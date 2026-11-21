# 0003. 端末の外のモデルの返信案は、API キーをサーバーに置いた Genkit の flow を経由して作る

## Status
Proposed (2026-11-21)

owner (bannzai) が下の「owner が決めること」を決めるまでの案。決まったら Accepted にするか書き直す。この ADR で足したのはリポジトリの中のサーバーの処理 (`server/`) とそのテストだけで、どこにもデプロイしていない。アプリの動きは変えておらず、利用者に配るビルドは `documents/adr/0002-process-on-device-without-backend.md` のとおり端末内だけで作る。

## Context

owner は、返信案を作るモデルを端末内だけに決めず、Claude・OpenAI・Gemini でも作れるようにすると決めた ( https://github.com/bannzai/poppo/issues/1#issuecomment-7019893647 )。開発中に比べるための実装 ( https://github.com/bannzai/poppo/issues/39 ) は、開発者が自分の API キーを端末の Keychain に入れる形で、利用者に配るアプリには使えない。owner は次のように指定した ( https://github.com/bannzai/poppo/issues/1#issuecomment-7055573516 )。

> 承認。ただ、将来的にGenKitに書き換えた方が筋が良いし安全な気もしたからそのissueを立てて並行して進めておいて。リリース前には絶対対応する。

「GenKit」を Genkit ( https://genkit.dev ) と読み、「安全」を、API キーを利用者の端末ではなくサーバーに置けること・サーバーで呼び出しを確かめて制限できることと読んだのは agent ( https://github.com/bannzai/poppo/issues/40 )。

下の「確かめたこと」は、2026-11-21 に各文書を読み直し、引用した文がそのページにあることを機械的に照合した結果 (ページを取得して、タグを除いた本文に引用の文が含まれるかを見た)。「実測」と書いた行は、`server/` に入れた版 (genkit 1.44.0・@genkit-ai/express 1.44.0・@genkit-ai/anthropic 0.7.0・@genkit-ai/compat-oai 1.44.0・@genkit-ai/google-genai 1.44.0) を手元で動かした結果。

### 確かめたこと: Genkit

| 項目 | 分かったこと |
| --- | --- |
| 言語 | 「Google's open-source framework for building AI-powered apps and agents in TypeScript, Go, Python, and Dart.」( https://genkit.dev/docs/get-started/ )。同じページの言語の切り替えは「TypeScript」「Go」「Dart」「Python (Preview)」で、Preview と付くのは Python だけ。「As of version 1.0, Genkit is considered Generally Available (GA) and ready for production use」( https://genkit.dev/docs/api-stability/ )。言語ごとの文書 (`https://genkit.dev/docs/<go・dart・python>/...`) は、Go を「Everything in `github.com/firebase/genkit/go` except the packages listed below is stable」「The module requires Go 1.25 or later」( https://genkit.dev/docs/go/api-stability/ )、Dart を「As of version 1.0, Genkit Dart is Generally Available (GA) and ready for production use.」( https://genkit.dev/docs/dart/api-stability/ )、Python を「Genkit Python is in preview (0.*)」で破壊的な変更が minor の版で入る ( https://genkit.dev/docs/python/api-stability/ ) と書く |
| 提供元の plugin (TypeScript) | Claude: `@genkit-ai/anthropic` (「package is the official Anthropic plugin for Genkit」。キーは `ANTHROPIC_API_KEY`。 https://genkit.dev/docs/integrations/anthropic/ )。OpenAI: `@genkit-ai/compat-oai` (キーは `OPENAI_API_KEY`。 https://genkit.dev/docs/integrations/openai/ )。Gemini: `@genkit-ai/google-genai` (キーは `GEMINI_API_KEY`。 https://genkit.dev/docs/integrations/google-genai/ )。|
| 提供元の plugin (Go・Dart・Python) | 3 社の plugin の文書が、3 つの言語のどれにもある。Go: `github.com/firebase/genkit/go/plugins/anthropic`・`.../plugins/compat_oai/openai`・`.../plugins/googlegenai` ( https://genkit.dev/docs/go/integrations/anthropic/ 、 https://genkit.dev/docs/go/integrations/openai/ 、 https://genkit.dev/docs/go/integrations/google-genai/ )。Dart: `genkit_anthropic`・`genkit_openai`・`genkit_google_genai` ( https://genkit.dev/docs/dart/integrations/anthropic/ 、 https://genkit.dev/docs/dart/integrations/openai/ 、 https://genkit.dev/docs/dart/integrations/google-genai/ )。Python: 3 社のページがある (`https://genkit.dev/docs/python/integrations/<anthropic・openai・google-genai>/` が 200 を返す。中身は読んでいない)。キーの環境変数の名前は TypeScript と同じ。Go・Dart・Python の plugin は動かしていない |
| 出力の形 | Zod の schema を `output: { schema }` に渡す。Genkit が出力を schema と照合する (「Verifies that the output conforms with the schema」)。合わない時は `output` が null になり得る (「property can be `null`」。どちらも https://genkit.dev/docs/models/ )。OpenAI は「Set `strict: true` to have OpenAI enforce your output schema exactly」「OpenAI's strict mode requires `additionalProperties: false` on every object, and Genkit does not add it for you」( https://genkit.dev/docs/integrations/openai/ )。Claude は、schema の一部の制約を API の側では強制しない (「are not enforced by the API's constrained decoding」 https://genkit.dev/docs/integrations/anthropic/ )。配列の要素の数がこれに当たるかは確かめていないが、Genkit の照合で 3 つでない出力は失敗になる (実測: `server/test/generateReplyTextsFlow.test.ts` の「返信の文が 2 つ」「4 つ」の場合) |
| テストでのモデルの差し替え | 「The `genkit/testing` module provides mock models that stand in for a real provider model」( https://genkit.dev/docs/testing/ )。`mockModel(ai, { name })` に `respondWith({ text })` で応答を決める。提供元の API も API キーも使わない |
| 置き場所 | Cloud Functions for Firebase は `onCallGenkit` で flow を包む。「Upgrade the project to the Blaze plan, which is required to deploy Cloud Functions.」「your API key is stored in Cloud Secret Manager, and available from the Cloud Functions environment」( https://genkit.dev/docs/deployment/firebase/ )。Cloud Run と Node が動く host は `@genkit-ai/express` の `startFlowServer` か `expressHandler` で HTTP に出す ( https://genkit.dev/docs/deployment/cloud-run/ 、 https://genkit.dev/docs/frameworks/express/ 。後者は「Node.js v20 or later」を前提に挙げる)。Cloud Functions for Firebase への配置の文書があるのは TypeScript だけで、Go・Dart・Python の同じページは無い (`https://genkit.dev/docs/<go・dart・python>/deployment/firebase/` は 3 つとも 404)。3 つの言語の配置の一覧は Cloud Run と任意の host の 2 つ (Go: 「Any platform: manually deploy a Go Genkit server to any host.」 https://genkit.dev/docs/go/deployment/overview/ 。Dart: 「manually deploy a Dart Genkit server to any host」 https://genkit.dev/docs/dart/deployment/overview/ 。Python: 「manually deploy a Python Genkit server to any host」 https://genkit.dev/docs/python/deployment/overview/ )。Go の HTTP の入口は呼び出しを確かめず、自分で組む (「Authentication, identity verification, and access policies are configured at the application level using context providers and HTTP middleware.」 https://genkit.dev/docs/go/deployment/authorization/ )。`startFlowServer` は待ち受けのアドレスを指定できず全てのインターフェースで待ち受ける (1.44.0 の実装の `server.listen(this.port, ...)`) ため、`server/` の手元の起動口は `expressHandler` を 127.0.0.1 だけで待ち受けさせる |
| 呼び出しの確かめ方 | 「`onCallGenkit` automatically populates `context.auth` (Firebase Authentication)」と App Check の `context.app`。指定は `authPolicy`・`enforceAppCheck`・`consumeAppCheckToken`。Firebase の外では「Use a `ContextProvider` to populate context values such as `auth`」で、`genkit/context` の `apiKey` や `@genkit-ai/firebase/context` を使う ( https://genkit.dev/docs/deployment/authorization/ ) |

### 確かめたこと: issue で確かめていなかった 5 点

**1. iOS (Swift) のアプリから flow を呼ぶ方法**

- Genkit の client の文書 ( https://genkit.dev/docs/client/ ) に Swift の記述は無い (取得した本文に「Swift」の語が無い)。同じページは「When deploying to Cloud Functions for Firebase, use the Firebase callable functions client library」と書く
- Cloud Functions for Firebase に置いた時: Firebase の Apple 向けの SDK の `functions.httpsCallable("addMessage")` の形で呼ぶ (Swift の例がある。 https://firebase.google.com/docs/functions/callable?gen=2nd )。SDK が App Check のトークンを付ける (「The Cloud Functions client SDKs automatically attach an App Check token when you invoke a callable function」 https://firebase.google.com/docs/app-check/cloud-functions )。SDK を使わずに HTTP で呼ぶ時の形も決まっている: 要求の本文の `data` が引数 (「The argument passed to the function」)、応答は「At a minimum it contains either result or error」。ただし SDK がある所では SDK を使うよう書いてある (「recommended to do that instead of directly implementing this protocol」 https://firebase.google.com/docs/functions/callable-reference )
- `@genkit-ai/express` の `expressHandler` で出した時 (実測): `POST /generateReplyTexts` に `{"data": {"conversation": "...", "provider": "gemini"}}` を送ると、`{"result": {"texts": ["a", "b", "c"]}}` が 200 で返る。形の合わない入力には成功でない応答が返り、`result` は無い (`server/test/generateReplyTextsFlow.test.ts` の HTTP のテスト)。この形なら Swift の `URLSession` と `Codable` だけで呼べる。SDK は要らないが、App Check のトークンを付ける・確かめる処理は自分で書く
- 実機のアプリからの呼び出しは、どちらの形も試していない (デプロイしていないため)

**2. アプリ側で、flow を Foundation Models の `LanguageModel` に準拠させるか、`ReplyModel` の先を HTTP の呼び出しに替えるか**

勧めるのは、flow を呼ぶモデルを `LanguageModel` に準拠させる方 (2026-11-21 に、main に入った `Poppo/ChatReading/ChatCompletionsLanguageModel.swift` を読んで改めた。その前は、準拠に要る処理の量を確かめないまま、`ReplyModel` の先を HTTP の呼び出しに替える方を勧めていた)。

`ChatCompletionsLanguageModel.swift` ( https://github.com/bannzai/poppo/issues/39 の実装。OpenAI と Gemini を `LanguageModel` に準拠させたもの) を読んで分かったこと:

- 準拠に要るのは、モデルの型に `capabilities` と `executorConfiguration` の 2 つ、実行側 (`LanguageModelExecutor`) に `init(configuration:)` と `respond(to:model:streamingInto:)` の 2 つ。同じファイルは、準拠の部分が約 55 行、要求の本文への変換と応答の読み取りを合わせて 177 行
- 実行側が受け取るのは `request.transcript` (指示の文と、利用者からの文) と `request.schema` (出力の形。無い時がある)。返すのは文で、`channel.send(.response(action: .appendText(content, tokenCount: 0)))` に、出力の形の JSON の文を 1 回流している
- 実行側は、受け取ったものを全部提供元へ運ぶ必要が無い。同じファイルは、会話の記録のうち文でない部分 (画像・tool の呼び出し) を送っていない。flow を呼ぶ実行側は、利用者からの文 (`replyPrompt(messages:)` が作った会話の文) だけを取り出して flow の `conversation` に入れ、指示の文と出力の形は送らずに済む。サーバーは今の flow (会話の文と提供元だけを受ける) のままでよく、「任意の指示と schema を受けるモデルの中継」にはならない (改める前の比べの、中継になるという見立ては誤りだった)
- アプリの今の作りは、どのモデルも `LanguageModel` として `LanguageModelSession(model:instructions:).respond(to:generating:)` の 1 つの呼び出しで使う (`Poppo/ChatReading/ReplyGeneration.swift` の `languageModel(replyModel:apiKeyKeychainService:)` と `generateReplyTexts(messages:languageModel:)`)。flow を呼ぶモデルを準拠させれば、`ReplyModel` に case を足して `languageModel(replyModel:)` の分岐を 1 つ足す変更で入る。HTTP の呼び出しに替える方は、`generateReplyTexts` に `LanguageModelSession` を通らない 2 つ目の経路を足すことになる

準拠させる時の作り (実装していない。ビルドも実行もしていない):

- 実行側は、flow が返した `texts` を `{"texts": [...]}` の JSON の文にして `appendText` で流す (`ChatCompletionsLanguageModel` が提供元の返した JSON の文を流すのと同じ形)。framework がその文を `GeneratedReplyTexts` として読むこと、3 つでない時に framework の側で失敗になるかは確かめていない (3 つであることは flow の側で確かめている)
- framework が渡す指示の文と出力の形は、flow を呼ぶ実行側では使わない。アプリの `replyInstructions` は端末内のモデル・Private Cloud Compute と、開発者メニューの OpenAI・Gemini (API キーを端末に置く経路) のためのもので、flow はサーバーの写しを使う (下の「指示の文の正」)
- 呼び出しの確かめ (App Check のトークン・匿名のサインイン) は実行側の中で付ける。Firebase の SDK の `httpsCallable` を実行側から呼べるかは確かめていない

**3. 取り込みの間 (本体アプリが背面にいる間) に、App Check のトークンの取得とサーバーへの通信が通るか**

分からなかった。実機でしか確かめられない (「ユーザー作業の一覧」に移す項目。デプロイの後)。文書から分かるのは次まで。

- App Attest は、iOS の app extension からは使えない (「The only app extensions that support App Attest are watchOS extensions in watchOS 9 or later.」「The `generateKey(completionHandler:)` method fails when you call it from an app extension」 https://developer.apple.com/documentation/devicecheck/dcappattestservice/issupported )。キーボード (拡張) からサーバーは呼べず、呼ぶのは本体アプリになる。今の作り (本体アプリが返信案を作り、キーボードは共有コンテナから読むだけ) と合う
- App Check のトークンは既定で 1 時間有効で、SDK が半分ほどの時点で取り直す (「The default TTL of 1 hour is reasonable for most apps」「refreshes tokens at approximately half the TTL duration」 https://firebase.google.com/docs/app-check/ios/app-attest-provider )。前面で取ったトークンが背面でも有効な間は使える見込みだが、背面での取り直しが通るかは文書に無い (推測)

**4. 費用**

- Blaze に最低額の記述は無く、使った分だけ払う: 「Pay-as-you-go pricing for any additional usage of paid Firebase products」「A Firebase project on the Blaze pricing plan has a Cloud Billing account linked to it」( https://firebase.google.com/docs/projects/billing/firebase-pricing-plans )
- Cloud Functions: 「The first 2,000,000 invocations, 400,000 GB-sec, 200,000 CPU-sec, and 5 GB of Internet egress traffic is provided at no cost each month.」( https://firebase.google.com/docs/functions/faq-and-troubleshooting )。料金の表は呼び出しを「No-cost up to 2M/month」、超えた分を「$0.40/million」と書く ( https://firebase.google.com/pricing )。関数の入れ物の保存に少額がかかる (「Artifact Registry provides the first 500MB at no cost」同じ FAQ)。常に起こしておく数を 1 以上にすると、呼ばれていない間も費用がかかる (「A minimum number of instances kept running incur billing costs at idle rates.」 https://firebase.google.com/docs/functions/manage-functions?gen=2nd )
- Cloud Run (要求ごとの課金): 「CPU - First 180,000 vCPU-seconds free per month RAM - First 360,000 GiB-seconds free per month Requests - 2 million requests free per month」( https://cloud.google.com/run/pricing )
- 置き場所の費用は、どちらも無料の枠に収まる見込み (読み取り 1 回が 1 回の呼び出しで、月 200 万回が無料の枠)。費用の大半は各社のモデルの利用料になる (Gemini 3.5 Flash-Lite で読み取り 1 回あたり約 $0.002 の見積もり。`documents/DIRECTION.md`「決めたこと」の 2026-11-20 の行。実測していない)
- 確かめていない: Cloud Secret Manager の料金、無料の枠を超えた分の CPU・メモリの単価、Claude と OpenAI のモデルの読み取り 1 回あたりの費用

**5. public のリポジトリに Firebase の設定ファイル (`GoogleService-Info.plist`) を置く扱い**

- Firebase は、この API キーを秘密として扱わなくてよいと書く: 「API keys for Firebase services are OK to include in code or checked-in config files」「API keys for Firebase services only identify your Firebase project and app to those services」。条件は、キーを Firebase の API だけに絞ることと、Security Rules・App Check で守ること。Gemini の API を呼ぶキーは別で、「should never be included in your code or configuration files」( https://firebase.google.com/docs/projects/api-keys )
- それでも、このリポジトリには置かない案を勧める。`AIza` で始まる値をコミットしない決まり ( https://github.com/bannzai/poppo/issues/40 の制約。commit の前の点検は Google の API キーの検出を誤検知として通さない) があり、Firebase の文書の条件 (キーの絞り込み) が外れた時に公開済みの値を消せないため。置かない時は、ビルドの時に Secrets から書き出す (Secrets に名前を 1 つ足す。下の「owner が決めること」)

### 確かめたこと: API キー無しでの起動 (実測)

API キーの環境変数を 1 つも持たない状態で `npm start` を実行した。`anthropic()` は plugin を作る時点で失敗する (「Please pass in the API key or set the ANTHROPIC_API_KEY environment variable」) ため、`server/src/server.ts` は作れた plugin だけで起動する。起動後、キーの無い提供元を指定した呼び出しは失敗し、返信の文は返らない。

## Decision

次の案を勧める。決めるのは owner。

| 項目 | 勧める案 | 比べた相手と、勧めない理由 |
| --- | --- | --- |
| サーバーの言語 | TypeScript | Python は preview (0.x) で、破壊的な変更が minor の版で入る。Go と Dart は安定版で 3 社の plugin もあるが、Cloud Functions for Firebase への配置 (`onCallGenkit`) の文書が無く、置き場所が Cloud Run か任意の host になり、App Check のトークンの確かめと利用者の見分けを自分で組むことになる。Dart は、テストでのモデルの差し替えの文書も無い (`https://genkit.dev/docs/dart/testing/` は 404。Go と Python にはある)。TypeScript は 3 社の plugin・`onCallGenkit`・テスト用の `mockModel` が文書にあり、`server/` で動かして確かめた。置き場所を Cloud Run にすると決めた時は、Go も候補に戻る (その時に動かして確かめる) |
| 置き場所 | Cloud Functions for Firebase (`onCallGenkit`) | Cloud Run・Node が動く host は、App Check のトークンの確かめ・利用者の見分け・API キーの受け渡しを自分で組む。`onCallGenkit` はどれも指定で済む。費用はどちらも無料の枠に収まる見込みで、差にならない |
| アプリからの呼び方 | Firebase の Apple 向けの SDK の `httpsCallable` | HTTP を直接書く形は依存が増えないが、App Check のトークンを付ける処理を自分で書く。Firebase の文書も SDK を勧める |
| アプリ側の作り | flow を呼ぶモデルを `LanguageModel` に準拠させ、`ReplyModel` の case として足す | `ReplyModel` の先を HTTP の呼び出しに替える方は、`LanguageModelSession` を通らない 2 つ目の経路が要る。準拠させても、実行側が会話の文だけを flow へ送れば、サーバーは任意の指示を受ける中継にならない (上の 2) |
| 呼び出しの確かめ方 | App Check (App Attest) を `enforceAppCheck` で必須にし、Firebase Authentication の匿名のサインインで利用者を見分ける | App Check だけでは、アプリからの呼び出しかは分かるが利用者を見分けられない。使い回しを防ぐ `consumeAppCheckToken` は入れない (「Replay protection (beta)」で、「adds a network round trip to token verification, and therefore adds latency to the function call」 https://firebase.google.com/docs/app-check/cloud-functions )。返信案は読み取りのたびに作るため、遅れを足さない |
| 利用者ごとの回数の制限 | flow の中で、Authentication の uid ごとの回数を数えて上限で断る | アプリの中だけで数える形は、書き換えられる端末では守れない (`documents/DIRECTION.md` の 2026-11-20 の行)。数える置き場所 (Firestore 等) は新しいデータ構造になるため、実装の時に型を owner に見せる。匿名の uid は、アプリを入れ直した時と、サインアウトして匿名のサインインをし直した時に新しくなる見込みで (どちらも確かめていない)、新しい uid の回数は 0 から始まる。上限に達した利用者が回数を戻せることは残るため、匿名の uid に頼らない制限 (端末ごと・App Check の単位など) を足すかは owner が決める (下の「利用者の見分け方と回数の上限」)。Claude は、サーバーが利用者ごとの user profile を作り、その ID を利用者ごとに保存して、その利用者の Claude の呼び出しのすべてに付ければ、1 人の利用者の内容で Anthropic の組織の全体が制限される問題 (同じ行) も避けられる (「You register each end customer once with `POST /v1/user_profiles` and store the `uprof_` ID it returns. Then you send that ID in the `anthropic-user-profile-id` header on every request you make on that end customer’s behalf.」「Without a profile on the request, one end customer can trigger an enforcement action that applies to your whole organization.」 https://platform.claude.com/docs/en/manage-claude/user-profiles )。保存する置き場所は新しいデータ構造になり、`@genkit-ai/anthropic` の plugin からこの header を付けられるかは確かめていない |

### `server/` に足したもの

- `generateReplyTexts` という flow (`server/src/generateReplyTextsFlow.ts`)。入力は会話の文 (`conversation`。アプリの `replyPrompt(messages:)` が作る文) と提供元 (`provider`。`claude`・`openAI`・`gemini`)。出力は `texts` (文字列 3 つ)。3 つの形でない出力は失敗にし、一部だけを返さない
- 提供元ごとのモデル (`server/src/providerModels.ts`): `claude-haiku-4-5`・`gpt-5.4-mini`・`gemini-3.5-flash-lite`。各 plugin の文書に載っているモデルのうち小さい側を仮に選んだ (試す間の費用を 3 社それぞれ 10 ドルに収めるため)。質を比べて決め直す。OpenAI は、アプリの開発者メニューの経路 (API キーを端末に置く経路) が使う `gpt-6-luna` (`documents/DIRECTION.md`「決めたこと」の 2026-11-21 の行が、廃止の予定が無いモデルのうち最も安いと記録したもの) と揃っていない。サーバーのモデルはその行より前に選んだもので、2 つの単価は比べていない。Gemini は同じ `gemini-3.5-flash-lite`
- 手元で試す起動口 (`server/src/server.ts`)。呼び出しの確かめを持たないため、このマシンの中からだけ届くアドレス (127.0.0.1) で待ち受ける (実測: 起動して `lsof` で見た待ち受けは `127.0.0.1:3499`)。Host ヘッダーが `127.0.0.1:<port>`・`localhost:<port>` でない要求は 403 で断る (起動中にブラウザで開いたページが、自分のドメインの解決先を 127.0.0.1 に切り替えて呼ぶ経路を断つため)。`onCallGenkit` で包む入口は、置き場所が決まってから足す
- 置き場所を `server/` にしたのは、Xcode の同期フォルダ (`Poppo/`・`PoppoKeyboard/`・`PoppoTests/`・`Shared/`) の外で、アプリのターゲットに入らないため

### 指示の文の正

モデルへの指示の文の正は、アプリの `replyInstructions` (`Poppo/ChatReading/ReplyGeneration.swift`) にする。端末内のモデルと Private Cloud Compute はアプリの文を使い続け、サーバーの文はその写しになる。同じ文を 2 か所に持つことになるため、`server/test/replyInstructionsMatchApp.test.ts` が Swift のソースから文を読み、サーバーの文と 1 字でも違えば CI で落とす (`texts` の説明の文も同じ)。アプリ側の呼び出しを flow に切り替え、端末の外のモデルがアプリの文を使わなくなった時に、正をどちらに置くかを決め直す。

## owner が決めること

| 決めること | 中身 |
| --- | --- |
| 新しい外部サービスの利用 | Firebase のプロジェクトを作り Blaze にする (Cloud Billing を結ぶ)。Cloud Functions・Secret Manager・App Check・Authentication を使う。Cloud Run にする時は Cloud の課金アカウント |
| 費用の上限 | 置き場所の予算の通知の額。各社のモデルの利用料の、利用者に配る時の月の上限 (試す間は 3 社それぞれ 10 ドルと決まっている) |
| 各社の API キーをサーバーの secret に置くこと | `ANTHROPIC_API_KEY`・`OPENAI_API_KEY`・`GEMINI_API_KEY` の 3 つを Cloud Secret Manager に置く。どの提供元を利用者に配るか (3 社とも / 一部) |
| `GoogleService-Info.plist` の扱い | リポジトリに置かず、ビルドの時に Secrets から書き出す (勧める案。Secrets に名前が 1 つ増える) か、Firebase の文書に従ってコミットする |
| 利用者の見分け方と回数の上限 | 匿名のサインインでよいか (入れ直しやサインインのし直しで回数が戻ることを許すか、匿名の uid に頼らない制限を足すか)。無料の利用者の 1 日あたり (または通算) の回数 |
| 提供元ごとのモデル | 仮に選んだ小さい側のモデルのままにするか、質を比べて決め直すか。OpenAI を、アプリの開発者メニューの経路と同じ `gpt-6-luna` に揃えるか |
| 同意の画面と文書の直し | 端末の外へ発言を送る前の同意の画面、`docs/PrivacyPolicy-ja.md`、App Privacy の回答、輸出コンプライアンスの申告。利用者に配るビルドで端末の外へ送る変更と同じ変更で行う (`documents/DIRECTION.md`「決めたこと」の 2026-11-20 の行) |

決まった後に別の issue で行うこと: `onCallGenkit` の入口とデプロイ、アプリ側の呼び出しの切り替え ( https://github.com/bannzai/poppo/issues/39 の実装は main に入っている。開発者メニューの OpenAI・Gemini の経路をこの flow に替えるか、残すかもその時に決める)、同意の画面と文書の直し、`documents/adr/0002-process-on-device-without-backend.md` の改め。

## Consequences

**良い点:**
- API キーを利用者の端末に置かずに、端末の外のモデルの返信案を配れる
- 呼び出しをサーバーで確かめ、利用者ごとに回数を絞れる。提供元を足す・モデルを替える変更が、アプリの審査を通さずにできる
- 返信の文を作る処理を、提供元の API を呼ばずにテストで確かめられる (`server/test/`。PR の CI の `server-tests`)

**悪い点 / 引き受けるリスク:**
- サーバー・認証・外部サービスを持つことになり、`documents/adr/0002-process-on-device-without-backend.md` の良い点 (インフラ費用が無い・プライバシーポリシーが単純) を手放す。費用の監視 (予算の通知) が要る
- 画面から読んだチャットの発言 (相手の発言を含む) が、Poppo のサーバーと各社のモデルへ送られる。同意の画面と文書の直しが要る
- リポジトリに Swift 以外の言語 (TypeScript) と npm の依存が入る
- 指示の文を、アプリとサーバーの 2 か所に持つ (食い違いはテストで検出する)
- 取り込みの間 (背面) にサーバーを呼べるかは、デプロイして実機で確かめるまで分からない。通らなければ、端末の外のモデルは「スクリーンショットから読む」使い方だけになる
