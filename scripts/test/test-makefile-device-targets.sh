#!/usr/bin/env bash
# Makefile の build-ios-device / device / install-device のテスト。xcodebuild と xcrun を記録するだけの偽物に差し替えて、
# 署名の Team ID が空の時に止まること (build-ios-device は署名しないので止まらないこと) と、
# 入れる実機の決め方の優先順 (DEVICE > IOS_DEVICE_UDID > 自動) を確かめる。
# Usage: bash scripts/test/test-makefile-device-targets.sh
# 偽物を PATH の先頭に置くため、本物の xcodebuild・xcrun は呼ばれない (ビルドもしない)。
# 書く場所は一時ディレクトリと、Makefile が使う tmp/devices.json だけ。何度実行しても同じ結果になる
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
log="$work/calls.log"
pass=0
fail=0

mkdir -p "$work/bin"

cat > "$work/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
echo "xcodebuild $*" >> "$STUB_LOG"
STUB

# devicectl の一覧 (--json-output <path>) を求められた時だけ、テストが用意した JSON をその path に置く。
# STUB_FAIL_ON が空でなく、呼び出しがその文字列を含む時は、記録した後に失敗する (アプリを入れる操作の失敗を模すため)
cat > "$work/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
echo "xcrun $*" >> "$STUB_LOG"
if [ -n "${STUB_FAIL_ON:-}" ]; then
  case "$*" in *"$STUB_FAIL_ON"*) exit 1 ;; esac
fi
previous=""
for argument in "$@"; do
  if [ "$previous" = "--json-output" ]; then
    cp "$STUB_DEVICES_JSON" "$argument"
  fi
  previous="$argument"
done
STUB

chmod +x "$work/bin/xcodebuild" "$work/bin/xcrun"

echo '{"result":{"devices":[{"identifier":"PHONE-AUTO","hardwareProperties":{"reality":"physical"},"connectionProperties":{"tunnelState":"disconnected"}}]}}' > "$work/one-device.json"
echo '{"result":{"devices":[]}}' > "$work/no-device.json"

# make を偽物の xcodebuild・xcrun で実行し、出力を output、exit code を code、呼び出しの記録を $log に残す。
# 第 1 引数は devicectl の一覧として返す JSON。残りは make の引数。
# 開発マシンの環境変数 (FASTLANE_TEAM_ID・IOS_DEVICE_UDID 等) に左右されないよう、変数は必ず make の引数で渡す
run_make() {
  : > "$log"
  output="$(cd "$repo" && PATH="$work/bin:$PATH" STUB_LOG="$log" STUB_DEVICES_JSON="$1" make -s "${@:2}" 2>&1)"
  code=$?
}

# 条件 (コマンド) が成り立てば PASS、成り立たなければ FAIL と、その時の出力と記録を出す
check() {
  local description="$1"
  shift
  if "$@"; then
    echo "PASS: ${description}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${description}"
    echo "  exit=${code} 出力: ${output}"
    echo "  記録: $(tr '\n' '|' < "$log")"
    fail=$((fail + 1))
  fi
}

# 直前の make が失敗し、出力に引数の文字列を含む時に成り立つ
failed_with() { [ "$code" -ne 0 ] && printf '%s' "$output" | grep -qF "$1"; }
# 直前の make の出力が引数の文字列を含まない時に成り立つ
output_lacks() { ! printf '%s' "$output" | grep -qF "$1"; }
# 直前の make が成功した時に成り立つ
succeeded() { [ "$code" -eq 0 ]; }
# 直前の make が失敗した時に成り立つ
failed() { [ "$code" -ne 0 ]; }
# 直前の make が、引数の文字列を含む呼び出しを偽物の xcodebuild・xcrun にした時に成り立つ
called() { grep -qF -- "$1" "$log"; }
# 直前の make が、引数の文字列を含む呼び出しを 1 度もしなかった時に成り立つ
not_called() { ! grep -qF -- "$1" "$log"; }

run_make "$work/one-device.json" device DEVELOPMENT_TEAM= FASTLANE_TEAM_ID=
check "device: Team ID が空の時はエラーで止まる" failed_with "DEVELOPMENT_TEAM が空です"
check "device: Team ID が空の時は xcodebuild を呼ばない" not_called "xcodebuild"

run_make "$work/one-device.json" device DEVELOPMENT_TEAM=TEAM123
check "device: Team ID がある時は成功する" succeeded
check "device: Team ID を xcodebuild に渡す" called "DEVELOPMENT_TEAM=TEAM123 build"
check "device: 実機向け (generic/platform=iOS) でビルドする" called "-destination generic/platform=iOS -allowProvisioningUpdates"

run_make "$work/one-device.json" build-ios-device DEVELOPMENT_TEAM= FASTLANE_TEAM_ID=
check "build-ios-device: Team ID が空でも成功する (署名しない)" succeeded
check "build-ios-device: 実機向け (generic/platform=iOS) で、署名なしでビルドする" called "-destination generic/platform=iOS CODE_SIGNING_ALLOWED=NO build"
check "build-ios-device: 実機に入れる操作をしない" not_called "devicectl"

run_make "$work/one-device.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE=PHONE-A IOS_DEVICE_UDID=PHONE-B
check "install-device: DEVICE と IOS_DEVICE_UDID の両方がある時は DEVICE に入れる" called "devicectl device install app --device PHONE-A "
check "install-device: DEVICE がある時は devicectl の一覧を取らない" not_called "list devices"
check "install-device: 入れた後に同じ実機でアプリを起動する" called "devicectl device process launch --device PHONE-A com.bannzai.poppo"

run_make "$work/one-device.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE= IOS_DEVICE_UDID=PHONE-B
check "install-device: DEVICE が空で IOS_DEVICE_UDID がある時はそれに入れる" called "devicectl device install app --device PHONE-B "
check "install-device: IOS_DEVICE_UDID がある時は devicectl の一覧を取らない" not_called "list devices"

run_make "$work/one-device.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE= IOS_DEVICE_UDID=
check "install-device: どちらも空の時は devicectl の一覧から決めた実機に入れる" called "devicectl device install app --device PHONE-AUTO "

run_make "$work/no-device.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE= IOS_DEVICE_UDID=
check "install-device: 実機を決められない時はエラーで止まる" failed_with "実機が見つかりません"
check "install-device: 実機を決められない時はアプリを入れない" not_called "device install app"

echo '{"result":' > "$work/broken.json"
run_make "$work/broken.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE= IOS_DEVICE_UDID=
check "install-device: devicectl の一覧を読めない時は、読めないことを伝えて止まる" failed_with "JSON として読めません"
check "install-device: devicectl の一覧を読めない時に「実機が見つかりません」と言わない" output_lacks "実機が見つかりません"
check "install-device: devicectl の一覧を読めない時はアプリを入れない" not_called "device install app"

run_make "$work/one-device.json" install-device DEVELOPMENT_TEAM= FASTLANE_TEAM_ID= DEVICE=PHONE-A
check "install-device: Team ID が空の時はエラーで止まる" failed_with "DEVELOPMENT_TEAM が空です"
check "install-device: Team ID が空の時はアプリを入れない" not_called "device install app"

export STUB_FAIL_ON="device install app"
run_make "$work/one-device.json" install-device DEVELOPMENT_TEAM=TEAM123 DEVICE=PHONE-A
unset STUB_FAIL_ON
check "install-device: アプリを入れる操作が失敗した時は失敗で終わる" failed
check "install-device: アプリを入れる操作が失敗した時は、前から入っているアプリを起動しない" not_called "device process launch"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
