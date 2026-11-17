import Foundation
import Testing
@testable import Poppo

/// テストターゲットがアプリをホストにしてビルド・実行されることを確かめる最初のテスト。
/// bundle identifier は App Group・キーボード拡張の識別子の接頭辞になるため、意図せず変わった時に落とす
@Test func appBundleIdentifierIsPoppo() {
    #expect(Bundle.main.bundleIdentifier == "com.bannzai.poppo")
}
