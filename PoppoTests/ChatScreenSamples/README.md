# チャットの画面の画像の見本

読み取りの処理 (`Poppo/ChatReading/TextRecognition.swift` の `recognizeTextLines(image:)` と `Poppo/ChatReading/MessageExtraction.swift` の `extractMessages(lines:)`) を、チャットアプリの画面の画像で確かめるための見本の置き場。`PoppoTests/ChatScreenSampleTests.swift` が、ここの画像を 1 枚ずつ読ませ、抜き出した発言が記録と一致することを `make test` (PR の CI) で確かめる。

## 記録

見本ごとの記録は `chat-screen-samples.json` に置く (項目の意味は `PoppoTests/ChatScreenSampleTests.swift` の `ChatScreenSample`)。出どころ (`source`)・利用の条件 (`usageTerms`)・画面に映っている発言 (`messages`) を、画像のファイル名 (`imageFileName`) ごとに書く。

`messages` には、画像を目で見て分かる発言を、画面の上から下の順に書く。今の実装が返す値を写さない。書き方は `documents/DIRECTION.md`「決めたこと」に合わせる。

- 画面で複数の行にわたる発言は、行を改行でつなぐ
- 名前と時刻が同じ行にある見出し行は、発言の先頭に残す
- 時刻だけの行、日付の区切り、リアクション、スレッドの返信の数、上のバーと入力欄の文字は発言に含めない
- `isFromUser` は、右に寄った吹き出しの発言だけ true にする

今の実装で抜き出せない見本は、テストから外さず、抜き出せない事実と理由を `knownIssue` に書く。テストはその見本を既知の不具合として扱い、抜き出せるようになった時に失敗して `knownIssue` の消し忘れを知らせる。

## 見本を足す時

画像は次のどれから集めてもよい (owner の決定。 https://github.com/bannzai/poppo/issues/52 )。

1. 作った会話で作る画像。`documents/design/chat-screen-samples/` に HTML を足し、`bash documents/design/chat-screen-samples/render.sh` で描く
2. フリー素材
3. インターネットで公開されている画像

どの画像でも、実在の個人の氏名・顔写真・連絡先が映っているものは入れない (映っている部分を塗りつぶした画像は入れてよい)。企業やサービスの公式アカウントの名前と、作った名前は入れてよい。2 と 3 の画像は、`source` に取ってきた URL を、`usageTerms` に分かる範囲の利用の条件を書く。

ファイル名は `chat-screen-sample-<見た目>-<言語>.png` にする (テストのバンドルではディレクトリが無くなり、ほかのリソースと同じ場所に並ぶため)。

## 権利を持つ人からの申し立て

見本の画像について、権利を持つ人が削除を求める時は、このリポジトリの issue ( https://github.com/bannzai/poppo/issues/new ) で、対象の画像 (ファイル名か、元の画像の URL) を知らせてもらう。

申し立てを受けたら、`chat-screen-samples.json` の `source` と `imageFileName` から対象の見本を決め、その画像と記録の要素を消す。
