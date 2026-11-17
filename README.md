# Poppo

画面のチャットを読んで、翻訳と返信案をキーボードに出す iOS アプリ (iOS 27 以降)。

## 何をするアプリか

外国語のチャット (Slack・Discord など) を読み書きする時の、翻訳アプリとの間のコピーと貼り付けの往復を無くす。

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

翻訳と返信案の生成は端末内で行う構成で作り始める (判断の経緯は [documents/DIRECTION.md](documents/DIRECTION.md) の「決めたこと」)。

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
- 利用規約: [docs/Terms-ja.md](docs/Terms-ja.md)、プライバシーポリシー: [docs/PrivacyPolicy-ja.md](docs/PrivacyPolicy-ja.md)
