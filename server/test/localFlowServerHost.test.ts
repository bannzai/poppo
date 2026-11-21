import assert from 'node:assert/strict';
import { request } from 'node:http';
import type { AddressInfo } from 'node:net';
import { after, before, beforeEach, test } from 'node:test';
import type { Server } from 'node:http';
import { genkit } from 'genkit';
import { mockModel } from 'genkit/testing';
import { defineGenerateReplyTextsFlow } from '../src/generateReplyTextsFlow.js';
import { startLocalFlowServer } from '../src/localFlowServer.js';

// 提供元の plugin を入れない ai。提供元の API は呼ばず、API キーも使わない
const ai = genkit({});
const model = mockModel(ai, { name: 'mockForHost' });
const generateReplyTexts = defineGenerateReplyTextsFlow(ai, () => model);

let server: Server;
/** サーバーが実際に待ち受けている port (0 を渡して OS に選ばせた番号) */
let listeningPort: number;

before(async () => {
  server = await startLocalFlowServer(generateReplyTexts, 0);
  listeningPort = (server.address() as AddressInfo).port;
});

after(() => new Promise((resolve) => server.close(resolve)));

beforeEach(() => {
  model.reset();
  model.respondWith({ text: JSON.stringify({ texts: ['a', 'b', 'c'] }) });
});

/**
 * 127.0.0.1 の listeningPort 番へ、Host ヘッダーを host にして flow を呼び、HTTP の状態と応答の本文を返す。
 * fetch は Host ヘッダーを指定できないため、node:http で送る
 */
function postWithHost(host: string): Promise<{ status: number | undefined; body: string }> {
  return new Promise((resolve, reject) => {
    const clientRequest = request(
      { host: '127.0.0.1', port: listeningPort, path: '/generateReplyTexts', method: 'POST', headers: { Host: host, 'Content-Type': 'application/json' } },
      (response) => {
        let body = '';
        response.on('data', (chunk) => (body += chunk));
        response.on('end', () => resolve({ status: response.statusCode, body }));
      },
    );
    clientRequest.once('error', reject);
    clientRequest.end(JSON.stringify({ data: { conversation: 'Them: Hello', provider: 'claude' } }));
  });
}

test('port に 0 を渡すと、OS が選んだ 0 でない番号で待ち受ける', () => {
  assert.notEqual(listeningPort, 0);
});

test('既に待ち受けている port で起動すると失敗する', async () => {
  await assert.rejects(startLocalFlowServer(generateReplyTexts, listeningPort), /EADDRINUSE/);
});

for (const hostName of ['127.0.0.1', 'localhost']) {
  test(`Host が ${hostName}:<待ち受けの port> の要求は flow を呼び、返信の文を返す`, async () => {
    assert.deepEqual(await postWithHost(`${hostName}:${listeningPort}`), { status: 200, body: JSON.stringify({ result: { texts: ['a', 'b', 'c'] } }) });
    assert.equal(model.requestCount, 1);
  });
}

for (const [name, host] of [
  ['別のドメイン', () => `attacker.example:${listeningPort}`],
  ['127.0.0.1 で始まる別のドメイン', () => `127.0.0.1.attacker.example:${listeningPort}`],
  ['localhost で始まる別のドメイン', () => `localhost.attacker.example:${listeningPort}`],
  ['127.0.0.1 の別の port', () => `127.0.0.1:${listeningPort + 1}`],
  ['port の無い 127.0.0.1', () => '127.0.0.1'],
  ['port の無い localhost', () => 'localhost'],
] as const) {
  test(`Host が ${name} の要求は 403 で断り、モデルを呼ばない`, async () => {
    const response = await postWithHost(host());

    assert.equal(response.status, 403);
    assert.equal(response.body.includes('texts'), false);
    assert.equal(model.requestCount, 0);
  });
}
