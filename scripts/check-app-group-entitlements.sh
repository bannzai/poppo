#!/usr/bin/env bash
# 本体アプリとキーボード拡張が、同じ App Group を使う設定になっているかを確かめる。
# 読み取り結果は App Group の共有コンテナ経由で本体アプリからキーボードへ渡すため、どれか 1 つでもずれるとキーボードが読めなくなる。
# 確かめるのは次の 3 つが一致していること:
#   - Shared/LatestReading.swift の appGroupIdentifier
#   - Config/Poppo.entitlements と Config/PoppoKeyboard.entitlements の com.apple.security.application-groups
#   - Poppo.xcodeproj の 2 つのターゲットの Debug と Release が、そのターゲットの entitlements を CODE_SIGN_ENTITLEMENTS に指定していること。
#     ターゲットは構成の PRODUCT_BUNDLE_IDENTIFIER で見分ける (指定の行の数だけを数えると、別のターゲットの構成へ移った指定を見逃す)
# Usage: bash scripts/check-app-group-entitlements.sh [リポジトリのルート (省略時はこのスクリプトの 1 つ上)]
# exit 0: 一致している / exit 1: ずれがある (ずれた場所を標準エラーに出す)
# ファイルを読むだけで何も書かない。何度実行しても同じ結果になる
set -uo pipefail

root="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
errors=0

# ずれを 1 件、標準エラーに出して数える
report() {
  echo "NG: $1" >&2
  errors=$((errors + 1))
}

# entitlements ファイル ($1) の com.apple.security.application-groups に並ぶ識別子を、1 行に 1 つ出す
app_groups() {
  awk '/<key>com\.apple\.security\.application-groups<\/key>/ { inside = 1; next } inside && /<\/array>/ { exit } inside' "$1" \
    | sed -n 's:.*<string>\(.*\)</string>.*:\1:p'
}

# project.pbxproj ($1) の構成 (XCBuildConfiguration) ごとに、「構成名<TAB>PRODUCT_BUNDLE_IDENTIFIER<TAB>CODE_SIGN_ENTITLEMENTS」を 1 行出す。
# 指定の無い項目は空で出す
build_configurations() {
  awk '
    /^\t\t[0-9A-F]+ \/\* .* \*\/ = \{$/ { name = $3; bundle = ""; entitlements = ""; is_configuration = 0; next }
    /isa = XCBuildConfiguration;/ { is_configuration = 1 }
    /^\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = / { bundle = $3; sub(/;$/, "", bundle) }
    /^\t\t\t\tCODE_SIGN_ENTITLEMENTS = / { entitlements = $3; sub(/;$/, "", entitlements) }
    /^\t\t\};$/ { if (is_configuration) print name "\t" bundle "\t" entitlements; is_configuration = 0 }
  ' "$1"
}

swift_app_group="$(sed -n 's/^let appGroupIdentifier = "\(.*\)"$/\1/p' "$root/Shared/LatestReading.swift" 2>/dev/null)"
if [ -z "$swift_app_group" ]; then
  report "Shared/LatestReading.swift に appGroupIdentifier の定義が無い"
fi

configurations="$(build_configurations "$root/Poppo.xcodeproj/project.pbxproj")"

# ターゲット名と、そのターゲットの構成の PRODUCT_BUNDLE_IDENTIFIER の組
for target_and_bundle in Poppo:com.bannzai.poppo PoppoKeyboard:com.bannzai.poppo.keyboard; do
  target="${target_and_bundle%%:*}"
  entitlements="$root/Config/$target.entitlements"
  if [ ! -f "$entitlements" ]; then
    report "Config/$target.entitlements が無い"
    continue
  fi
  if [ "$(app_groups "$entitlements")" != "$swift_app_group" ]; then
    report "Config/$target.entitlements の App Group ($(app_groups "$entitlements" | tr '\n' ' ')) が appGroupIdentifier ($swift_app_group) と違う"
  fi
  for configuration in Debug Release; do
    if ! printf '%s\n' "$configurations" | grep -qxF "$(printf '%s\t%s\t%s' "$configuration" "${target_and_bundle#*:}" "Config/$target.entitlements")"; then
      report "Poppo.xcodeproj の $target ターゲット (${target_and_bundle#*:}) の $configuration が Config/$target.entitlements を CODE_SIGN_ENTITLEMENTS に指定していない"
    fi
  done
done

[ "$errors" -eq 0 ]
