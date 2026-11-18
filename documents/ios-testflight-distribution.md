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
  bash ~/.agents/skills/ios-deploy-actions/scripts/asc-api.sh GET "/v1/builds?filter[app]=<App Store Connect のアプリの id>&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate"
  ```

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
| `IOS_PROVISIONING_PROFILE_BASE64` | 本体アプリの App Store 用 provisioning profile | 未登録 (下の「初回の準備」) |
| `IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64` | キーボードの App Store 用 provisioning profile | 未登録 (下の「初回の準備」) |

登録は ios-deploy-actions skill の `register-secrets.sh` で行う (値を画面に出さない)。登録済みの名前は `gh secret list -R bannzai/poppo --env ios-deploy` で読める。

```sh
bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/poppo --env ios-deploy --secret <名前>=<値> [--secret-base64-file <名前>=<base64 にして登録するファイル>]
```

### profile を発行し直す時

発行し直すのは、profile の期限が切れる時、配布証明書を替えた時、App ID の Capability (App Group など) を変えた時。今の `.p12` の証明書は App Store Connect の証明書の id `68L9PY6PX2` で、期限は 2027-01-17。2026-11-18 にこの証明書で試しに発行した profile の期限も、同じ 2027-01-17 だった。

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

   中身を開いて確かめるのは、2026-11-18 に `create-profile` の出力 (`entitlements-check=ok`) と中身が食い違ったため。`com.bannzai.poppo` の profile を頼んだ時に `com.bannzai.poppo.keyboard` の profile が発行され、App Group が空でも `ok` が出た ( https://github.com/bannzai/castle/issues/3132 。同じ日に修正がマージされた: https://github.com/bannzai/castle/pull/3135 。修正後のスクリプトでの発行は、この文書を書いた時点では試していない)。食い違った時は、App Store Connect API の `POST /v1/profiles` を bundle ID のリソース id (`com.bannzai.poppo` は `XZPY677UXL`、`com.bannzai.poppo.keyboard` は `CQ789C575K`) を指定して直接呼ぶ

3. 2 つの Secret を登録し直す

   ```sh
   bash ~/.agents/skills/ios-deploy-actions/scripts/register-secrets.sh --repo bannzai/poppo --env ios-deploy --secret-base64-file IOS_PROVISIONING_PROFILE_BASE64=tmp/signing/Poppo_AppStore.mobileprovision --secret-base64-file IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64=tmp/signing/Poppo_PoppoKeyboard_AppStore.mobileprovision
   ```

配布証明書を替える時は、`.p12` の 2 つの Secret も登録し直し、上の証明書の id と期限を書き直す。

## 初回の準備 (2026-11-18 の状態)

| 準備 | 状態 | 方法 |
| --- | --- | --- |
| bundle ID の登録 (`com.bannzai.poppo`・`com.bannzai.poppo.keyboard`) | 済み | App Store Connect API の `POST /v1/bundleIds` |
| 2 つの App ID で App Groups の Capability を有効にする | 済み | App Store Connect API の `POST /v1/bundleIdCapabilities` (`capabilityType` は `APP_GROUPS`) |
| 配布用の environment `ios-deploy` (デプロイブランチは main だけ) | 済み | ios-deploy-actions skill の `setup-environment.sh` |
| API Key と配布証明書の Secrets | 済み | 上の「Secrets」 |
| App Group `group.com.bannzai.poppo` の登録と、2 つの App ID への割り当て | 残っている | App Store Connect API ではできない (下) |
| App Store Connect へのアプリの登録 | 残っている | App Store Connect API ではできない (下) |
| 2 つの provisioning profile の発行と Secrets の登録 | 残っている | App Group の割り当ての後に、上の「profile を発行し直す時」の手順で行う (割り当ての前に発行した profile には App Group が入らない) |
| 最初の配布と、内部テスターのグループの用意 | 残っている | 上の準備が済んだ後 |

残っている準備の進み具合と、owner に頼んでいる操作は「ユーザー作業の一覧」の issue ( https://github.com/bannzai/poppo/issues/8 ) にある。

### App Store Connect API でできなかった操作

2026-11-18 に、設定済みの API Key で試した結果。

- App Group の登録と割り当て: App Group を扱う API が無い。`GET /v1/appGroups` は `404 NOT_FOUND`「The path provided does not match a defined resource type.」を返した
- アプリの登録: `POST /v1/apps` は `403 FORBIDDEN_ERROR`「The resource 'apps' does not allow 'CREATE'. Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE」を返した

どちらも、Apple ID でログインした状態 (2 ファクタ認証を通したセッション) が要る。fastlane の `produce` がこの 2 つを行う ( https://docs.fastlane.tools/actions/produce/ )。下のコマンドは同ページの例を Poppo の値に置き換えたもので、2026-11-18 の時点では実行していない。

```sh
# owner が、通常のターミナルで 1 回だけ実行する (2 ファクタ認証のコードを入力する。agent は代行できない)
fastlane spaceauth -u "$FASTLANE_USER"

# 以降は agent が実行する
fastlane produce group -g group.com.bannzai.poppo -n "Poppo"
fastlane produce associate_group -a com.bannzai.poppo group.com.bannzai.poppo
fastlane produce associate_group -a com.bannzai.poppo.keyboard group.com.bannzai.poppo
fastlane produce create -a com.bannzai.poppo --app_name "Poppo" --sku com.bannzai.poppo --language Japanese --skip_devcenter
```

アプリの名前 (`Poppo`) が App Store でほかのアプリに使われている時は、登録が失敗する。その時は別の名前で登録し、名前は公開までに決め直す (App Store Connect の名前は、端末に出る名前 `CFBundleDisplayName` とは別に持てる)。

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
