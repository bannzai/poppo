# 0002. 端末内だけで処理し、サーバーと外部の API を持たない構成で始める

## Status
Proposed (2026-11-17)

返信案を作るモデルの経路と課金は、作るかの判断 (https://github.com/bannzai/poppo/issues/1 ) で owner に聞いていて、返答がまだ無い。この ADR は返答までの進め方を書いたもので、owner の返答で Accepted にするか書き直す。

## Context
Poppo は画面やスクリーンショットから読んだチャットの発言を翻訳し、返信案を作る。扱う文字には利用者以外 (チャットの相手) の発言が含まれる。構成を決めるにあたり、次を確かめた。

- 翻訳 (Translation) は端末で処理される (Apple の文書: 「processed on the user's device」 https://developer.apple.com/documentation/translation/translating-text-within-your-app )
- 返信案の生成は、端末内のモデル (`SystemLanguageModel`)、Private Cloud Compute、外部の API (Claude 等) のどれでも作れる。端末外の 2 つは、チャットの内容を端末の外へ送ることになり、送る前の明示の同意と開示が要る (App Review Guidelines 5.1.2(i): 「You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so.」)
- 外部の API は利用量で費用がかかり、API キーの管理が要る。費用の許容と外部サービスとの連携は owner が決める事項で、作るかの判断 (https://github.com/bannzai/poppo/issues/1 ) では返答が無かった

## Decision
owner の返答までは、翻訳・返信案の生成・保存をすべて端末内で行う。サーバー、データベース、認証、アクセス解析、外部の API を持たない。

| 項目 | 返答までの進め方 |
| --- | --- |
| データの保存 | 端末内だけ。本体アプリとキーボードの受け渡しは App Group の共有コンテナ (保存する形は `documents/design/data-structure/latest-reading.html`) |
| サーバー・データベース | 持たない |
| 認証 | 持たない (アカウントなし) |
| アクセス解析・クラッシュの収集 | 入れない。公開後の指標は App Store Connect の数値で見る |
| 返信案の生成 | 端末内のモデル。使えない端末では翻訳だけを出す。開発者メニューのあるビルドに限り、Private Cloud Compute でも作れる (下の「2026-11-20 の改め」) |
| 課金 | 持たない |
| 通知 | サービスからの通知は無い。開発の連絡は Slack の `#poppo-notification` |

端末外へ送る構成 (Private Cloud Compute・外部の API)・アクセス解析・課金を足す時は、owner の決定を得てからこの ADR を改める。

### 2026-11-20 の改め: 開発者メニューのあるビルドに限り、Private Cloud Compute で返信案を作れる

owner (bannzai) は 2026-11-20 に次のように決めた ( https://github.com/bannzai/poppo/issues/1#issuecomment-7019893647 )。

> PCCもClaude APIもどちらも使えるようにしようか。なんかそういうプロトコルあるよね。CodexやGeminiもつかえるようにしたい

「PCC」は Private Cloud Compute (Apple のサーバーで動くモデル)。この決定のうち、登録も費用も要らない Private Cloud Compute だけを、次の範囲で足す (実装: https://github.com/bannzai/poppo/issues/34 )。

- 開発者メニューのあるビルド (DEBUG の条件があるビルド) に限り、開発者メニューで返信案を作るモデルを「端末内」と「Private Cloud Compute」から選べる。Private Cloud Compute を選んでいる間は、画面から読んだチャットの発言 (相手の発言を含む) を、返信案を作るために Apple のサーバーへ送る。翻訳と保存は端末内のまま
- Private Cloud Compute を選ぶ時に、送る内容 (画面から読んだチャットの発言) と送信先 (Apple のサーバー) を画面で示して確かめる。確かめた時だけ選択を切り替え、取り消した時は選択を変えない
- 利用者に配るビルド (開発者メニューの無いビルド) は、端末内だけのまま変えない。選んだモデルが端末に保存してあっても見ずに、端末内のモデルで作る。そのため `docs/PrivacyPolicy-ja.md`・App Privacy の回答・輸出コンプライアンスの申告は変えない。開発者メニューのあるビルドを配るのは TestFlight の内部テスト (2026-11-20 の時点で owner だけ) に限る
- 利用者に配るビルドで端末の外へ送る構成と、外部の API (Claude・Gemini・OpenAI) は、この改めの範囲に入れない。足す時は、同意の画面と文書の直し (`documents/DIRECTION.md`「決めたこと」の 2026-11-20 の行) を済ませ、この ADR を改める

### 2026-11-21: サーバーを経由する案 (ADR 0003。決まるまでこの ADR のまま)

端末の外のモデル (Claude・OpenAI・Gemini) を利用者に配る時に、API キーをサーバーに置く案を `documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md` に書いた (Status は Proposed)。リポジトリにサーバーの処理 (`server/`) とそのテストを足したが、デプロイしておらず、アプリからも呼んでいない。上の表 (サーバー・認証を持たない) は、owner が ADR 0003 の「owner が決めること」を決めて実装する時に改める。

## Consequences

**良い点:**
- チャットの内容が端末の外に出ないため、同意の画面と開示が取り込みの説明だけで済み、プライバシーポリシーが単純になる
- インフラ費用が発生せず、費用の監視 (予算アラート) が要らない

**悪い点 / 引き受けるリスク:**
- 返信案を出せるのは端末内のモデルが使える端末だけになる
- 返信案の品質は端末内のモデルの性能で決まり、実機で確かめるまで分からない
- 使われ方 (取り込みを始めた人のうち返信案を使った割合) を計測できない。`documents/DIRECTION.md` の判定基準のうちこの指標は、計測の仕組みを入れるまで判定できない
