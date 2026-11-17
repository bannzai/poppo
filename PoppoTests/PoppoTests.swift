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

/// 写真へのアクセスの許可を求める時にシステムが出す説明文が、ビルドしたアプリの Info.plist に入っていること。
/// 写真ライブラリを読むアプリに必須の項目 (Apple の文書: 「This key is required if your app uses APIs that have read or write access
/// to the user’s photo library.」 https://developer.apple.com/documentation/bundleresources/information-property-list/nsphotolibraryusagedescription )
@Test func appHasPhotoLibraryUsageDescription() {
    #expect((Bundle.main.object(forInfoDictionaryKey: "NSPhotoLibraryUsageDescription") as? String)?.isEmpty == false)
}

/// 写真へのアクセスの許可を求める時の説明文の日本語訳 (Poppo/InfoPlist.xcstrings) が、ビルドしたアプリに入っていること
@Test func photoLibraryUsageDescriptionHasJapaneseLocalization() {
    #expect(
        Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "ja")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }?["NSPhotoLibraryUsageDescription"]
            == "直近のスクリーンショットを並べて、翻訳する 1 枚を選べるようにします。スクリーンショットはこの端末の中でだけ読み取ります。"
    )
}

/// キーボード拡張の String Catalog (PoppoKeyboard/Localizable.xcstrings) の日本語訳が、アプリに埋め込まれた拡張に入っていること
@Test func keyboardExtensionBundleContainsJapaneseLocalization() throws {
    #expect(
        try #require(
            Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("PoppoKeyboard.appex")) }
        ).localizations.contains("ja")
    )
}
