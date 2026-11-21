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
| 返信案の生成 | 端末内のモデル。使えない端末では翻訳だけを出す。開発者メニューのあるビルドに限り、Private Cloud Compute (下の「2026-11-20 の改め」) と、OpenAI・Gemini の API (下の「2026-11-21 の改め」) でも作れる |
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
- 利用者に配るビルドで端末の外へ送る構成と、外部の API (Claude・Gemini・OpenAI) は、この改めの範囲に入れない。足す時は、同意の画面と文書の直し (`documents/DIRECTION.md`「決めたこと」の 2026-11-20 の行) を済ませ、この ADR を改める (OpenAI と Gemini を開発者メニューのあるビルドに足した改めは下)

### 2026-11-21 の改め: 開発者メニューのあるビルドに限り、OpenAI と Gemini の API で返信案を作れる

owner (bannzai) は 2026-11-21 に、開発者メニューに API キーの入力欄を足すことと、Gemini を自前の実装でつなぐことを決め ( https://github.com/bannzai/poppo/issues/1#issuecomment-7053569899 )、実装の計画を承認した ( https://github.com/bannzai/poppo/issues/1#issuecomment-7055573516 )。

> 1. キーの入力欄: → ええんちゃう？
> 2. Geminiは自前実装の方が良さそう。でもクラウドのモデルプロバイダの実装方法については /html-plan で相談して欲しい

> 承認。ただ、将来的にGenKitに書き換えた方が筋が良いし安全な気もしたからそのissueを立てて並行して進めておいて。リリース前には絶対対応する。

この決定のうち、OpenAI と Gemini を次の範囲で足す (実装: https://github.com/bannzai/poppo/issues/39 )。Claude は別の issue で足す。

- 開発者メニューのあるビルド (DEBUG の条件があるビルド) に限り、開発者メニューで返信案を作るモデルに「OpenAI」と「Gemini」を選べる。選んでいる間は、画面から読んだチャットの発言 (相手の発言を含む) を、返信案を作るために OpenAI の API (`https://api.openai.com/v1`) か Google の Gemini API (`https://generativelanguage.googleapis.com/v1beta/openai`) へ送る。翻訳と保存は端末内のまま。サーバーも Firebase も足さない (本体アプリが各社の API を直接呼ぶ)
- 選ぶ時に、送る内容と送信先 (OpenAI のサーバー / Google のサーバー) を画面で示して確かめる。Private Cloud Compute と同じ仕組みで、確かめた時だけ切り替える。送り先が変わる切り替え (Private Cloud Compute から OpenAI など) でも確かめる
- API キーは、owner が開発者メニューで入力し、その端末の Keychain にだけ置く (`kSecClassGenericPassword`。service は `com.bannzai.poppo.replyModelAPIKey`、account は `ReplyModel` の生の値。`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` で、ほかの端末とバックアップへは移さない)。リポジトリ・ビルドの設定・`UserDefaults`・ログ・診断の記録には置かない。キーを保存していないモデルは使えない扱いにし、ほかのモデルへ切り替えずに返信案なしで翻訳だけを出す
- 費用の上限はアプリの中に作らない。owner が各社の画面でキーに付ける (月 10 ドルずつ。 https://github.com/bannzai/poppo/issues/1#issuecomment-7043055903 )
- 利用者に配るビルド (開発者メニューの無いビルド) は、端末内だけのまま変えない (2026-11-20 の改めと同じ)。`docs/PrivacyPolicy-ja.md`・App Privacy の回答は変えない
- 輸出コンプライアンスの申告 (`ITSAppUsesNonExemptEncryption` が false) は見直した上で変えない。足した通信は `URLSession` の HTTPS だけで、アプリのコードは暗号を実装していない (Apple の文書: 「Typically, the use of encryption that’s built into the operating system—for example, when your app makes HTTPS connections using URLSession—is exempt from export documentation upload requirements」 https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations 2026-11-21 に読んだ)
- この自前の実装は、開発中に返信案の質を比べるためのもの。owner は、リリースの前に Genkit を使う形へ書き換えると決めている (上の引用)。利用者に配るビルドで端末の外へ送る前に、同意の画面と文書の直しを済ませ、この ADR を改める

## Consequences

**良い点:**
- チャットの内容が端末の外に出ないため、同意の画面と開示が取り込みの説明だけで済み、プライバシーポリシーが単純になる
- インフラ費用が発生せず、費用の監視 (予算アラート) が要らない

**悪い点 / 引き受けるリスク:**
- 返信案を出せるのは端末内のモデルが使える端末だけになる
- 返信案の品質は端末内のモデルの性能で決まり、実機で確かめるまで分からない
- 使われ方 (取り込みを始めた人のうち返信案を使った割合) を計測できない。`documents/DIRECTION.md` の判定基準のうちこの指標は、計測の仕組みを入れるまで判定できない
