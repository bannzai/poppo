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
