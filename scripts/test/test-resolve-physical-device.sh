#!/usr/bin/env bash
# scripts/resolve-physical-device.sh のテスト。devicectl の JSON を模した入力で、実機を 1 台に決める分岐を確かめる。
# Usage: bash scripts/test/test-resolve-physical-device.sh
# 一時ディレクトリだけに書き、何度実行しても同じ結果になる
set -uo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/resolve-physical-device.sh"
work="$(mktemp -d)"
pass=0
fail=0

# device <identifier> <reality> <tunnelState> の形の引数から、devicectl の一覧の JSON を作る
write_devices() {
  local file="$1"
  shift
  local items=()
  while [ "$#" -gt 0 ]; do
    items+=("{\"identifier\":\"$1\",\"hardwareProperties\":{\"reality\":\"$2\"},\"connectionProperties\":{\"tunnelState\":\"$3\"}}")
    shift 3
  done
  echo "{\"result\":{\"devices\":[$(IFS=,; echo "${items[*]}")]}}" > "$file"
}

# 期待する出力と exit code を、実際の結果と比べる
expect() {
  local description="$1" expected_output="$2" expected_code="$3" file="$4"
  local output code
  output="$(bash "$script" "$file" 2>/dev/null)"
  code=$?
  if [ "$output" = "$expected_output" ] && [ "$code" -eq "$expected_code" ]; then
    echo "PASS: $description"
    pass=$((pass + 1))
  else
    echo "FAIL: ${description} (出力='${output}' exit=${code} / 期待は 出力='${expected_output}' exit=${expected_code})"
    fail=$((fail + 1))
  fi
}

write_devices "$work/none.json"
expect "端末が 1 台も無い時は決められない" "" 1 "$work/none.json"

write_devices "$work/simulator-only.json" SIM-1 simulated connected
expect "接続中の simulator だけの時は決められない" "" 1 "$work/simulator-only.json"

write_devices "$work/one-disconnected.json" PHONE-1 physical disconnected
expect "実機が 1 台なら、待機中 (disconnected) でもそれに決まる" "PHONE-1" 0 "$work/one-disconnected.json"

write_devices "$work/one-with-simulator.json" SIM-1 simulated connected PHONE-1 physical disconnected
expect "接続中の simulator があっても、実機 1 台に決まる" "PHONE-1" 0 "$work/one-with-simulator.json"

write_devices "$work/two-one-connected.json" PHONE-1 physical disconnected PHONE-2 physical connected
expect "実機が 2 台で接続中が 1 台なら、接続中の方に決まる" "PHONE-2" 0 "$work/two-one-connected.json"

write_devices "$work/two-both-connected.json" PHONE-1 physical connected PHONE-2 physical connected
expect "実機が 2 台とも接続中なら決められない" "" 1 "$work/two-both-connected.json"

write_devices "$work/two-none-connected.json" PHONE-1 physical disconnected PHONE-2 physical disconnected
expect "実機が 2 台とも待機中なら決められない" "" 1 "$work/two-none-connected.json"

expect "ファイルが無い時は使い方のエラー (exit 2)" "" 2 "$work/missing.json"

echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
