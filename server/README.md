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

自分の API キーで実際のモデルを呼んで試す時だけ使う。利用料がかかる。呼び出しの確かめ (認証・回数の制限) が無いため、このマシンの中からだけ届くアドレス (127.0.0.1) で待ち受け、Host ヘッダーが `127.0.0.1:<port>` か `localhost:<port>` の要求だけを受ける (ブラウザで開いたほかのページから呼ばれないようにするため)。

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

## モデルを比べる

候補のモデル (`benchmark/candidateReplyModels.ts`) を、同じ会話の見本 (`benchmark/conversationSamples.ts`) で実際に呼んで、モデルごとに次を出す: 返信の文 3 つの形で返った回数と呼んだ回数、相手の言語の文字で書かれた文の数、返るまでの時間の中央値と最も遅かった値 (返信の文 3 つの形で返った呼び出しだけの時間で、失敗した回と打ち切った回は入らない。失敗の数は、返った回数と呼んだ回数の差で読む)、入力と出力のトークンの数の平均、1 回あたりの費用。その下に、各モデルが返した返信の文の実物を見本ごとに並べる。提供元の API を呼ぶため利用料がかかる (2026-11-22 の実測: OpenAI の 4 つを見本 8 つ × 3 回で約 0.04 USD)。

API キーは「手元での起動」と同じ環境変数で渡す。キーの無い提供元のモデルは呼ばず、「測っていない」と出す。

```sh
cd server
npm ci
npm run benchmark --silent > ../tmp/benchmark.md
```

- `--runs <回数>`: 見本 1 つあたりの呼ぶ回数 (指定しない時は 3)
- `--models <名前,名前>`: 測るモデルを絞る (指定しない時は候補の全部。候補に無い名前があると、呼ぶ前に失敗する)
- `--output <ファイル>`: 全部の呼び出しの結果を JSON で書き出す

1 回の実行で呼ぶ回数が 300 回を超える指定は、呼ぶ前に失敗する。1 回の呼び出しは 60 秒で打ち切って失敗に数える。失敗した呼び出しは、エラーの種類と status だけを結果に出す (エラーの文は API キーの一部を含むことがあるため出さない。plugin が標準エラーに出す記録には文が含まれるので、標準エラーをファイルに残してコミットしない)。

単価は `benchmark/candidateReplyModels.ts` に書いてある。料金が変わった時と候補を足す時は、出典のページを読み直してから直す。測った結果と提案は [../documents/evaluation/2026-11-22-reply-model-benchmark.md](../documents/evaluation/2026-11-22-reply-model-benchmark.md)。

## モデルへの指示の文

正はアプリの `replyInstructions` (`Poppo/ChatReading/ReplyGeneration.swift`) で、`src/generateReplyTextsFlow.ts` の文はその写し。アプリの文を変えた時は、ここも同じ文に直す (違うと `test/replyInstructionsMatchApp.test.ts` が落ちる)。
