import Testing
import UIKit
@testable import Poppo

/// 返信案のコピーで、クリップボードに返信案の文 (相手の言語の文) が入り、意味の文は入らないこと。
/// 端末全体のクリップボードを書き換えないよう、このテストだけの pasteboard を使う
@Test func copyPutsReplySuggestionTextOnPasteboard() {
    let pasteboard = UIPasteboard.withUniqueName()
    defer {
        UIPasteboard.remove(withName: pasteboard.name)
    }

    copy(replySuggestion: ReplySuggestion(text: "Sounds good", meaning: "いいですね"), pasteboard: pasteboard)

    #expect(pasteboard.string == "Sounds good")
}

/// 返信案を pasteboard に入れる時の設定が、入れた文をほかの端末へ渡さない設定になっていること
@Test func replySuggestionPasteboardOptionsKeepItemsOnThisDevice() {
    #expect(replySuggestionPasteboardOptions()[.localOnly] as? Bool == true)
}
