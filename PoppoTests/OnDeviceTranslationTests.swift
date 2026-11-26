import Foundation
import Testing
import Translation
@testable import Poppo

/// テスト用に、Translation が返す訳文 1 つを作る。対応を取るのに使う clientIdentifier と訳文だけを変える
private func translationResponse(clientIdentifier: String?, targetText: String) -> TranslationSession.Response {
    TranslationSession.Response(
        sourceLanguage: Locale.Language(identifier: "en"),
        targetLanguage: Locale.Language(identifier: "ja"),
        sourceText: "source",
        targetText: targetText,
        clientIdentifier: clientIdentifier
    )
}

/// 訳す先の言語は、利用者が端末で選んだ言語の並びの先頭にすること (アプリが対応していない言語でも、その言語にする)
@Test func userLanguageIsFirstPreferredLanguage() {
    #expect(userLanguage(preferredLanguages: ["ko-KR", "en-US"]).languageCode == Locale.LanguageCode("ko"))
    #expect(userLanguage(preferredLanguages: ["ja-JP"]).languageCode == Locale.LanguageCode("ja"))
}

/// 利用者が選んだ言語の並びが空の時は、訳す先の言語を、アプリが動いている言語にすること
@Test func userLanguageFallsBackToLanguageTheAppRunsIn() {
    #expect(userLanguage(preferredLanguages: []) == Locale.current.language)
}

/// 端末の言語の文と外国語の文が混ざった並びでは、外国語の文だけを、元の順のまま、判定した原文の言語と一緒に訳す処理へ渡し、
/// 返ってきた訳文を元の位置に戻して、端末の言語の文はそのまま返すこと。
/// 偽物の訳す処理は、受け取った原文の言語・受け取った順の位置・文をつないだ文字列を返す
@Test func translateForeignTextsTranslatesOnlyForeignTextsAndKeepsPositions() async throws {
    #expect(
        try await translateForeignTexts(
            texts: [
                "Can you review my pull request this afternoon?",
                "今日は午後から会議があるので、少し遅れます",
                "Sure, I will take a look after lunch",
            ],
            targetLanguage: Locale.Language(identifier: "ja"),
            translate: { foreignTexts, sourceLanguage in
                foreignTexts.enumerated().map { "\(sourceLanguage.languageCode?.identifier ?? "") \($0): \($1)" }
            }
        ) == [
            "en 0: Can you review my pull request this afternoon?",
            "今日は午後から会議があるので、少し遅れます",
            "en 1: Sure, I will take a look after lunch",
        ]
    )
}

/// 訳す先に端末の言語と違う言語 (英語) を選んだ時は、選んだ言語で書かれた文を訳さずに残し、ほかの言語 (日本語) の文だけを訳すこと
@Test func translateForeignTextsKeepsTextsInSelectedTargetLanguage() async throws {
    #expect(
        try await translateForeignTexts(
            texts: [
                "今日は午後から会議があるので、少し遅れます",
                "Can you review my pull request this afternoon?",
            ],
            targetLanguage: Locale.Language(identifier: "en"),
            translate: { foreignTexts, sourceLanguage in
                foreignTexts.map { "\(sourceLanguage.languageCode?.identifier ?? ""): \($0)" }
            }
        ) == [
            "ja: 今日は午後から会議があるので、少し遅れます",
            "Can you review my pull request this afternoon?",
        ]
    )
}

/// 訳す処理が投げた失敗 (言語が入っていない等) は、そのまま呼び出し元へ伝えること
@Test func translateForeignTextsRethrowsErrorFromTranslate() async {
    await #expect(throws: ChatReadingError.incompleteTranslation) {
        _ = try await translateForeignTexts(
            texts: ["Can you review my pull request this afternoon?"],
            targetLanguage: Locale.Language(identifier: "ja"),
            translate: { _, _ in throw ChatReadingError.incompleteTranslation }
        )
    }
}

/// Translation に渡す依頼は、文を渡した順に並べ、文の位置 (0 始まり) を文字列にした clientIdentifier を持つこと
@Test func translationRequestsCarryPositionAsClientIdentifier() {
    #expect(translationRequests(texts: ["Hello", "Goodbye"]).map(\.sourceText) == ["Hello", "Goodbye"])
    #expect(translationRequests(texts: ["Hello", "Goodbye"]).map(\.clientIdentifier) == ["0", "1"])
}

/// 利用者の言語 (日本語) で書かれた文は「その言語で書かれている」と判定し、ほかの言語 (英語) の文と空の文は判定しないこと。
/// 言語の判定は NaturalLanguage の実物を通す
@Test func isWrittenTellsWhetherTextIsInTheLanguage() {
    #expect(isWritten(text: "今日は午後から会議があるので、少し遅れます", language: Locale.Language(identifier: "ja")))
    #expect(!isWritten(text: "Can you review my pull request this afternoon?", language: Locale.Language(identifier: "ja")))
    #expect(isWritten(text: "Can you review my pull request this afternoon?", language: Locale.Language(identifier: "en")))
    #expect(!isWritten(text: "", language: Locale.Language(identifier: "ja")))
}

/// 訳す文 (英語) から原文の言語を判定して返すこと。判定した言語が訳す先と同じ時と、文が無い時は、訳せないことを表す nil を返すこと
@Test func detectSourceLanguageReturnsLanguageOfTextsUnlessItIsTargetLanguage() {
    #expect(
        detectSourceLanguage(
            texts: ["Can you review my pull request this afternoon?", "Sure, I will take a look after lunch"],
            targetLanguage: Locale.Language(identifier: "ja")
        )?.languageCode == Locale.LanguageCode("en")
    )
    #expect(
        detectSourceLanguage(
            texts: ["今日は午後から会議があるので、少し遅れます"],
            targetLanguage: Locale.Language(identifier: "ja")
        ) == nil
    )
    #expect(detectSourceLanguage(texts: [], targetLanguage: Locale.Language(identifier: "ja")) == nil)
}

/// 訳した文を、元の並びの中の訳した位置にだけ戻し、訳さなかった位置 (利用者の言語で書かれた文) は元の文のまま返すこと
@Test func replacingTextsPutsTranslationsBackAtTheirPositions() {
    #expect(
        replacingTexts(texts: ["Hello", "こんにちは", "Goodbye"], indices: [0, 2], replacements: ["やあ", "さようなら"])
            == ["やあ", "こんにちは", "さようなら"]
    )
}

/// 訳す位置が無い時は、元の並びをそのまま返すこと
@Test func replacingTextsWithoutPositionsKeepsTexts() {
    #expect(replacingTexts(texts: ["こんにちは", "ありがとう"], indices: [], replacements: []) == ["こんにちは", "ありがとう"])
}

/// どの文も利用者の言語で書かれている時 (訳す文が無い時) は、Translation を呼ばずに「翻訳できない言語」の失敗にすること
@Test func translateOnDeviceThrowsUntranslatableLanguageWhenEveryTextIsInTargetLanguage() async {
    await #expect(throws: ChatReadingError.untranslatableLanguage) {
        _ = try await translateOnDevice(
            texts: ["今日は午後から会議があるので、少し遅れます", "わかりました。資料を先に送っておきます"],
            targetLanguage: Locale.Language(identifier: "ja")
        )
    }
}

/// 訳す言語が端末に入っている時は、失敗にせず翻訳へ進めること
@Test func installedLanguagesAreAccepted() throws {
    try requireInstalledLanguages(
        status: .installed,
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ja")
    )
}

/// Translation が対応しているが言語が入っていない時は、その言語の組を持った「言語が入っていない」の失敗にすること
/// (画面が、その言語の組でダウンロードを促すために使う)
@Test func supportedButNotInstalledLanguagesThrowLanguageNotInstalled() {
    #expect(
        throws: ChatReadingError.languageNotInstalled(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ja")
        )
    ) {
        try requireInstalledLanguages(
            status: .supported,
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ja")
        )
    }
}

/// Translation が対応していない言語の組の時は、言語のダウンロードを促さず、「翻訳できない言語」の失敗にすること
@Test func unsupportedLanguagesThrowUntranslatableLanguage() {
    #expect(throws: ChatReadingError.untranslatableLanguage) {
        try requireInstalledLanguages(
            status: .unsupported,
            source: Locale.Language(identifier: "ja"),
            target: Locale.Language(identifier: "ja")
        )
    }
}

/// 訳文が渡した文と違う順で返ってきても、渡した文の順に並べ直すこと
@Test func targetTextsAreOrderedByClientIdentifier() throws {
    #expect(
        try orderedTargetTexts(
            responses: [
                translationResponse(clientIdentifier: "2", targetText: "三"),
                translationResponse(clientIdentifier: "0", targetText: "一"),
                translationResponse(clientIdentifier: "1", targetText: "二"),
            ],
            count: 3
        ) == ["一", "二", "三"]
    )
}

/// どれかの位置の訳文が返ってこなかった時は、残りだけを返さず、「訳文が足りない」の失敗にすること
@Test func missingTargetTextThrowsIncompleteTranslation() {
    #expect(throws: ChatReadingError.incompleteTranslation) {
        try orderedTargetTexts(
            responses: [
                translationResponse(clientIdentifier: "0", targetText: "一"),
                translationResponse(clientIdentifier: "2", targetText: "三"),
            ],
            count: 3
        )
    }
}

/// clientIdentifier の無い訳文は、どの文の訳か分からないため使わず、「訳文が足りない」の失敗にすること
@Test func targetTextWithoutClientIdentifierThrowsIncompleteTranslation() {
    #expect(throws: ChatReadingError.incompleteTranslation) {
        try orderedTargetTexts(responses: [translationResponse(clientIdentifier: nil, targetText: "一")], count: 1)
    }
}

/// 訳す文が無い時は、空の並びを返すこと
@Test func noTextsGiveNoTargetTexts() throws {
    #expect(try orderedTargetTexts(responses: [], count: 0).isEmpty)
}
