# 0002. 端末内だけで処理し、サーバーと外部の API を持たない構成で始める

## Status
Accepted (2026-11-17)

## Context
Poppo は画面やスクリーンショットから読んだチャットの発言を翻訳し、返信案を作る。扱う文字には利用者以外 (チャットの相手) の発言が含まれる。構成を決めるにあたり、次を確かめた。

- 翻訳 (Translation) は端末で処理される (Apple の文書: 「processed on the user's device」 https://developer.apple.com/documentation/translation/translating-text-within-your-app )
- 返信案の生成は、端末内のモデル (`SystemLanguageModel`)、Private Cloud Compute、外部の API (Claude 等) のどれでも作れる。端末外の 2 つは、チャットの内容を端末の外へ送ることになり、送る前の明示の同意と開示が要る (App Review Guidelines 5.1.2(i): 「You must clearly disclose where personal data will be shared with third parties, including with third-party AI, and obtain explicit permission before doing so.」)
- 外部の API は利用量で費用がかかり、API キーの管理が要る。費用の許容と外部サービスとの連携は owner が決める事項で、作るかの判断 (https://github.com/bannzai/poppo/issues/1 ) では返答が無かった

## Decision
翻訳・返信案の生成・保存をすべて端末内で行う。サーバー、データベース、認証、アクセス解析、外部の API を持たない。

| 項目 | 決定 |
| --- | --- |
| データの保存 | 端末内だけ。本体アプリとキーボードの受け渡しは App Group の共有コンテナ (保存する形は `documents/design/data-structure/latest-reading.html`) |
| サーバー・データベース | 持たない |
| 認証 | 持たない (アカウントなし) |
| アクセス解析・クラッシュの収集 | 入れない。公開後の指標は App Store Connect の数値で見る |
| 返信案の生成 | 端末内のモデル。使えない端末では翻訳だけを出す |
| 課金 | 持たない |
| 通知 | サービスからの通知は無い。開発の連絡は Slack の `#poppo-notification` |

端末外へ送る構成 (Private Cloud Compute・外部の API)・アクセス解析・課金を足す時は、owner の決定を得てからこの ADR を改める。

## Consequences

**良い点:**
- チャットの内容が端末の外に出ないため、同意の画面と開示が取り込みの説明だけで済み、プライバシーポリシーが単純になる
- インフラ費用が発生せず、費用の監視 (予算アラート) が要らない

**悪い点 / 引き受けるリスク:**
- 返信案を出せるのは端末内のモデルが使える端末だけになる
- 返信案の品質は端末内のモデルの性能で決まり、実機で確かめるまで分からない
- 使われ方 (取り込みを始めた人のうち返信案を使った割合) を計測できない。`documents/DIRECTION.md` の判定基準のうちこの指標は、計測の仕組みを入れるまで判定できない
