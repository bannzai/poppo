import assert from 'node:assert/strict';
import { test } from 'node:test';
import {
  billedOutputTokensOfUsage,
  costUSDOfTokens,
  failureOfError,
  isWrittenInScript,
  measureReplyModelCall,
  medianOf,
  planReplyModelCalls,
  renderReplyTexts,
  renderSummaryTable,
  summarizeReplyModelCalls,
  type ReplyModelCall,
} from '../benchmark/benchmarkMeasures.js';
import { candidateReplyModels } from '../benchmark/candidateReplyModels.js';
import { conversationSamples } from '../benchmark/conversationSamples.js';
import { ReplyProviderSchema } from '../src/generateReplyTextsFlow.js';

// 文字の種類ごとに、その文字で書かれた文 (該当する側) と、似ているが別の文字の文 (該当しない側) の両方を置く
for (const [writingScript, text, expected] of [
  ['latin', 'Sounds good, see you at 8!', true],
  ['latin', '¡Claro! Llevo un postre.', true],
  ['latin', 'OK、行きます', false],
  ['latin', '👍 2024', false],
  ['hangul', '네, 목요일까지 보내드리겠습니다.', true],
  ['hangul', 'Yes, by Thursday.', false],
  ['han', '好的，周末一起吃饭吧。', true],
  ['han', '週末に食べに行きましょう。', false],
  ['han', '周末 같이 먹어요', false],
  ['kana', '週末に食べに行きましょう。', true],
  ['kana', 'カフェ', true],
  ['kana', '好的，周末一起吃饭吧。', false],
] as const) {
  test(`「${text}」は ${writingScript} の文字で書かれて${expected ? 'いる' : 'いない'}`, () => {
    assert.equal(isWrittenInScript(text, writingScript), expected);
  });
}

test('出力の料金がかかるトークンの数は、出力のトークンに思考のトークンを足した数', () => {
  assert.equal(billedOutputTokensOfUsage({ outputTokens: 40, thoughtsTokens: 160 }), 200);
});

test('思考のトークンを返さない提供元では、出力のトークンの数のまま', () => {
  assert.equal(billedOutputTokensOfUsage({ outputTokens: 40 }), 40);
});

test('出力のトークンの数が返らなかった時は、数えられないので null (思考のトークンだけを数にしない)', () => {
  assert.equal(billedOutputTokensOfUsage({ thoughtsTokens: 160 }), null);
});

test('費用は、入力と出力それぞれのトークンの数に 100 万トークンあたりの単価を掛けた和', () => {
  // 入力 200 × $0.30 / 100 万 = $0.00006、出力 100 × $2.50 / 100 万 = $0.00025
  assert.ok(
    Math.abs(costUSDOfTokens({ inputTokens: 200, billedOutputTokens: 100, inputUSDPerMillionTokens: 0.3, outputUSDPerMillionTokens: 2.5 }) - 0.00031) <
      1e-12,
  );
});

test('トークンが 0 の時の費用は 0', () => {
  assert.equal(costUSDOfTokens({ inputTokens: 0, billedOutputTokens: 0, inputUSDPerMillionTokens: 0.3, outputUSDPerMillionTokens: 2.5 }), 0);
});

for (const [values, expected] of [
  [[5], 5],
  [[3, 1, 2], 2],
  [[4, 1, 3, 2], 2.5],
  // 文字の順 (10 が 9 より前) ではなく数の順で並べる
  [[10, 9, 100], 10],
] as const) {
  test(`${JSON.stringify(values)} の中央値は ${expected}`, () => {
    assert.equal(medianOf([...values]), expected);
  });
}

test('空の時の中央値は RangeError', () => {
  assert.throws(() => medianOf([]), RangeError);
});

test('中央値を出しても、渡した配列の並びは変えない', () => {
  const values = [3, 1, 2];
  medianOf(values);
  assert.deepEqual(values, [3, 1, 2]);
});

test('失敗の文には、エラーの種類と status だけを入れ、エラーの文 (API キーの一部を含み得る) を入れない', () => {
  assert.equal(
    failureOfError(Object.assign(new Error('Incorrect API key provided: sk-proj-abc***xyz'), { name: 'AuthenticationError', status: 401 })),
    'AuthenticationError status 401',
  );
});

test('status が文字列のエラー (Genkit のエラー) の失敗の文にも、status を入れる', () => {
  assert.equal(
    failureOfError(Object.assign(new Error('The model did not return three reply texts.'), { name: 'GenkitError', status: 'INTERNAL' })),
    'GenkitError status INTERNAL',
  );
});

test('status の無いエラーの失敗の文は、エラーの種類だけ', () => {
  assert.equal(failureOfError(new TypeError('fetch failed for key sk-proj-abc')), 'TypeError');
});

test('Error でないものが投げられた時の失敗の文は unknown error (投げられた値を入れない)', () => {
  assert.equal(failureOfError('sk-proj-abc'), 'unknown error');
});

/** 呼ぶたびに times の値を順に返す、時刻の関数を作る (計測のテストで、返るまでの時間を決まった値にするため) */
function clockReturning(times: number[]) {
  const remainingTimes = [...times];
  return () => {
    const time = remainingTimes.shift();
    assert.ok(time !== undefined, '時刻が想定より多く読まれた');
    return time;
  };
}

/** 計画のテストで使う候補。b は API キーが無い提供元のモデルとして扱う */
const planCandidates = [{ modelName: 'a' }, { modelName: 'b' }, { modelName: 'c' }];

/** planCandidates を、b だけ API キーが無いものとして計画する (上書きする引数だけを渡す) */
function plan(overrides: { runs?: string; modelNames?: string; sampleCount?: number; maximumCallCount?: number }) {
  return planReplyModelCalls({
    candidates: planCandidates,
    runs: '3',
    modelNames: undefined,
    sampleCount: 8,
    maximumCallCount: 300,
    hasAPIKey: (model) => model.modelName !== 'b',
    ...overrides,
  });
}

test('モデルを指定しない計画は、候補の全部を選び、API キーの無い提供元のモデルだけを呼ばない', () => {
  assert.deepEqual(plan({}), {
    runCount: 3,
    selectedModels: [{ modelName: 'a' }, { modelName: 'b' }, { modelName: 'c' }],
    measuredModels: [{ modelName: 'a' }, { modelName: 'c' }],
  });
});

test('モデルを指定した計画は、指定した名前の候補だけを選ぶ (候補に無い名前は選ばない)', () => {
  assert.deepEqual(plan({ modelNames: 'c,b,unknown' }), {
    runCount: 3,
    selectedModels: [{ modelName: 'b' }, { modelName: 'c' }],
    measuredModels: [{ modelName: 'c' }],
  });
});

for (const runs of ['0', '-1', '1.5', 'abc', '']) {
  test(`--runs が「${runs}」の計画は失敗する`, () => {
    assert.throws(() => plan({ runs }), /--runs は 1 以上の整数にする/);
  });
}

test('--runs が 1 の計画は通る', () => {
  assert.equal(plan({ runs: '1' }).runCount, 1);
});

test('呼ぶ回数が上限ちょうどの計画は通る (呼ばない候補は回数に数えない)', () => {
  // 呼ぶ候補 2 つ × 見本 8 つ × 3 回 = 48 回
  assert.equal(plan({ maximumCallCount: 48 }).measuredModels.length, 2);
});

test('呼ぶ回数が上限を 1 回超える計画は失敗する', () => {
  assert.throws(() => plan({ maximumCallCount: 47 }), /呼ぶ回数が上限 \(47 回\) を超える/);
});

test('1 回の呼び出しの計測は、返った返信の文とトークンの数を、どの呼び出しかと合わせて返す', async () => {
  assert.deepEqual(
    await measureReplyModelCall(
      { modelName: 'model-a', sampleID: 'english', runNumber: 2 },
      async () => ({ texts: ['a', 'b', 'c'], usage: { inputTokens: 120, outputTokens: 30, thoughtsTokens: 50 } }),
      // 呼ぶ前が 1000、返った後が 3500
      clockReturning([1000, 3500]),
    ),
    {
      modelName: 'model-a',
      sampleID: 'english',
      runNumber: 2,
      durationMilliseconds: 2500,
      texts: ['a', 'b', 'c'],
      failure: null,
      inputTokens: 120,
      billedOutputTokens: 80,
    },
  );
});

test('1 回の呼び出しの計測は、提供元がトークンの数を返さなかった時、トークンの数を null にする (0 にしない)', async () => {
  const { inputTokens, billedOutputTokens } = await measureReplyModelCall({ modelName: 'model-a', sampleID: 'english', runNumber: 1 }, async () => ({
    texts: ['a', 'b', 'c'],
    usage: {},
  }));

  assert.deepEqual([inputTokens, billedOutputTokens], [null, null]);
});

test('1 回の呼び出しの計測は、呼び出しが失敗しても投げずに、失敗の内容を結果に入れる', async () => {
  assert.deepEqual(
    await measureReplyModelCall(
      { modelName: 'model-a', sampleID: 'english', runNumber: 1 },
      async () => {
        throw Object.assign(new Error('Incorrect API key provided: sk-proj-abc***xyz'), { name: 'AuthenticationError', status: 401 });
      },
      // 呼ぶ前が 200、失敗した後が 60200 (打ち切りの 60 秒)
      clockReturning([200, 60200]),
    ),
    {
      modelName: 'model-a',
      sampleID: 'english',
      runNumber: 1,
      durationMilliseconds: 60000,
      texts: null,
      failure: 'AuthenticationError status 401',
      inputTokens: null,
      billedOutputTokens: null,
    },
  );
});

/** まとめのテストで使う、モデル 2 つ・見本 2 つの呼び出しの結果 */
const calls: ReplyModelCall[] = [
  {
    modelName: 'model-a',
    sampleID: 'english',
    runNumber: 1,
    durationMilliseconds: 1000,
    texts: ['Sure!', 'Sorry, I cannot.', 'いいですね'],
    failure: null,
    inputTokens: 100,
    billedOutputTokens: 20,
  },
  {
    modelName: 'model-a',
    sampleID: 'korean',
    runNumber: 1,
    durationMilliseconds: 3000,
    texts: ['네, 알겠습니다.', 'Thursday is fine.', '목요일까지 보내드리겠습니다.'],
    failure: null,
    inputTokens: 300,
    billedOutputTokens: 40,
  },
  {
    modelName: 'model-a',
    sampleID: 'korean',
    runNumber: 2,
    durationMilliseconds: 60000,
    texts: null,
    failure: 'GenkitError status INTERNAL',
    inputTokens: null,
    billedOutputTokens: null,
  },
  {
    modelName: 'model-b',
    sampleID: 'english',
    runNumber: 1,
    durationMilliseconds: 500,
    texts: ['a', 'b', 'c'],
    failure: null,
    inputTokens: 1,
    billedOutputTokens: 1,
  },
];

test('モデルごとのまとめは、そのモデルの呼び出しだけを数え、失敗した回を時間・トークン・費用に入れない', () => {
  assert.deepEqual(
    summarizeReplyModelCalls({ modelName: 'model-a', inputUSDPerMillionTokens: 1_000_000, outputUSDPerMillionTokens: 2_000_000 }, calls, {
      english: 'latin',
      korean: 'hangul',
    }),
    {
      modelName: 'model-a',
      callCount: 3,
      threeTextsCallCount: 2,
      textCount: 6,
      // english の 3 つのうちラテン文字は 2 つ、korean の 3 つのうちハングルは 2 つ
      textInThemWritingScriptCount: 4,
      medianDurationMilliseconds: 2000,
      slowestDurationMilliseconds: 3000,
      meanInputTokens: 200,
      meanBilledOutputTokens: 30,
      // 単価を 1 トークンあたり入力 $1・出力 $2 にしてある: (100 + 2 × 20 + 300 + 2 × 40) / 2
      meanCostUSD: 260,
    },
  );
});

test('1 回も返信の文が返らなかったモデルのまとめは、時間・トークン・費用を null にする (0 にしない)', () => {
  assert.deepEqual(
    summarizeReplyModelCalls({ modelName: 'model-a', inputUSDPerMillionTokens: 1, outputUSDPerMillionTokens: 1 }, [calls[2]], { korean: 'hangul' }),
    {
      modelName: 'model-a',
      callCount: 1,
      threeTextsCallCount: 0,
      textCount: 0,
      textInThemWritingScriptCount: 0,
      medianDurationMilliseconds: null,
      slowestDurationMilliseconds: null,
      meanInputTokens: null,
      meanBilledOutputTokens: null,
      meanCostUSD: null,
    },
  );
});

test('まとめの表は、モデルごとに 1 行で、時間を秒に直し、測れなかった数字を「-」にする', () => {
  assert.deepEqual(
    renderSummaryTable([
      {
        modelName: 'model-a',
        callCount: 3,
        threeTextsCallCount: 2,
        textCount: 6,
        textInThemWritingScriptCount: 4,
        medianDurationMilliseconds: 2000,
        slowestDurationMilliseconds: 3456,
        meanInputTokens: 200.4,
        meanBilledOutputTokens: 30,
        meanCostUSD: 0.0001234,
      },
      {
        modelName: 'model-b',
        callCount: 1,
        threeTextsCallCount: 0,
        textCount: 0,
        textInThemWritingScriptCount: 0,
        medianDurationMilliseconds: null,
        slowestDurationMilliseconds: null,
        meanInputTokens: null,
        meanBilledOutputTokens: null,
        meanCostUSD: null,
      },
    ])
      .split('\n')
      .slice(2),
    ['| `model-a` | 2 / 3 | 4 / 6 | 2.00 | 3.46 | 200 | 30 | 0.000123 |', '| `model-b` | 0 / 1 | 0 / 0 | - | - | - | - | - |'],
  );
});

test('返信の文の一覧は、見本ごと・モデルごとに各回の文を並べ、失敗した回は失敗の内容を出し、文の中の改行を空白にする', () => {
  assert.equal(
    renderReplyTexts(
      ['korean', 'english'],
      ['model-a', 'model-b'],
      [...calls, { ...calls[3], runNumber: 2, texts: ['line 1\nline 2', 'b', 'c'] }],
    ),
    [
      '### korean',
      '',
      '`model-a`',
      '',
      '- 1 回目: 「네, 알겠습니다.」 「Thursday is fine.」 「목요일까지 보내드리겠습니다.」',
      '- 2 回目: 失敗 (GenkitError status INTERNAL)',
      '',
      '`model-b`',
      '',
      '',
      '### english',
      '',
      '`model-a`',
      '',
      '- 1 回目: 「Sure!」 「Sorry, I cannot.」 「いいですね」',
      '',
      '`model-b`',
      '',
      '- 1 回目: 「a」 「b」 「c」',
      '- 2 回目: 「line 1 line 2」 「b」 「c」',
    ].join('\n'),
  );
});

for (const provider of ReplyProviderSchema.options) {
  test(`候補のモデルは、${provider} を 2 つ以上含む`, () => {
    assert.ok(candidateReplyModels.filter((model) => model.provider === provider).length >= 2);
  });
}

for (const modelName of ['gpt-5.4-mini', 'gpt-6-luna']) {
  test(`候補のモデルは、OpenAI の ${modelName} を含む`, () => {
    assert.ok(candidateReplyModels.some((model) => model.provider === 'openAI' && model.modelName === modelName));
  });
}

test('OpenAI のほかの提供元の候補は、OpenAI の strict の指定を付けない', () => {
  assert.deepEqual(
    candidateReplyModels.filter((model) => model.provider !== 'openAI' && model.usesStrictOutput),
    [],
  );
});

test('候補のモデルの名前は重ならない (結果をモデルの名前で分けるため)', () => {
  assert.equal(new Set(candidateReplyModels.map((model) => model.modelName)).size, candidateReplyModels.length);
});

test('会話の見本は 5 つ以上で、英語のほかの言語 (ラテン文字でない文字の言語) を含む', () => {
  assert.ok(conversationSamples.length >= 5);
  assert.ok(conversationSamples.some((sample) => sample.themWritingScript !== 'latin'));
});

test('会話の見本の名前は重ならない (結果を見本の名前で分けるため)', () => {
  assert.equal(new Set(conversationSamples.map((sample) => sample.id)).size, conversationSamples.length);
});

for (const sample of conversationSamples) {
  test(`会話の見本 ${sample.id} は、アプリの replyPrompt が作る形 (どの発言も Me: か Them: で始まり、空行で区切る) で、最後が相手の発言`, () => {
    const messages = sample.conversation.split('\n\n');
    assert.ok(messages.every((message) => /^(Me|Them): \S/.test(message)));
    assert.ok(messages.at(-1)?.startsWith('Them: '));
  });

  test(`会話の見本 ${sample.id} の相手の発言は、themWritingScript (${sample.themWritingScript}) の文字で書かれている`, () => {
    assert.ok(
      sample.conversation
        .split('\n\n')
        .filter((message) => message.startsWith('Them: '))
        .every((message) => isWrittenInScript(message.slice('Them: '.length), sample.themWritingScript)),
    );
  });
}
