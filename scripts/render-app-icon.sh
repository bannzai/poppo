#!/usr/bin/env bash
# アプリアイコン (Poppo/Assets.xcassets/AppIcon.appiconset/AppIcon.png) を、本体アプリの中で使う鳥の絵
# (Poppo/Assets.xcassets/PoppoBird.imageset/poppo-bird.svg) から作り直す。鳥の絵を直した時に実行する。
#
# 使い方: bash scripts/render-app-icon.sh
# 要るもの: rsvg-convert (librsvg) と magick (ImageMagick)
# 出力: 1024 × 1024・透明の部分が無い PNG。何度実行しても同じ絵から同じアイコンができる
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bird_svg="$repository_root/Poppo/Assets.xcassets/PoppoBird.imageset/poppo-bird.svg"
app_icon_png="$repository_root/Poppo/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
# 途中の画像は、git の管理から外れている tmp/ に置く
bird_png="$repository_root/tmp/poppo-bird.png"
mkdir -p "$repository_root/tmp"

# 840: 1024 の地に対して鳥の絵の枠を約 82% の幅で置く。ホーム画面の大きさ (60pt) でも目とくちばしが潰れず、
# iOS が角を丸めても尾羽とくちばしが切れない大きさとして、できたアイコンと、縮めた絵を見て決めた
rsvg-convert --width 840 --height 840 "$bird_svg" --output "$bird_png"

# #2BB5A0: Shared/PoppoTheme.swift の、鳥の地の色 (poppoBirdBackground) と同じ値
# +0-40: 鳥は絵の枠の中で下に寄っている (上の余白が下より広い) ため、鳥の中心が地の中心に来るよう上へ寄せる
# -alpha off: App Store に出すアイコンは透明の部分を持てないため、alpha チャンネルを落とす
magick -size 1024x1024 "xc:#2BB5A0" "$bird_png" -gravity center -geometry +0-40 -composite -alpha off "PNG24:$app_icon_png"

sips -g pixelWidth -g pixelHeight -g hasAlpha "$app_icon_png"
