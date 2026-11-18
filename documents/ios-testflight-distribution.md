# TestFlight の内部テストへの配布

main の Poppo を GitHub Actions でビルドし、TestFlight の内部テストへアップロードする手順。workflow は `.github/workflows/ios-deploy.yml`。

審査への提出・外部テスター (TestFlight の公開リンク) への配布は、この workflow では行わない。

## 配布する

```sh
# 実機での確認に使うビルド (開発者メニューと診断の記録が入る)
gh workflow run ios-deploy.yml --ref main -f developer_menu=true

# 開発者メニューを入れないビルド
gh workflow run ios-deploy.yml --ref main
```

- 配布できるのは main からだけ。配布用の environment (`ios-deploy`) のデプロイブランチを main だけにしてある (ほかのブランチを `--ref` に指定した run がどう止まるかは、実行して確かめていない)
- main への push では起動しない (`on:` は `workflow_dispatch` だけ)。マージのたびにビルドが増えて内部テスターに通知が届くのを避けるため。push で起動する形にするのは、owner が公開に進むと決めた後にする
- 同時に 1 本だけ動く。先に動いている run がある時は、後から起動した run が最初の step で失敗する。先の run が終わってから起動し直す
- アップロードの後、App Store Connect がビルドを処理し終えると TestFlight に出る。処理の状態は次で読む (`processingState` が `VALID` なら TestFlight で入れられる)

  ```sh
  bash ~/.agents/skills/ios-deploy-actions/scripts/asc-api.sh GET "/v1/builds?filter[app]=6836208900&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate"
  ```

  `6836208900` は App Store Connect の Poppo のアプリの id。アップロードの直後は一覧にまだ出ない (最初の配布では、アップロードの成功の直後に読んだ時は 0 件だった)

- 配ったビルドは、内部テスターのグループ `InternalTester` (すべてのビルドに届く設定) のテスターが TestFlight アプリで入れられる。テスターを足す時は、App Store Connect API の `POST /v1/betaTesters` を、グループ (id `685408f9-7ad0-4b3f-8f02-39f7c8abc649`) を `relationships.betaGroups` に指定して呼ぶ。内部テスターにできるのは、App Store Connect のユーザーで、このアプリにアクセスできる人だけ (「Create a group and add up to 100 internal testers (App Store Connect users with access to your content)」「If you choose testers not part of your App Store Connect account, you won't be able to add them to an internal group.」 https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers )。ユーザーでない人を足す時は、先に App Store Connect のユーザーとして追加する (その人を足す要求がどう拒否されるかは試していない)。2026-11-18 に、アカウントの所有者をこの方法で足した (グループのテスターは 1 人)。既にあるテスターの記録の id をグループに足す方法 (`POST /v1/betaGroups/<id>/relationships/betaTesters`) は使えなかった: 所有者のメールアドレスで見つかった記録 (ほかのアプリのグループに属する記録が 20 件) の 1 つを指定すると、`409 STATE_ERROR`「Tester(s) cannot be assigned」で拒否された

### 開発者メニューを入れるビルド (`developer_menu`)

開発者メニューと診断の記録は `#if DEBUG` のコードで、Release 構成のビルドには入らない。実機での確認 (`documents/DIRECTION.md` の判定基準「実機で、背面の一連の処理が回った回数」) は診断の記録を見て数えるため、`developer_menu=true` で起動した時だけ、Release 構成のまま DEBUG の条件 (`SWIFT_ACTIVE_COMPILATION_CONDITIONS` に `DEBUG`) を足してアーカイブする。

- 入力を指定しない時は入れない。審査に出すビルドには `developer_menu=true` を使わない (`.claude/rules/debug-menu-for-verification.md`: 開発者メニューは App Store 配布のビルドに入れない)
- この組み合わせ (Release 構成 + DEBUG の条件) がコンパイルできることは、PR の CI (`.github/workflows/ci.yml` の「開発者メニューを入れた Release 構成での、実機向けの SDK でのビルド」) が確かめる。2026-11-18 の run ( https://github.com/bannzai/poppo/actions/runs/44235237358 ) では、この step のコンパイラの引数は `-O -DDEBUG`、入れない Release 構成の step は `-O` だけだった

## ビルド番号とバージョン

- ビルド番号 (`CURRENT_PROJECT_VERSION`) は、workflow が `github.run_number + BUILD_NUMBER_OFFSET` で決めてアーカイブの引数に渡す。`project.pbxproj` の値 (`1`) は配布では使わない
- 失敗した run の Re-run は、同じ `run_number` (= 同じビルド番号) になる。「Upload to TestFlight」の step まで進んで失敗した run は Re-run せず、新しく起動する (アップロード済みの番号と同じ番号は拒否される)。それより前の step で失敗した run は Re-run でよい
- workflow のファイルを作り直すと `run_number` が 1 に戻る。その時は、App Store Connect にある最大のビルド番号を超えるように `BUILD_NUMBER_OFFSET` を増やす
- バージョン (`MARKETING_VERSION`) は `project.pbxproj` の値 (`1.0.0`) をそのまま使う。App Store に出したバージョンと同じかそれ以下のバージョンはアップロードできなくなるため、公開した後は次のバージョンに上げてから配布する

## 署名

Release 構成の実機向け (`sdk=iphoneos*`) だけを手動署名にしてある (`project.pbxproj`)。Debug 構成と simulator 向けの設定は変えていない。

| target | bundle ID | profile の名前 (`PROVISIONING_PROFILE_SPECIFIER`) | profile を置く Secret |
| --- | --- | --- | --- |
| Poppo (本体アプリ) | `com.bannzai.poppo` | `Poppo.AppStore` | `IOS_PROVISIONING_PROFILE_BASE64` |
| PoppoKeyboard (キーボード) | `com.bannzai.poppo.keyboard` | `Poppo.PoppoKeyboard.AppStore` | `IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64` |

- Team ID は `project.pbxproj` に書かず、workflow の `env.DEVELOPMENT_TEAM` からアーカイブの引数で渡す (手元の `make install-device` が環境変数から渡すのと同じ扱い)
- 配布証明書 (Apple Distribution) は、Secrets の `.p12` を workflow が runner のキーチェーンに入れて使う

### Secrets

配布用の environment `ios-deploy` の environment secrets に置く (リポジトリの Secrets には置かない。main 以外のブランチの workflow から読めないようにするため)。

| Secret | 中身 | 登録した日 |
| --- | --- | --- |
| `ASC_API_KEY_ID`・`ASC_API_KEY_ISSUER_ID`・`ASC_API_KEY_P8_BASE64` | App Store Connect API の Key (アップロードに使う) | 2026-11-18 |
| `IOS_P12_CERTIFICATE_BASE64`・`IOS_P12_PASSWORD` | 配布証明書の `.p12` とそのパスワード | 2026-11-18 |
| `IOS_PROVISIONING_PROFILE_BASE64` | 本体アプリの App Store 用 provisioning profile (`Poppo.AppStore`。App Store Connect の profile の id `7Y96J77CJ4`) | 2026-11-18 |
| `IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64` | キーボードの App Store 用 provisioning profile (`Poppo.PoppoKeyboard.AppStore`。profile の id `CFT5FW2D7U`) | 2026-11-18 |

登録は ios-deploy-actions skill の `register-secrets.sh` で行う (値を画面に出さない)。登録済みの名前は `gh secret list -R bannzai/poppo --env ios-deploy` で読める。

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/poppo --env ios-deploy --secret <名前>=<値> [--secret-base64-file <名前>=<base64 にして登録するファイル>]
```

### profile を発行し直す時

発行し直すのは、profile の期限が切れる時、配布証明書を替えた時、App ID の Capability (App Group など) を変えた時。今の `.p12` の証明書は App Store Connect の証明書の id `68L9PY6PX2` で、期限は 2027-01-17。2026-11-18 にこの証明書で発行した今の 2 つの profile の期限も、同じ 2027-01-17。

1. profile を発行する (同じ名前の profile がある時は `--recreate` で作り直す)

   ```sh
   bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-profile --name "Poppo.AppStore" --bundle-id com.bannzai.poppo --certificate-id 68L9PY6PX2 --out tmp/signing --entitlements Config/Poppo.entitlements
   bash ~/.agents/skills/ios-deploy-actions/scripts/signing-assets.sh create-profile --name "Poppo.PoppoKeyboard.AppStore" --bundle-id com.bannzai.poppo.keyboard --certificate-id 68L9PY6PX2 --out tmp/signing --entitlements Config/PoppoKeyboard.entitlements
   ```

2. 発行された profile の中身を開き、次の 2 つを確かめる

   ```sh
   security cms -D -i tmp/signing/Poppo_AppStore.mobileprovision > tmp/signing/profile.plist
   plutil -extract Entitlements json -o - tmp/signing/profile.plist
   ```

   - `application-identifier` が、頼んだ bundle ID で終わっている
   - `com.apple.security.application-groups` に `group.com.bannzai.poppo` が入っている

   中身を開いて確かめるのは、2026-11-18 に `create-profile` の出力 (`entitlements-check=ok`) と中身が食い違ったため。`com.bannzai.poppo` の profile を頼んだ時に `com.bannzai.poppo.keyboard` の profile が発行され、App Group が空でも `ok` が出た ( https://github.com/bannzai/castle/issues/3132 。同じ日に修正がマージされた: https://github.com/bannzai/castle/pull/3135 。修正後のスクリプトでの発行は試していない)。食い違った時は、App Store Connect API の `POST /v1/profiles` を bundle ID のリソース id (`com.bannzai.poppo` は `XZPY677UXL`、`com.bannzai.poppo.keyboard` は `CQ789C575K`) を指定して直接呼ぶ。今の 2 つの profile は、開発マシンのスクリプトに修正が届く前だったため、この方法で発行した (本文は `{"data":{"type":"profiles","attributes":{"name":"<profile の名前>","profileType":"IOS_APP_STORE"},"relationships":{"bundleId":{"data":{"type":"bundleIds","id":"<bundle ID のリソース id>"}},"certificates":{"data":[{"type":"certificates","id":"68L9PY6PX2"}]}}}}`。応答の `profileContent` を base64 で戻したものが `.mobileprovision`)

3. 2 つの Secret を登録し直す

   ```sh
   bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/poppo --env ios-deploy --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=tmp/signing/Poppo_AppStore.mobileprovision --secret-base64-file IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64=tmp/signing/Poppo_PoppoKeyboard_AppStore.mobileprovision
   ```

配布証明書を替える時は、`.p12` の 2 つの Secret も登録し直し、上の証明書の id と期限を書き直す。

## 初回の準備 (2026-11-18 にすべて済んだ)

新しいアプリで同じ準備をする時の順番と方法の記録。上から順に行う。

| 準備 | 方法 |
| --- | --- |
| bundle ID の登録 (`com.bannzai.poppo`・`com.bannzai.poppo.keyboard`) | App Store Connect API の `POST /v1/bundleIds` |
| 2 つの App ID で App Groups の Capability を有効にする | App Store Connect API の `POST /v1/bundleIdCapabilities` (`capabilityType` は `APP_GROUPS`) |
| 配布用の environment `ios-deploy` (デプロイブランチは main だけ) | ios-deploy-actions skill の `setup-environment.sh` |
| API Key と配布証明書の Secrets | 上の「Secrets」 |
| App Group `group.com.bannzai.poppo` の登録と、2 つの App ID への割り当て | fastlane の `produce` (下。App Store Connect API ではできない) |
| App Store Connect へのアプリの登録 | fastlane の `produce` (下。App Store Connect API ではできない) |
| 2 つの provisioning profile の発行と Secrets の登録 | 上の「profile を発行し直す時」。App Group の割り当ての後に行う (割り当ての前に試しに発行した profile は、`com.apple.security.application-groups` が空の配列だった) |
| 最初の配布 | `gh workflow run ios-deploy.yml --ref main -f developer_menu=true` |
| 内部テスターのグループ `InternalTester` を作り、所有者を足す | App Store Connect API の `POST /v1/betaGroups` (`isInternalGroup`・`hasAccessToAllBuilds` を true) と `POST /v1/betaTesters` |

### 最初の配布の結果

- run: https://github.com/bannzai/poppo/actions/runs/44253583678 (main の `511dc29`。`developer_menu=true`)。1 回目の起動で、署名・IPA の書き出し・アップロードを含む全 step が成功した
- ビルド番号は `1` (`run_number` 1 + `BUILD_NUMBER_OFFSET` 0)。アップロードのログは「UPLOAD SUCCEEDED with no errors」
- App Store Connect の処理は、アップロードの成功から約 5 分後に読んだ時に終わっていた: ビルド (id `fa0f7495-2054-44b3-84c3-a6993a143557`。バージョン 1.0.0 のビルド 1) の `processingState` が `VALID`、内部テストの状態 (`buildBetaDetail` の `internalBuildState`) が `IN_BETA_TESTING`、`usesNonExemptEncryption` が false (輸出コンプライアンスの質問は出ていない)
- ログ全文の ` error: ` は 0 行、` warning: ` は 2 行で、どちらも `Metadata extraction skipped, no AppIntents.framework dependency found` (App Intents を使っていないことの通知)

### App Store Connect API でできなかった操作

2026-11-18 に、設定済みの API Key で試した結果。

- App Group の登録と割り当て: App Group を扱う API が無い。`GET /v1/appGroups` は `404 NOT_FOUND`「The path provided does not match a defined resource type.」を返した
- アプリの登録: `POST /v1/apps` は `403 FORBIDDEN_ERROR`「The resource 'apps' does not allow 'CREATE'. Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE」を返した

どちらも、Apple ID でログインした状態 (2 ファクタ認証を通したセッション) が要る。fastlane の `produce` がこの 2 つを行う ( https://docs.fastlane.tools/actions/produce/ )。2026-11-18 に、owner が `spaceauth` を実行した後、agent が残りを次のとおり実行した (fastlane 2.240.1)。

```sh
# owner が、通常のターミナルで 1 回だけ実行する (2 ファクタ認証のコードを入力する。agent は代行できない)
fastlane spaceauth -u "$FASTLANE_USER"

# 以降は agent が実行した
fastlane produce group -g group.com.bannzai.poppo -n "Poppo"
fastlane produce associate_group -a com.bannzai.poppo group.com.bannzai.poppo
fastlane produce associate_group -a com.bannzai.poppo.keyboard group.com.bannzai.poppo
fastlane produce create -a com.bannzai.poppo --app_name "Poppo チャット翻訳キーボード" --sku com.bannzai.poppo --language ja --app_version 1.0.0 --skip_devcenter
```

- App Group は「Created group D9BJ69MLDU」、割り当ては 2 回とも「Finalising association with 1 groups」「Done!」と出た。その後に発行した 2 つの profile の `com.apple.security.application-groups` に `group.com.bannzai.poppo` が入っている
- アプリは「Successfully created new app 'Poppo チャット翻訳キーボード' on App Store Connect with ID 6836208900」と出た。`GET /v1/apps?filter[bundleId]=com.bannzai.poppo` でも、bundle ID が完全に一致するアプリの id は `6836208900`

### App Store Connect のアプリの名前

App Store Connect のアプリの名前は、仮の「Poppo チャット翻訳キーボード」で登録してある。`--app_name "Poppo"` での登録は、「The App Name you entered is already being used.」で失敗した (ほかのアカウントのアプリがこの名前を使っている)。

- TestFlight と App Store に出るのはこの名前で、ホーム画面に出る名前 (`CFBundleDisplayName`) は `Poppo` のまま
- App Store に出す名前は決まっていない。公開の前に owner が決め、App Store Connect で書き換える (`documents/DIRECTION.md`「決めたこと」)

## workflow を作り直す時

`ios-deploy.yml` は、ios-deploy-actions skill の `scaffold-ios-deploy.sh` で生成した後に手で直してある。生成に使った引数:

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/scaffold-ios-deploy.sh --root . \
  --var PROJECT_FLAG=-project --var PROJECT_PATH=Poppo.xcodeproj --var SCHEME=Poppo \
  --var DEVELOPMENT_TEAM=<Team ID> --var MACOS_RUNNER=xcode-27 --var BUILD_NUMBER_OFFSET=0 \
  --var 'EXTRA_XCODEBUILD_FLAGS=DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM' \
  --profile 'com.bannzai.poppo=Poppo.AppStore=IOS_PROVISIONING_PROFILE_BASE64' \
  --profile 'com.bannzai.poppo.keyboard=Poppo.PoppoKeyboard.AppStore=IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64'
```

手で直した所:

- `on:` から `push` を外し、`workflow_dispatch` に入力 `developer_menu` を足した
- 「Archive」の step に、`developer_menu` の時だけ DEBUG の条件を足す処理を入れた
- 1 行目の管理マーカー (`# managed-by: ios-deploy-actions (bannzai/castle)`) を外した。scaffold は 1 行目がこのマーカーのファイルだけを上書きする (`scaffold-ios-deploy.sh` のヘッダー)。マーカーを残すと、scaffold を実行し直した時に手で直した所が上書きされ、push での起動が戻る。マーカーが無いファイルには `action=unmanaged` (exit 2) を返して上書きしない (`--force` を付けた時を除く)

テンプレートの更新を取り込む時は、別の場所 (`--root` に空のディレクトリ) に生成して差分を見比べ、上の手で直した所を残して取り込む。

runner は `xcode-27` (iOS 27 の SDK がある GitHub-hosted runner。`ci.yml` と同じ)。

## セッション再開

この文書を書いたセッション ( https://github.com/bannzai/poppo/issues/19 の実装)。

```sh
cd /Users/bannzai/worktrees/bannzai/poppo/issue-19
claude --resume ffda0165-b446-409c-a2c0-b444bc895a9b
```
