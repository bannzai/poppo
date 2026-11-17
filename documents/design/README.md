# documents/design

見た目と体験の方向を決めてもらうためのモックと、受領したデザイン、設計の資料の置き場。決まった方向は `documents/DIRECTION.md` の「デザインの方向」に書く。

| ディレクトリ | 中身 |
| --- | --- |
| `data-structure/` | 新しいデータ構造を owner に見せた時の資料 (型定義と、操作ごとに読み書きするデータの表) |
| `mock-<日付>/` | agent が Claude Design の canvas に作ったモック。`project/canvas.json` と `project/*.dc.html` は canvas に公開したファイルそのもので、canvas の実行環境 (`./support.js`) が無いと単体では表示できない。`index.html` は同じ画面を 1 枚に並べた、ブラウザで単独で開ける写し |

canvas の URL (claude.ai/artifact) は、アカウントの切り替えや削除で開けなくなる。判断の材料を残すため、モックはここに保存してから issue にパスを書く。
