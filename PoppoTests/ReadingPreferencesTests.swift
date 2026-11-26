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

/// 返信の文を作る処理には、保存してある相手との関係を渡し、その処理が返した文を返すこと。何も選んでいない時は未選択 (nil) を渡すこと
@Test func generateReplyTextsForSelectedRelationshipPassesSavedRelationship() async throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    var receivedRelationships: [ChatPartnerRelationship?] = []
    let generate: ([ExtractedMessage], ChatPartnerRelationship?) async throws -> [String] = { messages, chatPartnerRelationship in
        receivedRelationships.append(chatPartnerRelationship)
        return messages.map { "返信: " + $0.text }
    }

    #expect(
        try await generateReplyTextsForSelectedRelationship(
            messages: [ExtractedMessage(text: "Are you free?", isFromUser: false)],
            userDefaults: userDefaults,
            generate: generate
        ) == ["返信: Are you free?"]
    )
    save(selectedChatPartnerRelationship: .superiorOrClient, userDefaults: userDefaults)
    _ = try await generateReplyTextsForSelectedRelationship(messages: [], userDefaults: userDefaults, generate: generate)

    #expect(receivedRelationships == [nil, .superiorOrClient])
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 画面を開いただけ (欄が既定の値 = 端末の言語と未選択のまま) では何も保存しないため、後で端末の言語を変えると訳す先も変わること
@Test func saveChangedReadingPreferencesSavesNothingWhenOpenedWithDefaults() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))

    saveChangedReadingPreferences(
        targetLanguageIdentifier: Locale.Language(identifier: "ja-JP").maximalIdentifier,
        chatPartnerRelationship: nil,
        userDefaults: userDefaults,
        preferredLanguages: ["ja-JP"]
    )

    #expect(userDefaults.object(forKey: selectedTargetLanguageUserDefaultsKey) == nil)
    #expect(userDefaults.object(forKey: selectedChatPartnerRelationshipUserDefaultsKey) == nil)
    #expect(selectedTargetLanguage(userDefaults: userDefaults, preferredLanguages: ["ko-KR"]).languageCode == Locale.LanguageCode("ko"))
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 欄で既定と違う言語と関係を選ぶと、両方を保存し、端末の言語を変えても選んだ言語と関係のままであること
@Test func saveChangedReadingPreferencesSavesChosenLanguageAndRelationship() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))

    saveChangedReadingPreferences(
        targetLanguageIdentifier: Locale.Language(identifier: "fr").maximalIdentifier,
        chatPartnerRelationship: .stranger,
        userDefaults: userDefaults,
        preferredLanguages: ["ja-JP"]
    )

    #expect(selectedTargetLanguage(userDefaults: userDefaults, preferredLanguages: ["ko-KR"]).languageCode == Locale.LanguageCode("fr"))
    #expect(selectedChatPartnerRelationship(userDefaults: userDefaults) == .stranger)
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 関係を選んだ後に欄で未選択に戻すと、保存してある関係を消すこと
@Test func saveChangedReadingPreferencesClearsRelationshipWhenReturnedToNotSelected() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    save(selectedChatPartnerRelationship: .coworker, userDefaults: userDefaults)

    saveChangedReadingPreferences(
        targetLanguageIdentifier: Locale.Language(identifier: "ja-JP").maximalIdentifier,
        chatPartnerRelationship: nil,
        userDefaults: userDefaults,
        preferredLanguages: ["ja-JP"]
    )

    #expect(userDefaults.object(forKey: selectedChatPartnerRelationshipUserDefaultsKey) == nil)
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 保存してある訳す先の言語が空文字の時は、何も選んでいない時と同じく端末の言語になること
@Test func selectedTargetLanguageIsPreferredLanguageWhenSavedValueIsEmpty() throws {
    let suiteName = makeSuiteName()
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.set("", forKey: selectedTargetLanguageUserDefaultsKey)

    #expect(selectedTargetLanguage(userDefaults: userDefaults, preferredLanguages: ["ko-KR"]).languageCode == Locale.LanguageCode("ko"))
    userDefaults.removePersistentDomain(forName: suiteName)
}

/// 読み取りのタスクの id は、言語だけ・関係だけ・読み直しを頼んだ回数だけが変わった時のどれでも変わり、どれも変わらなければ同じであること
/// (id が変わった時だけ読み直すため)
@Test func chatReadingTaskIDChangesWhenAnyOfLanguageRelationshipOrReadRequestChanges() {
    let base = chatReadingTaskID(targetLanguageIdentifier: "ja-Jpan-JP", chatPartnerRelationship: nil, readRequestCount: 0)

    #expect(chatReadingTaskID(targetLanguageIdentifier: "ja-Jpan-JP", chatPartnerRelationship: nil, readRequestCount: 0) == base)
    #expect(chatReadingTaskID(targetLanguageIdentifier: "en-Latn-US", chatPartnerRelationship: nil, readRequestCount: 0) != base)
    #expect(chatReadingTaskID(targetLanguageIdentifier: "ja-Jpan-JP", chatPartnerRelationship: .coworker, readRequestCount: 0) != base)
    #expect(chatReadingTaskID(targetLanguageIdentifier: "ja-Jpan-JP", chatPartnerRelationship: nil, readRequestCount: 1) != base)
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

/// 訳す先として選べる言語の一覧は、渡した順に関係なく、言語の名前の順に並ぶこと
@Test func targetLanguageOptionsAreSortedByLanguageName() {
    let names = targetLanguageOptions(
        supportedLanguages: [
            Locale.Language(identifier: "ko"), Locale.Language(identifier: "fr"), Locale.Language(identifier: "de"),
        ],
        selectedLanguage: Locale.Language(identifier: "es")
    ).map { languageName(language: $0) }

    #expect(names.count == 4)
    #expect(zip(names, names.dropFirst()).allSatisfy { $0.localizedStandardCompare($1) == .orderedAscending })
}

/// 端末で訳せる言語をまだ読み出していない時 (一覧が空) は、今選んでいる言語だけを並べること
@Test func targetLanguageOptionsContainOnlySelectedLanguageBeforeSupportedLanguagesAreLoaded() {
    #expect(
        targetLanguageOptions(supportedLanguages: [], selectedLanguage: Locale.Language(identifier: "ja-JP")).map(\.maximalIdentifier)
            == ["ja-Jpan-JP"]
    )
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
