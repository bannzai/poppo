import type { Server } from 'node:http';
import type { AddressInfo } from 'node:net';
import { expressHandler } from '@genkit-ai/express';
import express from 'express';
import type { Action } from 'genkit';

/**
 * flow を、このマシンの中からだけ届く HTTP のサーバー (127.0.0.1 の port 番。0 なら空いている番号) として起動し、
 * 待ち受けが始まったサーバーを返す。
 * 呼び方は `POST /<flow の名前>` に `{"data": 入力}`。成功の応答は `{"result": 出力}`。
 * Host ヘッダーが `127.0.0.1:<待ち受けの port>` でも `localhost:<待ち受けの port>` でもない要求は、flow を呼ばずに 403 で断る。
 * 待ち受けを 127.0.0.1 に絞るのは、呼び出しの確かめ (認証・回数の制限) を持たないため。
 * `@genkit-ai/express` の `startFlowServer` は待ち受けのアドレスを指定できず、全てのインターフェースで待ち受ける
 * (`server.listen(this.port, ...)`。1.44.0 の実装) ので、同じネットワークのほかの端末から、起動した人の API キーでモデルを呼べてしまう。
 * Host を確かめるのは、起動中にこのマシンのブラウザで開いたページが、自分のドメインの名前の解決先を 127.0.0.1 に切り替えて
 * (DNS rebinding) 同じ flow を呼ぶ経路を断つため (その要求の Host はページのドメインになる)。
 * 冪等ではない: 呼ぶたびにサーバーを 1 つ起動する。0 以外の同じ port で 2 回呼ぶと 2 回目は失敗する
 */
export function startLocalFlowServer(flow: Action, port: number): Promise<Server> {
  const app = express();
  return new Promise((resolve, reject) => {
    const server = app.listen(port, '127.0.0.1');
    app.use((request, response, next) => {
      const listeningPort = (server.address() as AddressInfo).port;
      if (request.headers.host === `127.0.0.1:${listeningPort}` || request.headers.host === `localhost:${listeningPort}`) {
        next();
      } else {
        response.status(403).json({ message: 'This server accepts requests only for 127.0.0.1 or localhost.' });
      }
    });
    app.use(express.json());
    app.post(`/${flow.__action.name}`, expressHandler(flow));
    server.once('listening', () => resolve(server));
    server.once('error', reject);
  });
}
