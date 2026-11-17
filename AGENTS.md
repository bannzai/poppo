# Poppo

画面のチャットを読んで、翻訳と返信案をキーボードに出す iOS アプリ (iOS 27 以降)。

## 概要
@README.md

方向性 (仮説・判定基準・必要な機能・決めたこと・用語) は `documents/DIRECTION.md`。issue を書く時と読む時は、プロダクト固有の言葉の意味を同文書の「用語」で確かめる。

## Xcode プロジェクト構成の変更

- `Poppo.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない (理由: [ADR 0001](documents/adr/0001-manage-xcode-project-directly.md)。機械検査: `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目)
- ソースのディレクトリ (`Poppo/`・`PoppoKeyboard/`・`PoppoTests/`) は Xcode の同期フォルダで、ファイルを足す・消すだけでターゲットに反映される。ターゲットに入れないファイル (拡張の Info.plist 等) は `Config/` に置く
- ターゲット、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Poppo.xcodeproj/project.pbxproj`、Scheme を `Poppo.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 変更後は `git diff -- Poppo.xcodeproj` で意図した差分だけであることを確認し、下記の CI で検証する

## 検証方法

ビルド・simulator・ブラウザの動作確認は外部のマシンで行い、開発マシンでは行わない (owner の方針。`documents/DIRECTION.md`「決めたこと」)。本リポジトリは public のため、外部のマシンは GitHub Actions の runner を使う (private のリポジトリなら Devin)。開発マシンでの実行は、下のどの経路でも確かめられない時の最後の手段にする。経路の判定は `/ios-simulator` skill Phase 1 と verify skill「実行場所の判定」に従う。

| 確かめること | 経路 | 補足 |
| --- | --- | --- |
| ビルドとユニットテスト | PR の CI (`.github/workflows/ci.yml`。`make build-ios` と `make test`) | PR を作る前のブランチは `gh workflow run ci.yml --ref <ブランチ>` で流す。runner は `xcode-27` (iOS 27 の SDK と simulator がある GitHub-hosted runner はこれだけ) |
| 本体アプリの画面と、キーボードの表示 | simtunnel (GitHub Actions の runner 上のリモート iOS Simulator)。caller workflow は `.github/workflows/simulator-session.yml` | 動作確認は特別な理由がない限り simtunnel で行う。キーボードに出す内容は、開発者メニューで保存した読み取り結果の見本で確かめる (`.claude/rules/debug-menu-for-verification.md`)。simulator の端末は iPhone Duo を使わない (Xcode 27.1 の既知の問題: 「Running and debugging most app extensions is unavailable in the iPhone Duo Simulator runtime.」) |
| 紹介ページ・利用規約・プライバシーポリシーの表示 | webtunnel (GitHub Actions の runner 上の Chromium)。caller workflow は `.github/workflows/browser-session.yml` | `docs/` を静的サーバでそのまま配信して開く。今の `docs/` は Markdown だけで、公開時に GitHub Pages (Jekyll) が HTML にした後の表示はこの経路では確かめられない。紹介ページ (`docs/index.html`) を作る時に、Jekyll でビルドした出力を配信するよう workflow を直す |
| 取り込み → 読み取り → 翻訳 → 返信案 → キーボードへの表示の通し | 実機 (iOS 27)。「ユーザー作業の一覧」issue の「実機・実環境での確認」に書いて owner に頼む | 下の「simulator で確かめられないこと」のため |

simtunnel と webtunnel は、リポジトリの Secrets に `TS_OIDC_CLIENT_ID` と `TS_OIDC_AUDIENCE` が登録されるまで使えない (`gh secret list` で確かめる)。

### simulator で確かめられないこと

- 翻訳: Translation は simulator で訳さない (「It doesn't translate text in iOS or iPadOS simulators.」 https://developer.apple.com/documentation/translation/translating-text-within-your-app )
- 返信案の生成: GitHub-hosted runner の simulator では Foundation Models が使えない見込み。Apple の DTS の回答 (2025-06、macOS 26 の時点) は「An iOS simulator uses the models on macOS 26, and yet, Apple Intelligence currently isn't available on macOS running on a VM」( https://developer.apple.com/forums/thread/790860 ) で、GitHub-hosted runner は仮想マシンである。この 2 つからの推測で、macOS 27 の runner での実測はしていない
- 画面の取り込み (ScreenCaptureKit) と文字の読み取り (Vision): simulator で動くかは未確認。Apple のサンプルは「This sample requires a device running iOS 27 or later.」と書いている ( https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios )

そのため、取り込み・読み取り・翻訳・生成に依存しない部分 (読み取った文字から発言を抜き出す処理、読み取り結果の保存と読み出し、画面の表示) は、外から値を渡せる形にしてユニットテストと simtunnel で確かめる。

### 開発マシンで実行する時 (最後の手段)

- `make` (既定 target の `ios`): simulator 向けにビルドし、sim-boot で起動したプロジェクト固有の simulator に入れて起動する
- `make install-device`: 実機向けにビルドして実機に入れる (`FASTLANE_TEAM_ID` か `DEVELOPMENT_TEAM=<Team ID>` が要る)
- ビルドのログは `./tmp/build.log` に保存し、全文を warning / error で検査する

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
