#!/usr/bin/env bash
# このディレクトリの HTML (作った会話を、チャットアプリの画面に似せて描いたもの) を PNG にして、
# テストが読む見本の置き場 (PoppoTests/ChatScreenSamples/) に書き出す。
# 同じ HTML からは同じ名前の PNG を上書きするため、何度実行してもよい (冪等)。
# 使い方: bash documents/design/chat-screen-samples/render.sh
# 前提: macOS の Google Chrome (CHROME で実行ファイルを差し替えられる)
set -euo pipefail

# macOS の Google Chrome の既定のインストール先
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
source_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="$(cd "${source_dir}/../../.." && pwd)/PoppoTests/ChatScreenSamples"

mkdir -p "${output_dir}"
for html in "${source_dir}"/*.html; do
  # 393 × 852pt を 3 倍で描く: iPhone 17 のスクリーンショットの大きさ (1179 × 2556px) に合わせるため
  "${chrome}" --headless --hide-scrollbars --window-size=393,852 --force-device-scale-factor=3 \
    --screenshot="${output_dir}/chat-screen-sample-$(basename "${html}" .html).png" "file://${html}" 2> /dev/null
done
