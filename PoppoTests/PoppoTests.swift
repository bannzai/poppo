import Foundation
import Testing
@testable import Poppo

/// テストターゲットがアプリをホストにしてビルド・実行されることを確かめる最初のテスト。
/// bundle identifier は App Group・キーボード拡張の識別子の接頭辞になるため、意図せず変わった時に落とす
@Test func appBundleIdentifierIsPoppo() {
    #expect(Bundle.main.bundleIdentifier == "com.bannzai.poppo")
}

/// 本体アプリの String Catalog (Poppo/Localizable.xcstrings) の日本語訳が、ビルドしたアプリに入っていること。
/// ターゲットにリソースのビルドフェーズが無いと、同期フォルダの String Catalog は組み込まれず、日本語の端末でも英語のまま表示される
@Test func appBundleContainsJapaneseLocalization() {
    #expect(Bundle.main.localizations.contains("ja"))
}

/// 本体アプリが iPhone 専用としてビルドされていること。
/// 公開した後は対応する端末を減らせないため、iPad への対応は決めてから足す。意図せず iPad が入った時に落とす
@Test func appSupportsOnlyIPhone() {
    #expect(Bundle.main.object(forInfoDictionaryKey: "UIDeviceFamily") as? [Int] == [1])
}

/// キーボード拡張の String Catalog (PoppoKeyboard/Localizable.xcstrings) の日本語訳が、アプリに埋め込まれた拡張に入っていること
@Test func keyboardExtensionBundleContainsJapaneseLocalization() throws {
    #expect(
        try #require(
            Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("PoppoKeyboard.appex")) }
        ).localizations.contains("ja")
    )
}
