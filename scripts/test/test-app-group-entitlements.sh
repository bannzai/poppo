#!/usr/bin/env bash
# scripts/check-app-group-entitlements.sh のテスト。今のリポジトリで通ることと、
# 設定を 1 か所ずつずらした写しでは、ずれた場所を出して失敗することを確かめる。
# Usage: bash scripts/test/test-app-group-entitlements.sh
# 書く場所は一時ディレクトリだけ。何度実行しても同じ結果になる
set -uo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
pass=0
fail=0

# 検査が読むファイルだけを、リポジトリから写しの場所 ($1) へ写す
copy_fixture() {
  mkdir -p "$1/Shared" "$1/Config" "$1/Poppo.xcodeproj"
  cp "$repo/Shared/LatestReading.swift" "$1/Shared/"
  cp "$repo/Config/Poppo.entitlements" "$repo/Config/PoppoKeyboard.entitlements" "$1/Config/"
  cp "$repo/Poppo.xcodeproj/project.pbxproj" "$1/Poppo.xcodeproj/"
}

# 検査を $1 の場所に対して実行し、出力を output、exit code を code に残す
run_check() {
  output="$(bash "$repo/scripts/check-app-group-entitlements.sh" "$1" 2>&1)"
  code=$?
}

# 条件 (コマンド) が成り立てば PASS、成り立たなければ FAIL と、その時の出力を出す
check() {
  local description="$1"
  shift
  if "$@"; then
    echo "PASS: ${description}"
    pass=$((pass + 1))
  else
    echo "FAIL: ${description}"
    echo "  exit=${code} 出力: ${output}"
    fail=$((fail + 1))
  fi
}

# 直前の検査が成功し、何も出力しなかった時に成り立つ
succeeded_silently() { [ "$code" -eq 0 ] && [ -z "$output" ]; }
# 直前の検査が失敗し、出力に引数の文字列を含む時に成り立つ
failed_with() { [ "$code" -ne 0 ] && printf '%s' "$output" | grep -qF "$1"; }

run_check "$repo"
check "今のリポジトリ: 3 つの設定が一致していて通る" succeeded_silently

copy_fixture "$work/same"
run_check "$work/same"
check "写し (何も変えない): 通る" succeeded_silently

copy_fixture "$work/keyboard-group"
sed -i.bak 's:<string>group\.com\.bannzai\.poppo</string>:<string>group.com.bannzai.poppo.keyboard</string>:' "$work/keyboard-group/Config/PoppoKeyboard.entitlements"
run_check "$work/keyboard-group"
check "キーボード拡張の App Group だけ違う: 失敗する" failed_with "Config/PoppoKeyboard.entitlements の App Group (group.com.bannzai.poppo.keyboard ) が appGroupIdentifier (group.com.bannzai.poppo) と違う"

copy_fixture "$work/app-no-group"
sed -i.bak '/<string>group\.com\.bannzai\.poppo<\/string>/d' "$work/app-no-group/Config/Poppo.entitlements"
run_check "$work/app-no-group"
check "本体アプリの entitlements に App Group が無い: 失敗する" failed_with "Config/Poppo.entitlements の App Group () が appGroupIdentifier (group.com.bannzai.poppo) と違う"

copy_fixture "$work/app-missing-file"
mv "$work/app-missing-file/Config/Poppo.entitlements" "$work/app-missing-file/Config/Poppo.entitlements.moved"
run_check "$work/app-missing-file"
check "本体アプリの entitlements のファイルが無い: 失敗する" failed_with "Config/Poppo.entitlements が無い"

copy_fixture "$work/swift-group"
sed -i.bak 's/^let appGroupIdentifier = ".*"$/let appGroupIdentifier = "group.com.bannzai.other"/' "$work/swift-group/Shared/LatestReading.swift"
run_check "$work/swift-group"
check "Swift の appGroupIdentifier だけ違う: 本体アプリの entitlements との違いを出して失敗する" failed_with "Config/Poppo.entitlements の App Group (group.com.bannzai.poppo ) が appGroupIdentifier (group.com.bannzai.other) と違う"
check "Swift の appGroupIdentifier だけ違う: キーボード拡張の entitlements との違いも出す" failed_with "Config/PoppoKeyboard.entitlements の App Group (group.com.bannzai.poppo ) が appGroupIdentifier (group.com.bannzai.other) と違う"

copy_fixture "$work/swift-no-definition"
sed -i.bak '/^let appGroupIdentifier = /d' "$work/swift-no-definition/Shared/LatestReading.swift"
run_check "$work/swift-no-definition"
check "Swift に appGroupIdentifier の定義が無い: 失敗する" failed_with "Shared/LatestReading.swift に appGroupIdentifier の定義が無い"

# Debug と Release の 2 か所のうち、ファイルで先に出てくる 1 か所 (キーボード拡張の Release) だけを消す
copy_fixture "$work/project-one-configuration"
awk '/CODE_SIGN_ENTITLEMENTS = Config\/PoppoKeyboard\.entitlements;/ && !removed { removed = 1; next } { print }' \
  "$repo/Poppo.xcodeproj/project.pbxproj" > "$work/project-one-configuration/Poppo.xcodeproj/project.pbxproj"
run_check "$work/project-one-configuration"
check "キーボード拡張の Release にだけ entitlements の指定が無い: Release を名指しして失敗する" failed_with "Poppo.xcodeproj の PoppoKeyboard ターゲット (com.bannzai.poppo.keyboard) の Release が Config/PoppoKeyboard.entitlements を CODE_SIGN_ENTITLEMENTS に指定していない"
# 直前の検査の出力に、引数の文字列が含まれない時に成り立つ
not_reported() { ! printf '%s' "$output" | grep -qF "$1"; }
check "キーボード拡張の Release にだけ entitlements の指定が無い: 指定が残っている Debug は出さない" not_reported "PoppoKeyboard ターゲット (com.bannzai.poppo.keyboard) の Debug"

# キーボード拡張の Release の指定を、テストのターゲットの Release の構成へ移す。指定の行の数は 2 のまま変わらない
copy_fixture "$work/project-moved-to-other-target"
awk '
  /CODE_SIGN_ENTITLEMENTS = Config\/PoppoKeyboard\.entitlements;/ && !removed { removed = 1; next }
  /PRODUCT_BUNDLE_IDENTIFIER = com\.bannzai\.poppo\.tests;/ { tests_configurations++; if (tests_configurations == 2) print "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Config/PoppoKeyboard.entitlements;" }
  { print }
' "$repo/Poppo.xcodeproj/project.pbxproj" > "$work/project-moved-to-other-target/Poppo.xcodeproj/project.pbxproj"
# 指定を別のターゲットへ移した写しで、キーボード拡張の entitlements の指定の行がちょうど 2 行ある時に成り立つ
line_count_is_two() { [ "$(grep -c "CODE_SIGN_ENTITLEMENTS = Config/PoppoKeyboard.entitlements;" "$work/project-moved-to-other-target/Poppo.xcodeproj/project.pbxproj")" -eq 2 ]; }
check "指定を別のターゲットへ移した写し: 指定の行の数は 2 のまま (行の数だけでは見分けられない写しになっている)" line_count_is_two
run_check "$work/project-moved-to-other-target"
check "キーボード拡張の Release の指定が別のターゲットの構成へ移っている: 失敗する" failed_with "Poppo.xcodeproj の PoppoKeyboard ターゲット (com.bannzai.poppo.keyboard) の Release が Config/PoppoKeyboard.entitlements を CODE_SIGN_ENTITLEMENTS に指定していない"

copy_fixture "$work/project-no-app-entitlements"
sed -i.bak '/CODE_SIGN_ENTITLEMENTS = Config\/Poppo\.entitlements;/d' "$work/project-no-app-entitlements/Poppo.xcodeproj/project.pbxproj"
run_check "$work/project-no-app-entitlements"
check "本体アプリのターゲットに entitlements の指定が無い: Debug を名指しして失敗する" failed_with "Poppo.xcodeproj の Poppo ターゲット (com.bannzai.poppo) の Debug が Config/Poppo.entitlements を CODE_SIGN_ENTITLEMENTS に指定していない"
check "本体アプリのターゲットに entitlements の指定が無い: Release も名指しする" failed_with "Poppo.xcodeproj の Poppo ターゲット (com.bannzai.poppo) の Release が Config/Poppo.entitlements を CODE_SIGN_ENTITLEMENTS に指定していない"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
