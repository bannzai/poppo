# Poppo

画面のチャットを読んで、翻訳と返信案をキーボードに出す iOS アプリ (iOS 27 以降)。

## 概要
@README.md

方向性 (仮説・判定基準・必要な機能・決めたこと・用語) は `documents/DIRECTION.md`。issue を書く時と読む時は、プロダクト固有の言葉の意味を同文書の「用語」で確かめる。

## Xcode プロジェクト構成の変更

- `Poppo.xcodeproj` をプロジェクト構成の唯一の正とする。XcodeGen と `project.yml` は使わず、`xcodegen generate` を実行しない (理由: [ADR 0001](documents/adr/0001-manage-xcode-project-directly.md)。機械検査: `~/.agents/skills/create-new-app/scripts/check-setup.sh` の `xcode-project-source` 項目)
- ソースのディレクトリ (`Poppo/`・`PoppoKeyboard/`・`PoppoTests/`・`Shared/`) は Xcode の同期フォルダで、ファイルを足す・消すだけでターゲットに反映される。`Shared/` は本体アプリとキーボード拡張の両方のターゲットに入るため、両方から使う型だけを置く。ターゲットに入れないファイル (拡張の Info.plist 等) は `Config/` に置く
- ターゲット、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Poppo.xcodeproj/project.pbxproj`、Scheme を `Poppo.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する
- 変更後は `git diff -- Poppo.xcodeproj` で意図した差分だけであることを確認し、下記の CI で検証する

## 検証方法

ビルド・simulator・ブラウザの動作確認は外部のマシンで行い、開発マシンでは行わない (owner の方針。`documents/DIRECTION.md`「決めたこと」)。本リポジトリは public のため、外部のマシンは GitHub Actions の runner を使う (private のリポジトリなら Devin)。開発マシンでの実行は、下のどの経路でも確かめられない時の最後の手段にする。経路の判定は `/ios-simulator` skill Phase 1 と verify skill「実行場所の判定」に従う。

| 確かめること | 経路 | 補足 |
| --- | --- | --- |
| ビルドとユニットテスト | PR の CI (`.github/workflows/ci.yml`。`make build-ios`・`make build-ios-device`・`make test`) | PR を作る前のブランチは `gh workflow run ci.yml --ref <ブランチ>` で流す。runner は `xcode-27` (iOS 27 の SDK と simulator がある GitHub-hosted runner はこれだけ)。`make build-ios-device` は実機向けの SDK での署名なしのビルドで、simulator 向けビルドではコンパイルされないコード (ScreenCaptureKit を使う画面の取り込みの実体) のコンパイルを確かめる |
| 本体アプリの画面と、キーボードの表示 | simtunnel (GitHub Actions の runner 上のリモート iOS Simulator)。caller workflow は `.github/workflows/simulator-session.yml` | 動作確認は特別な理由がない限り simtunnel で行う。キーボードに出す内容は、開発者メニューで保存した読み取り結果の見本で確かめる (`.claude/rules/debug-menu-for-verification.md`)。simulator の端末は iPhone Duo を使わない (Xcode 27.1 の既知の問題: 「Running and debugging most app extensions is unavailable in the iPhone Duo Simulator runtime.」) |
| 紹介ページ・利用規約・プライバシーポリシーの表示 | webtunnel (GitHub Actions の runner 上の Chromium)。caller workflow は `.github/workflows/browser-session.yml` | `docs/` を静的サーバでそのまま配信して開く。今の `docs/` は Markdown だけで、公開時に GitHub Pages (Jekyll) が HTML にした後の表示はこの経路では確かめられない。今の構成では日本語が文字化けし、文の中身も読めない (実行した結果は表の下の webtunnel の項)。紹介ページ (`docs/index.html`) を作る時に、Jekyll でビルドした出力を配信するよう workflow を直す |
| 取り込み → 読み取り → 翻訳 → 返信案 → キーボードへの表示の通し | 実機 (iOS 27)。「ユーザー作業の一覧」issue の「実機・実環境での確認」に書いて owner に頼む | 下の「simulator で確かめられないこと」のため。実機には TestFlight の内部テストで入れる。配るのは `gh workflow run ios-deploy.yml --ref main -f developer_menu=true` (`.github/workflows/ios-deploy.yml`。`developer_menu=true` で開発者メニューと診断の記録が入る)。手順と、初回の準備で残っていることは `documents/ios-testflight-distribution.md` |
| TestFlight へ配るビルドのコンパイル (Release 構成。開発者メニューあり・なし) | PR の CI (`.github/workflows/ci.yml` の Release 構成の 2 つの step) | 配布の workflow は main で手動で起動した時にだけ動くため、Release 構成でだけ出るコンパイルエラーを PR の時点で見つける。署名とアップロードは PR の CI では確かめられない |

simtunnel と webtunnel は、リポジトリの Secrets の `TS_OIDC_CLIENT_ID` と `TS_OIDC_AUDIENCE` で tailnet に参加する (`gh secret list` で確かめる)。2026-11-17 に両方の caller workflow を初めて実行し、次を確かめた。

- simtunnel: iPhone 17 (iOS 27.2) の simulator でアプリが起動し、画面の撮影とタップができた ( https://github.com/bannzai/poppo/actions/runs/44035813671 )。試したのは https://github.com/bannzai/poppo/pull/11 のブランチ (`issue-3`) のアプリ。この回は job の開始から「tailnet へブリッジ」の step の完了まで約 24 分かかり (うち「WebDriverAgent を起動」の step が約 10 分)、`simtunnel up --wait` は 20 分の上限で失敗した。その時点で run は「Tailscale に参加」の step を実行中で、約 4 分後に `simtunnel status <session>` が成功して操作できた。`up --wait` が上限で終わったら、`gh run view <run id>` で run が進んでいることを見てから `status` が成功するのを待つ
- webtunnel: `docs/` の Markdown は変換されずに原文のまま表示され、日本語は文字化けした ( https://github.com/bannzai/poppo/actions/runs/44039659729 )。配信の対象外のファイル (`documents/design/` のモック等) は、runner 上の checkout を `file:///home/runner/work/poppo/poppo/<リポジトリ内のパス>` で開くと描画を確かめられた

### simulator で確かめられないこと

- 翻訳: Translation は simulator で訳さない (「It doesn't translate text in iOS or iPadOS simulators.」 https://developer.apple.com/documentation/translation/translating-text-within-your-app )
- 返信案の生成: GitHub-hosted runner の simulator では Foundation Models が使えない見込み。Apple の DTS の回答 (2025-06、macOS 26 の時点) は「An iOS simulator uses the models on macOS 26, and yet, Apple Intelligence currently isn't available on macOS running on a VM」( https://developer.apple.com/forums/thread/790860 ) で、GitHub-hosted runner は仮想マシンである。この 2 つからの推測で、macOS 27 の runner での実測はしていない
- 画面の取り込み (ScreenCaptureKit): simulator では使えない。Xcode 27.1 の iOS Simulator の SDK には ScreenCaptureKit.framework が無く、simulator 向けビルドで `import ScreenCaptureKit` は「Unable to resolve module dependency: 'ScreenCaptureKit'」になる (CI の実測: https://github.com/bannzai/poppo/actions/runs/44024115556 )。取り込みの実体は `#if canImport(ScreenCaptureKit)` で実機向けだけにコンパイルし、simulator では始める操作にエラーを返す。Apple のサンプルも「This sample requires a device running iOS 27 or later.」と書いている ( https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios )
- 文字の読み取り (Vision): simulator で動くかは未確認

そのため、取り込み・読み取り・翻訳・生成に依存しない部分 (読み取った文字から発言を抜き出す処理、読み取り結果の保存と読み出し、画面の表示) は、外から値を渡せる形にしてユニットテストと simtunnel で確かめる。

### 開発マシンで実行する時 (最後の手段)

- `make` (既定 target の `ios`): simulator 向けにビルドし、sim-boot で起動したプロジェクト固有の simulator に入れて起動する
- `make install-device`: 実機向けにビルドして実機に入れる (`FASTLANE_TEAM_ID` か `DEVELOPMENT_TEAM=<Team ID>` が要る)。実機に入れる経路は TestFlight (上の表の実機の行) で、これは TestFlight へ配れない時だけ使う
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
