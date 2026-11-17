import UIKit
import UniformTypeIdentifiers

/// 返信案の文 (相手の言語の文) を pasteboard に入れる。利用者がチャットアプリの入力欄へ貼り付けるために使う。
/// 入れた文は、この端末の中でだけ貼り付けられる
func copy(replySuggestion: ReplySuggestion, pasteboard: UIPasteboard) {
    pasteboard.setItems([[UTType.utf8PlainText.identifier: replySuggestion.text]], options: replySuggestionPasteboardOptions())
}

/// 返信案を pasteboard に入れる時の設定。入れた文を、ほかの端末へ渡さない
func replySuggestionPasteboardOptions() -> [UIPasteboard.OptionsKey: Any] {
    // localOnly: コピーした文をほかの端末へ渡さない (Apple の文書: 「A Boolean value that specifies that the pasteboard items should not be
    // available to other devices through the Handoff feature.」 https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly )。
    // チャットから作った文を端末の中だけで扱う決まり (docs/PrivacyPolicy-ja.md「スクリーンショットから読み取る情報」) に合わせる
    [.localOnly: true]
}
