import assert from 'node:assert/strict';
import { createServer } from 'node:net';
import { beforeEach, test } from 'node:test';
import { genkit } from 'genkit';
import { mockModel } from 'genkit/testing';
import { defineGenerateReplyTextsFlow, replyInstructions, ReplyProviderSchema } from '../src/generateReplyTextsFlow.js';
import { startLocalFlowServer } from '../src/localFlowServer.js';

// 提供元の plugin を入れない ai。提供元の API は呼ばず、API キーも使わない
const ai = genkit({});

/** 提供元ごとの、提供元の API を呼ばないモデル。どの提供元のモデルが呼ばれたかを見分けるために提供元ごとに分ける */
const mockModelOfProvider = {
  claude: mockModel(ai, { name: 'mockClaude' }),
  openAI: mockModel(ai, { name: 'mockOpenAI' }),
  gemini: mockModel(ai, { name: 'mockGemini' }),
};

const generateReplyTexts = defineGenerateReplyTextsFlow(ai, (provider) => mockModelOfProvider[provider]);

/** テストで flow に渡す会話の文。アプリの `replyPrompt(messages:)` が作る形 */
const conversation = 'Them: Are you free tomorrow?\n\nMe: Let me check.\n\nThem: No rush!';

beforeEach(() => {
  for (const model of Object.values(mockModelOfProvider)) {
    model.reset();
  }
});

for (const provider of ReplyProviderSchema.options) {
  test(`${provider}: モデルが書いた返信の文 3 つを、文字列 3 つの配列で返す`, async () => {
    mockModelOfProvider[provider].respondWith({ text: JSON.stringify({ texts: ['Yes, I am.', 'Sorry, I am busy.', 'What time?'] }) });

    assert.deepEqual(await generateReplyTexts({ conversation, provider }), { texts: ['Yes, I am.', 'Sorry, I am busy.', 'What time?'] });
  });

  test(`${provider}: 指定した提供元のモデルだけを 1 回呼ぶ`, async () => {
    mockModelOfProvider[provider].respondWith({ text: JSON.stringify({ texts: ['a', 'b', 'c'] }) });

    await generateReplyTexts({ conversation, provider });

    assert.deepEqual(
      Object.fromEntries(Object.entries(mockModelOfProvider).map(([name, model]) => [name, model.requestCount])),
      { claude: 0, openAI: 0, gemini: 0, [provider]: 1 },
    );
  });
}

test('モデルへ、指示の文を system として、会話の文をそのまま利用者の発言として渡す', async () => {
  mockModelOfProvider.claude.respondWith({ text: JSON.stringify({ texts: ['a', 'b', 'c'] }) });

  await generateReplyTexts({ conversation, provider: 'claude' });

  assert.deepEqual(
    mockModelOfProvider.claude.lastRequest?.messages.map((message) => ({ role: message.role, content: message.content })),
    [
      { role: 'system', content: [{ text: replyInstructions }] },
      { role: 'user', content: [{ text: conversation }] },
    ],
  );
});

test('モデルへ、出力の形 (追加のプロパティを許さない、3 つの文字列の texts) を schema として渡す', async () => {
  mockModelOfProvider.openAI.respondWith({ text: JSON.stringify({ texts: ['a', 'b', 'c'] }) });

  await generateReplyTexts({ conversation, provider: 'openAI' });

  const schema = mockModelOfProvider.openAI.lastRequest?.output?.schema;
  assert.equal(schema?.additionalProperties, false);
  assert.deepEqual(schema?.required, ['texts']);
  assert.equal(schema?.properties.texts.type, 'array');
  assert.deepEqual(schema?.properties.texts.items, { type: 'string' });
  assert.equal(schema?.properties.texts.minItems, 3);
  assert.equal(schema?.properties.texts.maxItems, 3);
});

for (const [name, text] of [
  ['返信の文が 2 つ', JSON.stringify({ texts: ['a', 'b'] })],
  ['返信の文が 4 つ', JSON.stringify({ texts: ['a', 'b', 'c', 'd'] })],
  ['返信の文が 0 個', JSON.stringify({ texts: [] })],
  ['texts が文字列でない要素を含む', JSON.stringify({ texts: ['a', 'b', 3] })],
  ['texts が無い', JSON.stringify({ replies: ['a', 'b', 'c'] })],
  ['texts のほかにプロパティがある', JSON.stringify({ texts: ['a', 'b', 'c'], note: 'x' })],
  ['JSON でない文', 'Sure! Here are three replies.'],
  ['3 つ目の文の途中で切れた JSON', '{"texts":["Yes, I am.","Sorry, I am busy.","What ti'],
  ['3 つ目の文の後の閉じる括弧が無い JSON', '{"texts":["a","b","c"'],
  ['文の中に } があり、途中で切れた JSON', '{"texts":["a}","b","c'],
  ['空の文', ''],
] as const) {
  test(`モデルの出力が ${name} の時は失敗し、一部だけを返さない`, async () => {
    mockModelOfProvider.gemini.respondWith({ text });

    await assert.rejects(generateReplyTexts({ conversation, provider: 'gemini' }));
  });
}

for (const [name, text] of [
  ['コードブロックで囲んだ JSON', '```json\n{"texts":["a","b","c"]}\n```'],
  ['前に説明の文が付いた JSON', 'Here you go: {"texts":["a","b","c"]}'],
  ['後ろに波括弧を含む説明の文が付いた JSON', '{"texts":["a","b","c"]} Replace {name} if needed.'],
] as const) {
  test(`モデルの出力が ${name} の時は、中の返信の文 3 つを返す`, async () => {
    mockModelOfProvider.gemini.respondWith({ text });

    assert.deepEqual(await generateReplyTexts({ conversation, provider: 'gemini' }), { texts: ['a', 'b', 'c'] });
  });
}

test('モデルの出力が文でない部分 (data) で届いた時は、その返信の文 3 つを返す', async () => {
  mockModelOfProvider.claude.respondWith({ content: [{ data: { texts: ['a', 'b', 'c'] } }] });

  assert.deepEqual(await generateReplyTexts({ conversation, provider: 'claude' }), { texts: ['a', 'b', 'c'] });
});

test('モデルの出力が文でない部分 (data) で届き、返信の文が 2 つの時は失敗する', async () => {
  mockModelOfProvider.claude.respondWith({ content: [{ data: { texts: ['a', 'b'] } }] });

  await assert.rejects(generateReplyTexts({ conversation, provider: 'claude' }));
});

test('モデルの呼び出しが失敗した時は、その失敗を返す', async () => {
  mockModelOfProvider.claude.respondWith([new Error('rate limited')]);

  await assert.rejects(generateReplyTexts({ conversation, provider: 'claude' }), /rate limited/);
});

for (const [name, input] of [
  ['提供元が一覧に無い', { conversation, provider: 'llama' }],
  ['提供元が無い', { conversation }],
  ['会話の文が空', { conversation: '', provider: 'claude' }],
  ['会話の文が空白と改行だけ', { conversation: ' \n\t ', provider: 'claude' }],
  ['会話の文が無い', { provider: 'claude' }],
] as const) {
  test(`入力が ${name} の時は、どのモデルも呼ばずに失敗する`, async () => {
    // 型に合わない入力を渡した時の実行時の検査を確かめるため、型の検査を外す
    await assert.rejects(generateReplyTexts(input as never));

    assert.deepEqual(
      Object.values(mockModelOfProvider).map((model) => model.requestCount),
      [0, 0, 0],
    );
  });
}

/** 今このマシンで空いている TCP のポートの番号を返す。返した後にほかのプロセスが先に使うことはあり得る */
function findFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => (address !== null && typeof address === 'object' ? resolve(address.port) : reject(new Error('no port'))));
    });
  });
}

test('手元のサーバーは 127.0.0.1 だけで待ち受ける (このマシンの外から届かない)', async () => {
  const server = await startLocalFlowServer(generateReplyTexts, await findFreePort());
  try {
    const address = server.address();
    assert.ok(address !== null && typeof address === 'object');
    assert.equal(address.address, '127.0.0.1');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});

test('HTTP では、{"data": 入力} を POST すると {"result": 出力} が返り、形の合わない入力には成功でない応答を返して result を返さない', async () => {
  mockModelOfProvider.gemini.respondWith({ text: JSON.stringify({ texts: ['a', 'b', 'c'] }) });
  const port = await findFreePort();
  const server = await startLocalFlowServer(generateReplyTexts, port);
  try {
    const response = await fetch(`http://127.0.0.1:${port}/generateReplyTexts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { conversation, provider: 'gemini' } }),
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { result: { texts: ['a', 'b', 'c'] } });

    const invalidInputResponse = await fetch(`http://127.0.0.1:${port}/generateReplyTexts`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ data: { conversation, provider: 'llama' } }),
    });
    assert.equal(invalidInputResponse.ok, false);
    assert.equal('result' in ((await invalidInputResponse.json()) as object), false);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});
