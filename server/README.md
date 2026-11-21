# server

端末の外のモデル (Claude・OpenAI・Gemini) で返信の文を作る、サーバーの側の処理。Genkit ( https://genkit.dev ) の flow として書いてある。どこにもデプロイしておらず、アプリからも呼んでいない。置き場所・費用・呼び出しの確かめ方は [documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md](../documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md) の案を owner が決めてから足す。

アプリのターゲットには入らない (Xcode の同期フォルダの外)。

## テスト

提供元の API は呼ばず、API キーも使わない (モデルを Genkit の `mockModel` に差し替える)。PR の CI (`.github/workflows/ci.yml` の `server-tests`) が同じコマンドを流す。

```sh
cd server
npm ci
npm run typecheck
npm test
```

Node.js は 22 以降。

## 手元での起動

自分の API キーで実際のモデルを呼んで試す時だけ使う。利用料がかかる。呼び出しの確かめ (認証・回数の制限) が無いため、このマシンの中からだけ届くアドレス (127.0.0.1) で待ち受ける。

API キーは環境変数で渡す (`ANTHROPIC_API_KEY`・`OPENAI_API_KEY`・`GEMINI_API_KEY`)。値をファイルに書いてコミットしない。持っている提供元の分だけでよく、キーの無い提供元を指定した呼び出しは失敗する。

```sh
cd server
npm ci
PORT=3400 npm start
```

別の端末から呼ぶ。`conversation` は、アプリの `replyPrompt(messages:)` が作る形 (利用者自身の発言に「Me:」、相手の発言に「Them:」) の文。`provider` は `claude`・`openAI`・`gemini`。

```sh
curl -X POST http://127.0.0.1:3400/generateReplyTexts \
  -H 'Content-Type: application/json' \
  -d '{"data": {"conversation": "Them: Are you free tomorrow?", "provider": "gemini"}}'
```

返信の文 3 つが `{"result": {"texts": ["...", "...", "..."]}}` の形で返る。

## モデルへの指示の文

正はアプリの `replyInstructions` (`Poppo/ChatReading/ReplyGeneration.swift`) で、`src/generateReplyTextsFlow.ts` の文はその写し。アプリの文を変えた時は、ここも同じ文に直す (違うと `test/replyInstructionsMatchApp.test.ts` が落ちる)。
