import Foundation
import Testing

@testable import Poppo

/// テストごとに別の UserDefaults の suite の名前を作って返す。アプリの UserDefaults (standard) と、ほかのテストの値を混ぜないため
private func makeSuiteName() -> String {
    "ReadingPreferencesTests-\(UUID().uuidString)"
}

/// 訳す先の言語を選んでいない時は、端末の言語 (利用者が端末で選んだ言語の並びの先頭) が選ばれていること (選べるようにする前の動きを変えない)
@Test func selectedTargetLanguageIsPreferredLanguageWhenNothingIsSelected() throws {
    let suiteName = makeSuiteName()

    #expect(
        selectedTargetLanguage(userDefaults: try #require(UserDefaults(suiteName: suiteName)), preferredLanguages: ["ko-KR", "en-US"])
            .languageCode == Locale.LanguageCode("ko")
    )
    try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
}

/// 選んだ言語は、同じ保存先を読み直しても (アプリを開き直した後も) 選ばれたままで、端末の言語より優先されること。
/// 選び直すと、後から選んだ言語だけが選ばれていること
@Test func selectedTargetLanguageIsKeptAfterSavingAndReplacedBySavingAgain() throws {
    let suiteName = makeSuiteName()
    save(selectedTargetLanguage: Locale.Language(identifier: "es"), userDefaults: try #require(UserDefaults(suiteName: suiteName)))

    #expect(
        selectedTargetLanguage(userDefaults: try #require(UserDefaults(suiteName: suiteName)), preferredLanguages: ["ja-JP"])
            .languageCode == Locale.LanguageCode("es")
    )

    save(selectedTargetLanguage: Locale.Language(identifier: "zh-Hant"), userDefaults: try #require(UserDefaults(suiteName: suiteName)))

    #expect(
        selectedTargetLanguage(userDefaults: try #require(UserDefaults(suiteName: suiteName)), preferredLanguages: ["ja-JP"])
            .maximalIdentifier == Locale.Language(identifier: "zh-Hant").maximalIdentifier
    )
    try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
}

/// 読み取りの翻訳は、保存してある訳す先の言語を渡して訳す処理を呼び、その処理が返した訳文を返すこと。
/// 何も選んでいない時は、端末の言語を渡すこと
@Test func translateIntoSelectedLanguageCallsTranslateWithSelectedLanguage() async throws {
    let suiteName = makeSuiteName()
    var receivedTargetLanguages: [Locale.Language] = []
    let translate: ([String], Locale.Language) async throws -> [String] = { texts, targetLanguage in
        receivedTargetLanguages.append(targetLanguage)
        return texts.map { "訳: " + $0 }
    }

    #expect(
        try await translateIntoSelectedLanguage(
            texts: ["Hello"],
            userDefaults: try #require(UserDefaults(suiteName: suiteName)),
            preferredLanguages: ["ja-JP"],
            translate: translate
        ) == ["訳: Hello"]
    )
    save(selectedTargetLanguage: Locale.Language(identifier: "fr"), userDefaults: try #require(UserDefaults(suiteName: suiteName)))
    _ = try await translateIntoSelectedLanguage(
        texts: ["Hello"],
        userDefaults: try #require(UserDefaults(suiteName: suiteName)),
        preferredLanguages: ["ja-JP"],
        translate: translate
    )

    #expect(receivedTargetLanguages.map(\.languageCode) == [Locale.LanguageCode("ja"), Locale.LanguageCode("fr")])
    try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
}

/// 選べる相手との関係は、友人・家族、仕事の仲間、目上・取引先、初めての相手の 4 つで、保存に書く生の値がこの 4 つの文字列であること
/// (生の値を変えると、保存してある選択を読めなくなる)
@Test func chatPartnerRelationshipsAreFriendOrFamilyCoworkerSuperiorOrClientAndStranger() {
    #expect(ChatPartnerRelationship.allCases.map(\.rawValue) == ["friendOrFamily", "coworker", "superiorOrClient", "stranger"])
}

/// 相手との関係を選んでいない時は、未選択 (nil) であること
@Test func selectedChatPartnerRelationshipIsNilWhenNothingIsSelected() throws {
    #expect(selectedChatPartnerRelationship(userDefaults: try #require(UserDefaults(suiteName: makeSuiteName()))) == nil)
}

/// 選んだ関係は、同じ保存先を読み直しても (アプリを開き直した後も) 選ばれたままであること。選べる関係のそれぞれで確かめる
@Test(arguments: ChatPartnerRelationship.allCases)
func selectedChatPartnerRelationshipIsKeptAfterSaving(chatPartnerRelationship: ChatPartnerRelationship) throws {
    let suiteName = makeSuiteName()
    save(selectedChatPartnerRelationship: chatPartnerRelationship, userDefaults: try #require(UserDefaults(suiteName: suiteName)))

    #expect(selectedChatPartnerRelationship(userDefaults: try #require(UserDefaults(suiteName: suiteName))) == chatPartnerRelationship)
    try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
}

/// 関係を選んだ後に未選択を選び直すと、未選択に戻ること
@Test func selectedChatPartnerRelationshipReturnsToNilAfterSavingNil() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    save(selectedChatPartnerRelationship: .coworker, userDefaults: userDefaults)
    save(selectedChatPartnerRelationship: nil, userDefaults: userDefaults)

    #expect(selectedChatPartnerRelationship(userDefaults: userDefaults) == nil)
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 保存してある値が選べる関係の一覧に無い時 (空文字・知らない名前・文字列でない値) は、未選択 (nil) であること
@Test func selectedChatPartnerRelationshipIsNilWhenSavedValueIsNotSelectable() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))

    userDefaults.set("", forKey: selectedChatPartnerRelationshipUserDefaultsKey)
    #expect(selectedChatPartnerRelationship(userDefaults: userDefaults) == nil)
    userDefaults.set("family", forKey: selectedChatPartnerRelationshipUserDefaultsKey)
    #expect(selectedChatPartnerRelationship(userDefaults: userDefaults) == nil)
    userDefaults.set(["coworker"], forKey: selectedChatPartnerRelationshipUserDefaultsKey)
    #expect(selectedChatPartnerRelationship(userDefaults: userDefaults) == nil)
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 訳す先として選べる言語の一覧は、端末で訳せる言語に、今選んでいる言語を (一覧に無くても) 1 つだけ含めること
@Test func targetLanguageOptionsIncludeSelectedLanguageOnce() {
    #expect(
        Set(
            targetLanguageOptions(
                supportedLanguages: [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "ja-JP")],
                selectedLanguage: Locale.Language(identifier: "ko-KR")
            ).map(\.maximalIdentifier)
        ) == Set(["en-Latn-US", "ja-Jpan-JP", "ko-Kore-KR"])
    )
    #expect(
        targetLanguageOptions(
            supportedLanguages: [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "ja")],
            selectedLanguage: Locale.Language(identifier: "ja-JP")
        ).map(\.maximalIdentifier).sorted() == ["en-Latn-US", "ja-Jpan-JP"]
    )
}
