#!/usr/bin/env bash
# `xcrun devicectl list devices --json-output <file>` の JSON から、アプリを入れる実機を 1 台に決めて identifier を出力する。
# Usage: resolve-physical-device.sh <devices.json>
# 出力: 決まった実機の identifier (1 行)。決められない時は何も出力せず exit 1。
#       引数の数が違う・ファイルが無い時は exit 2、ファイルを devicectl の一覧の JSON として読めない時は exit 3、
#       jq が無い時は exit 4
# 決め方: devicectl は起動中の simulator も一覧に載せるため、先に実機 (hardwareProperties.reality == "physical") に絞る。
#         実機が 1 台ならそれ。複数台なら接続中 (connectionProperties.tunnelState == "connected") が 1 台の時だけそれ。
#         待機中の実機は disconnected になることがあるため、1 台の時は接続の状態を見ない
# 読むだけで冪等
set -euo pipefail

if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
  echo "Usage: resolve-physical-device.sh <devices.json>" >&2
  exit 2
fi

if ! command -v jq > /dev/null; then
  echo "Error: jq が見つかりません (brew install jq で入れてください)" >&2
  exit 4
fi

identifier="$(jq -r '
  [.result.devices[] | select(.hardwareProperties.reality == "physical")]
  | if length == 1 then .[0]
    else (map(select(.connectionProperties.tunnelState == "connected")) | if length == 1 then .[0] else empty end)
    end
  | .identifier // empty
' "$1")" || { echo "Error: $1 を devicectl の一覧の JSON として読めません" >&2; exit 3; }

[ -n "$identifier" ] || exit 1
echo "$identifier"
