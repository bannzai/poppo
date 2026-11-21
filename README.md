# Poppo

画面のチャットを読んで、翻訳と返信案をキーボードに出す iOS アプリ (iOS 27 以降)。

## 何をするアプリか

外国語のチャット (Slack・Discord など) を読み書きする時の、翻訳アプリとの間のコピーと貼り付けの往復を無くす。

まだ作り始めたところで、下の 2 つの使い方はどちらも通して実装してあるが、実機での確認はこれから。「取り込みで読む」の手順 2 (本体アプリが背面にいる間に、取り込んだ画面から文字を読んで翻訳と返信案を作る) が実機で動くかは分かっておらず、各段 (文字の読み取り・翻訳・返信案の生成・保存) の成功と失敗を開発者メニューの診断の記録で確かめる。simulator では取り込みが始まらないため、キーボードの表示は、開発者メニューで保存した見本の読み取り結果で確かめる。進み具合は https://github.com/bannzai/poppo/issues/7 にある。

使い方は 2 つある。

スクリーンショットから読む:

1. チャットの画面のスクリーンショットを撮る
2. 本体アプリを開き、直近に撮ったスクリーンショットを選ぶ
3. 発言の翻訳と返信案が出る。返信案をコピーしてチャットアプリに貼り付ける

取り込みで読む (アプリを切り替えない):

1. 本体アプリで取り込みを始める (画面全体を選ぶ)
2. チャットアプリを開く。本体アプリが画面の文字を読み取り、発言の翻訳と返信案を作る
3. 入力欄でキーボードを Poppo に切り替えると、直前の翻訳と返信案が出る
4. 返信案をタップすると、その文が入力欄に入る

翻訳と返信案の生成は端末内で行う構成で作り始める。端末の外のモデル (Private Cloud Compute・Claude・Gemini など) も使えるようにすると決まったが、利用者に配るビルドは今も端末内だけで作る。開発者メニューのあるビルドだけ、返信案を作るモデルを「端末内」と「Private Cloud Compute」から選べる (質を比べるため。Private Cloud Compute を選ぶと、画面から読んだ発言が Apple のサーバーへ送られる。使うには Apple からの entitlement の割り当てが要り、実機では確かめていない)。Claude・Gemini などはまだ実装していない。費用の許容など owner の返答待ちの点と、決まるまでの進め方は [documents/DIRECTION.md](documents/DIRECTION.md) の「bannzai の返答を待っていること」に書いてある。

## 使う技術

| 役割 | 技術 | 確かめたこと (2026-11-17) |
| --- | --- | --- |
| 画面の取り込み | ScreenCaptureKit | iOS 27 から使える。「ScreenCaptureKit replaces ReplayKit for screen streaming and mirroring. A broadcast extension is no longer necessary.」( https://developer.apple.com/documentation/screencapturekit ) |
| 背面での取り込みの継続 | `UIBackgroundModes` の `screen-capture` | Apple のサンプル: 「`screen-capture` in UIBackgroundModes, so the stream survives backgrounding for full-display capture.」( https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios ) |
| 文字の読み取り | Vision | 背面で実行できるかは Apple の文書に記述が無く、実機で確かめる |
| 翻訳 | Translation | view 無しで訳せる (`TranslationSession` の `init(installedSource:target:)`)。simulator では訳せない: 「It doesn't translate text in iOS or iPadOS simulators.」( https://developer.apple.com/documentation/translation/translating-text-within-your-app ) |
| 返信案の生成 | Foundation Models (`SystemLanguageModel`) | 背面で実行できるかは実機で確かめる。iOS 27 は背面での Neural Engine の利用に entitlement を求める ( https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes ) |
| 結果の受け渡し | App Group の共有コンテナ | キーボードは Full Access 無しでも読める: 「prevents writing to the containing app's shared group containers (reading is permitted)」( https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard )。実機での動きは未確認 |

## 文書

- 方向性 (仮説・判定基準・必要な機能・決めたこと・用語): [documents/DIRECTION.md](documents/DIRECTION.md)
- 評価の記録: [documents/evaluation/2026-11-17-report.md](documents/evaluation/2026-11-17-report.md)
- 開発の手順と検証方法: [AGENTS.md](AGENTS.md)
- 端末の外のモデルで返信の文を作るサーバーの処理 (デプロイしていない。手元での起動とテスト): [server/README.md](server/README.md)。置き場所・費用・呼び方の案: [documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md](documents/adr/0003-serve-off-device-reply-models-through-genkit-server.md)
- TestFlight の内部テストへの配布: [documents/ios-testflight-distribution.md](documents/ios-testflight-distribution.md)
- 利用規約: [docs/Terms-ja.md](docs/Terms-ja.md)、プライバシーポリシー: [docs/PrivacyPolicy-ja.md](docs/PrivacyPolicy-ja.md)
