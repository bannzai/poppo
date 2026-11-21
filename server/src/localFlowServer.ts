import type { Server } from 'node:http';
import { expressHandler } from '@genkit-ai/express';
import express from 'express';
import type { Action } from 'genkit';

/**
 * flow を、このマシンの中からだけ届く HTTP のサーバー (127.0.0.1 の port 番) として起動し、待ち受けが始まったサーバーを返す。
 * 呼び方は `POST /<flow の名前>` に `{"data": 入力}`。成功の応答は `{"result": 出力}`。
 * 待ち受けを 127.0.0.1 に絞るのは、呼び出しの確かめ (認証・回数の制限) を持たないため。
 * `@genkit-ai/express` の `startFlowServer` は待ち受けのアドレスを指定できず、全てのインターフェースで待ち受ける
 * (`server.listen(this.port, ...)`。1.44.0 の実装) ので、同じネットワークのほかの端末から、起動した人の API キーでモデルを呼べてしまう。
 * 冪等ではない: 呼ぶたびにサーバーを 1 つ起動する。同じ port で 2 回呼ぶと 2 回目は失敗する
 */
export function startLocalFlowServer(flow: Action, port: number): Promise<Server> {
  const app = express();
  app.use(express.json());
  app.post(`/${flow.__action.name}`, expressHandler(flow));
  return new Promise((resolve, reject) => {
    const server = app.listen(port, '127.0.0.1');
    server.once('listening', () => resolve(server));
    server.once('error', reject);
  });
}
