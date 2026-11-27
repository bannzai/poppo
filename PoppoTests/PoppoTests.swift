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
    // 翻訳ファイル (InfoPlist.strings) の値で補われた結果ではなく、Info.plist そのものに入っていることを見るため、infoDictionary を読む
    #expect((Bundle.main.infoDictionary?["NSPhotoLibraryUsageDescription"] as? String)?.isEmpty == false)
}

/// 写真へのアクセスの許可を求める時の説明文の日本語訳 (Poppo/InfoPlist.xcstrings) が、ビルドしたアプリに入っていること
@Test func photoLibraryUsageDescriptionHasJapaneseLocalization() {
    #expect(
        Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "ja")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }?["NSPhotoLibraryUsageDescription"]
            == "直近のスクリーンショットか写真を並べて、翻訳する 1 枚を選べるようにします。画像はこの端末の中でだけ読み取ります。"
    )
}

/// 画面の取り込みの許可を求める時にシステムが出す説明文が、ビルドしたアプリの Info.plist に入っていること
/// (Apple の文書: 「In the Info pane of the Xcode target editor, add a NSScreenCaptureUsageDescription key with a description
/// of why your app requires screen recording access.」 https://developer.apple.com/documentation/screencapturekit )
@Test func appHasScreenCaptureUsageDescription() {
    #expect((Bundle.main.infoDictionary?["NSScreenCaptureUsageDescription"] as? String)?.isEmpty == false)
}

/// 画面の取り込みの許可を求める時の説明文の日本語訳 (Poppo/InfoPlist.xcstrings) が、ビルドしたアプリに入っていること
@Test func screenCaptureUsageDescriptionHasJapaneseLocalization() {
    #expect(
        Bundle.main.url(forResource: "InfoPlist", withExtension: "strings", subdirectory: nil, localization: "ja")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: String] }?["NSScreenCaptureUsageDescription"]
            == "画面のチャットを読み取って、翻訳と返信案をキーボードに出します。画面はこの端末の中でだけ読み取ります。"
    )
}

/// 他のアプリへ切り替えた後も取り込みを続けるための宣言が、ビルドしたアプリの Info.plist に入っていること
/// (Apple のサンプル: 「screen-capture in UIBackgroundModes, so the stream survives backgrounding for full-display capture.」
/// https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios )
@Test func appDeclaresScreenCaptureBackgroundMode() {
    #expect(Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] == ["screen-capture"])
}

/// キーボード拡張が Full Access を求めていないこと (App Review Guidelines 4.4.1:
/// 「Remain functional without full network access and without requiring full access」)
@Test func keyboardExtensionDoesNotRequestOpenAccess() throws {
    #expect(
        ((try #require(
            Bundle.main.builtInPlugInsURL.flatMap { Bundle(url: $0.appendingPathComponent("PoppoKeyboard.appex")) }
        ).infoDictionary?["NSExtension"] as? [String: Any])?["NSExtensionAttributes"] as? [String: Any])?["RequestsOpenAccess"] as? Bool
            == false
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
