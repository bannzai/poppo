/** 言語を書く文字の種類。返信の文が相手の言語で書かれたかを、文字の種類で数える時に使う */
export type WritingScript = 'latin' | 'hangul' | 'han' | 'kana';

/**
 * text が writingScript の文字で書かれているかを返す。
 * 見るのは文字の種類だけで、同じ文字を使う言語どうし (英語とスペイン語など) は見分けない (そこは返った文を読んで確かめる)。
 * 中国語 (han) は、漢字があって仮名もハングルも無い文とする (日本語の文にも漢字があるため)。
 * ラテン文字 (latin) は、ラテン文字があって漢字・仮名・ハングルが無い文とする
 */
export function isWrittenInScript(text: string, writingScript: WritingScript): boolean {
  switch (writingScript) {
    case 'hangul':
      return /\p{Script=Hangul}/u.test(text);
    case 'kana':
      return /[\p{Script=Hiragana}\p{Script=Katakana}]/u.test(text);
    case 'han':
      return /\p{Script=Han}/u.test(text) && !/[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(text);
    case 'latin':
      return /\p{Script=Latin}/u.test(text) && !/[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(text);
  }
}

/** 候補のモデル 1 つを、会話の見本 1 つで 1 回呼んだ結果 */
export type ReplyModelCall = {
  /** 呼んだモデルの名前 (提供元の API でのモデルの ID) */
  modelName: string;
  /** 渡した会話の見本の `id` */
  sampleID: string;
  /** 同じモデルと見本の組で何回目の呼び出しか (1 から) */
  runNumber: number;
  /** 呼んでから応答 (または失敗) が返るまでの時間 (ミリ秒) */
  durationMilliseconds: number;
  /** モデルが返した返信の文 3 つ。返信の文 3 つの形で返らなかった時は null */
  texts: string[] | null;
  /** 失敗した時の、エラーの種類と status (エラーの文は API キーの一部を含むことがあるため残さない)。成功した時は null */
  failure: string | null;
  /** 入力のトークンの数。提供元が返さなかった時と失敗した時は null */
  inputTokens: number | null;
  /** 出力の料金がかかるトークンの数 (思考のトークンを含む)。提供元が返さなかった時と失敗した時は null */
  billedOutputTokens: number | null;
};

/**
 * 出力の料金がかかるトークンの数を返す。
 * Gemini は出力の単価に思考のトークンを含め (料金の表の見出し「Output price (including thinking tokens)」 https://aistudio.google.com/docs/pricing 2026-11-22 に読んだ)、
 * plugin は思考のトークンを出力と別に返す (@genkit-ai/google-genai 1.44.0 の `thoughtsTokens: response.usageMetadata?.thoughtsTokenCount`) ため足す。
 * OpenAI の plugin は思考のトークンを別に返さない (@genkit-ai/compat-oai 1.44.0 は `outputTokens: response.usage?.completion_tokens` だけ)
 */
export function billedOutputTokensOfUsage(usage: { outputTokens?: number; thoughtsTokens?: number }): number | null {
  if (usage.outputTokens === undefined) {
    return null;
  }
  // thoughtsTokens が無いのは思考のトークンを別に返さない提供元で、足すものが無いため 0
  return usage.outputTokens + (usage.thoughtsTokens ?? 0);
}

/**
 * 失敗した呼び出しの error から、結果に残す文 (エラーの種類と、あれば status) を返す。
 * エラーの文 (message) は入れない (OpenAI は、キーが違う時の文に送ったキーの一部を入れるため。documents/DIRECTION.md「決めたこと」の 2026-11-21 の行)
 */
export function failureOfError(error: unknown): string {
  if (!(error instanceof Error)) {
    return 'unknown error';
  }
  return 'status' in error && (typeof error.status === 'string' || typeof error.status === 'number')
    ? `${error.name} status ${error.status}`
    : error.name;
}

/**
 * generate を 1 回実行し、返るまでの時間と結果を、call (どのモデルを・どの見本で・何回目か) と合わせて返す。
 * generate が失敗しても投げずに、失敗の内容 (`failureOfError`) を結果に入れる。
 * now は今の時刻をミリ秒で返す関数で、時間は generate の前後の now の差
 */
export async function measureReplyModelCall(
  call: Pick<ReplyModelCall, 'modelName' | 'sampleID' | 'runNumber'>,
  generate: () => Promise<{ texts: string[]; usage: { inputTokens?: number; outputTokens?: number; thoughtsTokens?: number } }>,
  // 既定は、時計の合わせ直しで戻らない performance.now (経過の時間を測るため)。テストは決まった時刻を返す関数を渡す
  now: () => number = () => performance.now(),
): Promise<ReplyModelCall> {
  const startedAt = now();
  try {
    const { texts, usage } = await generate();
    return {
      ...call,
      durationMilliseconds: now() - startedAt,
      texts,
      failure: null,
      // inputTokens が無いのは提供元がトークンの数を返さなかった時で、費用を計算しない
      inputTokens: usage.inputTokens ?? null,
      billedOutputTokens: billedOutputTokensOfUsage(usage),
    };
  } catch (error) {
    return {
      ...call,
      durationMilliseconds: now() - startedAt,
      texts: null,
      failure: failureOfError(error),
      inputTokens: null,
      billedOutputTokens: null,
    };
  }
}

/**
 * 実行の引数から、見本 1 つあたりの呼ぶ回数 (`runCount`)、測ると選ばれた候補 (`selectedModels`)、そのうち実際に呼ぶ候補 (`measuredModels`) を返す。
 * runs は `--runs` の値、modelNames は `--models` の値 (カンマ区切り。undefined は候補の全部)。
 * hasAPIKey が false を返した候補 (提供元の API キーが無い) は呼ばない。
 * runs が 1 以上の整数でない時と、呼ぶ回数 (呼ぶ候補の数 × sampleCount × runCount) が maximumCallCount を超える時は、Error を投げる (提供元を呼ぶ前に止めるため)
 */
export function planReplyModelCalls<Model extends { modelName: string }>(plan: {
  candidates: Model[];
  runs: string;
  modelNames: string | undefined;
  sampleCount: number;
  maximumCallCount: number;
  hasAPIKey: (model: Model) => boolean;
}): { runCount: number; selectedModels: Model[]; measuredModels: Model[] } {
  const runCount = Number(plan.runs);
  if (!Number.isInteger(runCount) || runCount < 1) {
    throw new Error(`--runs は 1 以上の整数にする: ${plan.runs}`);
  }
  const selectedModels = plan.candidates.filter(
    (model) => plan.modelNames === undefined || plan.modelNames.split(',').includes(model.modelName),
  );
  const measuredModels = selectedModels.filter(plan.hasAPIKey);
  if (measuredModels.length * plan.sampleCount * runCount > plan.maximumCallCount) {
    throw new Error(`呼ぶ回数が上限 (${plan.maximumCallCount} 回) を超える。--runs か --models で減らす`);
  }
  return { runCount, selectedModels, measuredModels };
}

/** トークンの数と 100 万トークンあたりの単価 (USD) から、1 回の呼び出しの費用 (USD) を返す */
export function costUSDOfTokens(tokens: {
  inputTokens: number;
  billedOutputTokens: number;
  inputUSDPerMillionTokens: number;
  outputUSDPerMillionTokens: number;
}): number {
  return (tokens.inputTokens * tokens.inputUSDPerMillionTokens + tokens.billedOutputTokens * tokens.outputUSDPerMillionTokens) / 1_000_000;
}

/** values の中央値を返す (偶数個の時は中央の 2 つの平均)。values が空の時は RangeError を投げる */
export function medianOf(values: number[]): number {
  if (values.length === 0) {
    throw new RangeError('medianOf: values is empty');
  }
  const sortedValues = [...values].sort((left, right) => left - right);
  const middleIndex = Math.floor(sortedValues.length / 2);
  return sortedValues.length % 2 === 1 ? sortedValues[middleIndex] : (sortedValues[middleIndex - 1] + sortedValues[middleIndex]) / 2;
}

/** 候補のモデル 1 つの、全部の呼び出しをまとめた数字 */
export type ReplyModelSummary = {
  /** モデルの名前 */
  modelName: string;
  /** 呼んだ回数 */
  callCount: number;
  /** 返信の文 3 つの形で返った回数 */
  threeTextsCallCount: number;
  /** 返った返信の文の数 (返信の文 3 つの形で返った回数の 3 倍) */
  textCount: number;
  /** 返った返信の文のうち、相手の言語の文字で書かれていた数 */
  textInThemWritingScriptCount: number;
  /** 返信の文 3 つの形で返った呼び出しの、返るまでの時間の中央値 (ミリ秒)。1 回も返らなかった時は null */
  medianDurationMilliseconds: number | null;
  /** 返信の文 3 つの形で返った呼び出しの、返るまでの時間の最も遅かった値 (ミリ秒)。1 回も返らなかった時は null */
  slowestDurationMilliseconds: number | null;
  /** トークンの数が分かった呼び出しの、入力のトークンの数の平均。1 回も分からなかった時は null */
  meanInputTokens: number | null;
  /** トークンの数が分かった呼び出しの、出力の料金がかかるトークンの数の平均。1 回も分からなかった時は null */
  meanBilledOutputTokens: number | null;
  /** トークンの数が分かった呼び出しの、1 回あたりの費用の平均 (USD)。1 回も分からなかった時は null */
  meanCostUSD: number | null;
};

/** values の平均を返す。values が空の時は null */
function meanOf(values: number[]): number | null {
  return values.length === 0 ? null : values.reduce((sum, value) => sum + value, 0) / values.length;
}

/**
 * calls のうち model.modelName の呼び出しをまとめた数字を返す。
 * themWritingScriptOfSampleID は、会話の見本の `id` から相手の言語の文字の種類を引く対応
 */
export function summarizeReplyModelCalls(
  model: { modelName: string; inputUSDPerMillionTokens: number; outputUSDPerMillionTokens: number },
  calls: ReplyModelCall[],
  themWritingScriptOfSampleID: Record<string, WritingScript>,
): ReplyModelSummary {
  const modelCalls = calls.filter((call) => call.modelName === model.modelName);
  const threeTextsCalls = modelCalls.flatMap((call) => (call.texts === null ? [] : [{ ...call, texts: call.texts }]));
  const measuredTokens = modelCalls.flatMap((call) =>
    call.inputTokens === null || call.billedOutputTokens === null
      ? []
      : [{ inputTokens: call.inputTokens, billedOutputTokens: call.billedOutputTokens }],
  );
  const durations = threeTextsCalls.map((call) => call.durationMilliseconds);
  return {
    modelName: model.modelName,
    callCount: modelCalls.length,
    threeTextsCallCount: threeTextsCalls.length,
    textCount: threeTextsCalls.reduce((count, call) => count + call.texts.length, 0),
    textInThemWritingScriptCount: threeTextsCalls.reduce(
      (count, call) => count + call.texts.filter((text) => isWrittenInScript(text, themWritingScriptOfSampleID[call.sampleID])).length,
      0,
    ),
    medianDurationMilliseconds: durations.length === 0 ? null : medianOf(durations),
    slowestDurationMilliseconds: durations.length === 0 ? null : Math.max(...durations),
    meanInputTokens: meanOf(measuredTokens.map((tokens) => tokens.inputTokens)),
    meanBilledOutputTokens: meanOf(measuredTokens.map((tokens) => tokens.billedOutputTokens)),
    meanCostUSD: meanOf(
      measuredTokens.map((tokens) =>
        costUSDOfTokens({
          ...tokens,
          inputUSDPerMillionTokens: model.inputUSDPerMillionTokens,
          outputUSDPerMillionTokens: model.outputUSDPerMillionTokens,
        }),
      ),
    ),
  };
}

/** 数字を、小数点以下 fractionDigits 桁の文にする。null は「-」にする (測れなかったことを 0 と見分けるため) */
function formatNumber(value: number | null, fractionDigits: number): string {
  return value === null ? '-' : value.toFixed(fractionDigits);
}

/** summaries を、モデルごとに 1 行の Markdown の表にして返す */
export function renderSummaryTable(summaries: ReplyModelSummary[]): string {
  return [
    '| モデル | 返信の文 3 つの形で返った回数 / 呼んだ回数 | 相手の言語の文字で書かれた文 / 返った文 | 返るまでの時間の中央値 (秒) | 最も遅かった値 (秒) | 入力のトークンの平均 | 出力のトークンの平均 (思考を含む) | 1 回あたりの費用 (USD) |',
    '| --- | --- | --- | --- | --- | --- | --- | --- |',
    ...summaries.map(
      (summary) =>
        `| \`${summary.modelName}\` | ${summary.threeTextsCallCount} / ${summary.callCount} | ${summary.textInThemWritingScriptCount} / ${summary.textCount} | ${formatNumber(
          summary.medianDurationMilliseconds === null ? null : summary.medianDurationMilliseconds / 1000,
          2,
        )} | ${formatNumber(summary.slowestDurationMilliseconds === null ? null : summary.slowestDurationMilliseconds / 1000, 2)} | ${formatNumber(
          summary.meanInputTokens,
          0,
        )} | ${formatNumber(summary.meanBilledOutputTokens, 0)} | ${formatNumber(summary.meanCostUSD, 6)} |`,
    ),
  ].join('\n');
}

/**
 * calls を、会話の見本ごと・モデルごとに、各回が返した返信の文 (失敗した回は失敗の内容) を並べた Markdown にして返す。
 * 見本とモデルは、sampleIDs と modelNames の順で並べる
 */
export function renderReplyTexts(sampleIDs: string[], modelNames: string[], calls: ReplyModelCall[]): string {
  return sampleIDs
    .map((sampleID) =>
      [
        `### ${sampleID}`,
        ...modelNames.flatMap((modelName) => [
          '',
          `\`${modelName}\``,
          '',
          ...calls
            .filter((call) => call.sampleID === sampleID && call.modelName === modelName)
            .map((call) =>
              call.texts === null
                ? `- ${call.runNumber} 回目: 失敗 (${call.failure})`
                : `- ${call.runNumber} 回目: ${call.texts.map((text) => `「${text.replaceAll('\n', ' ')}」`).join(' ')}`,
            ),
        ]),
      ].join('\n'),
    )
    .join('\n\n');
}
