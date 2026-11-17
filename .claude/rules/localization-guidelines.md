---
paths:
  - "Poppo/**/*.swift"
  - "PoppoKeyboard/**/*.swift"
  - "**/Localizable.xcstrings"
---

# ローカライゼーションガイドライン

## 基本ルール

- アプリの基本言語は**英語**。`Text()` などの SwiftUI 標準のローカライズ対象や `String(localized:)` の文字列は**英文**で書く (英語圏のユーザーにはそのまま表示される)
- コード上のコメントは**日本語**
- 翻訳は String Catalog で管理する。本体アプリは `Poppo/Localizable.xcstrings`、キーボード拡張は `PoppoKeyboard/Localizable.xcstrings`。コーディング段階での編集は、コードで追加した英語文言の **ja エントリーの追加に限る**。他言語のエントリーの追加・既存訳の変更は指示がある時だけ行う (他言語は `/translate-app-xcstrings` skill が英語原文と日本語訳を元に一括で翻訳する。プロジェクト固有の翻訳スクリプトは作らない)

## `// ja:` コメント

- アプリの UI 翻訳が必要な箇所 (`Text()` や `String(localized:)`) の直上に `// ja:` で日本語訳を書く。enum のケースやプロパティの説明コメントなど翻訳対象でないものには付けない
- 訳文中の改行は `\n` ではなく、コメントの空行として残す

## 固有名詞と機能名の扱い

- アプリ内の固有名詞・機能名が文中に出てくる場合は、直接文字列に含めず `Text()` の補間で埋め込む (固有名詞も多言語対応の対象で、String Catalog で一元管理するため)
- 固有名詞は引用符で囲む。英語はシングルクォート (`''`)、日本語は (`「」`)

```swift
// ja: 「取り込みを開始」を押してください
Text("You should press '\(Text("Start capture"))'")
```

## 翻訳の対象と、アプリが扱う文章の区別

- 画面から読み取ったチャットの文言・翻訳結果・返信案は利用者のデータで、UI 文言ではない。`Text(verbatim:)` で表示し、String Catalog に入れない
