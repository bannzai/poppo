import CoreGraphics
import Foundation
import Testing

@testable import Poppo

/// テストごとに別の、まだ無い記録のファイルの場所を返す。ほかのテストと本体アプリの記録を混ぜないため
private func makeChoicesFileURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotReadingChoiceTests-\(UUID().uuidString).json")
}

/// 文字の読み取りの偽物が返す、チャットの画面の行。ステータスバーの時刻と電波、上部のチャットの名前 (chatTitle。nil は上部に文字が無い画面)、
/// 発言ごとの見出し行 (headers) と本文を、見本の画像 (PoppoTests/ChatScreenSamples/) と同じ並びで置く
private func chatScreenLines(chatTitle: String?, headers: [String]) -> [RecognizedTextLine] {
    [
        RecognizedTextLine(text: "9:41", boundingBox: CGRect(x: 0.08, y: 0.025, width: 0.1, height: 0.02)),
        RecognizedTextLine(text: "5G", boundingBox: CGRect(x: 0.86, y: 0.025, width: 0.06, height: 0.02)),
    ]
        + (chatTitle.map { [RecognizedTextLine(text: $0, boundingBox: CGRect(x: 0.33, y: 0.078, width: 0.34, height: 0.02))] } ?? [])
        + headers.enumerated().flatMap { index, header in
            [
                RecognizedTextLine(text: header, boundingBox: CGRect(x: 0.16, y: 0.2 + 0.1 * CGFloat(index), width: 0.5, height: 0.02)),
                RecognizedTextLine(text: "Message \(index)", boundingBox: CGRect(x: 0.16, y: 0.23 + 0.1 * CGFloat(index), width: 0.5, height: 0.02)),
            ]
        }
}

/// テストで比べる過去の記録を作る。言語と関係は、どの記録が選ばれたかを見分けるために記録ごとに変える
private func pastChoice(
    chatTitle: String?,
    speakerNames: [String],
    relationship: ChatPartnerRelationship?,
    readAt: Date = Date(timeIntervalSinceReferenceDate: 800_000_000)
) -> ScreenshotReadingChoice {
    ScreenshotReadingChoice(
        id: UUID(),
        readAt: readAt,
        chatTitleReadFromScreen: chatTitle,
        speakerNames: speakerNames,
        targetLanguageIdentifier: "es-Latn-ES",
        chatPartnerRelationship: relationship
    )
}

/// 画面の上部の段から、チャットの名前を読むこと。ステータスバーの時刻と電波、戻るボタンの「‹」はチャットの名前にしないこと
@Test func chatTitleIsReadFromNavigationBarExcludingStatusBarAndBackButton() {
    #expect(
        chatTitleReadFromScreen(
            lines: chatScreenLines(chatTitle: "# design-review", headers: [])
                + [RecognizedTextLine(text: "‹", boundingBox: CGRect(x: 0.03, y: 0.078, width: 0.03, height: 0.02))]
        ) == "# design-review"
    )
}

/// 上部の段に文字が無く、ステータスバーにだけ文字がある画面では、チャットの名前を読まない (nil) こと。
/// ステータスバーの文字を名前にすると、どの画面も同じチャットになってしまうため
@Test func chatTitleIsNilWhenOnlyStatusBarHasText() {
    #expect(chatTitleReadFromScreen(lines: chatScreenLines(chatTitle: nil, headers: ["Mira Solberg 10:42 AM"])) == nil)
}

/// 上部の段の境目: 行の上下の中心がステータスバーの範囲 (6% より上) の行は名前にせず、すぐ下の行は名前にすること。
/// 発言の並ぶ範囲 (上端 12%) から始まる行は名前にせず、その直前から始まる行は名前にすること
@Test func chatTitleBoundariesAreStatusBarAndChatArea() {
    let line = { (text: String, minY: CGFloat) in RecognizedTextLine(text: text, boundingBox: CGRect(x: 0.3, y: minY, width: 0.4, height: 0.02)) }

    // 高さ 0.02 の行の上下の中心は minY + 0.01
    #expect(chatTitleReadFromScreen(lines: [line("Carrier name", 0.049)]) == nil)
    #expect(chatTitleReadFromScreen(lines: [line("Harbor Books", 0.051)]) == "Harbor Books")
    #expect(chatTitleReadFromScreen(lines: [line("First message", 0.12)]) == nil)
    #expect(chatTitleReadFromScreen(lines: [line("Harbor Books", 0.119)]) == "Harbor Books")
}

/// 上部の段の時刻だけの行と、文字と数字の無い行 (「‹」だけ) は、チャットの名前にしないこと
@Test func chatTitleIgnoresTimeOnlyAndSymbolOnlyLines() {
    #expect(
        chatTitleReadFromScreen(lines: [RecognizedTextLine(text: "10:42 AM", boundingBox: CGRect(x: 0.3, y: 0.078, width: 0.4, height: 0.02))])
            == nil
    )
    #expect(
        chatTitleReadFromScreen(lines: [RecognizedTextLine(text: "‹ ‹", boundingBox: CGRect(x: 0.3, y: 0.078, width: 0.4, height: 0.02))])
            == nil
    )
}

/// 見出し行 (名前と時刻) から発言した人の名前を、画面の上から下の順に読み、同じ人 (空白と大文字小文字の違いを含む) は 1 つにまとめること
@Test func speakerNamesAreReadFromHeaderLinesWithoutDuplicates() {
    #expect(
        speakerNames(
            messages: [
                ExtractedMessage(text: "Mira Solberg 10:42 AM\nCan someone review?", isFromUser: false),
                ExtractedMessage(text: "水瀬 あおい 14:05\n確認をお願いします。", isFromUser: false),
                ExtractedMessage(text: "MiraSolberg 10:47 AM\nThanks!", isFromUser: false),
                ExtractedMessage(text: "luna_verde hoy a las 18:05\n¿Alguien?", isFromUser: false),
            ]
        ) == ["Mira Solberg", "水瀬 あおい", "luna_verde hoy a las"]
    )
}

/// 見出し行の無い発言 (吹き出しのチャット。先頭の行が本文) と、時刻だけの行からは、名前を読まないこと
@Test func speakerNamesIgnoreMessagesWithoutHeaderLine() {
    #expect(
        speakerNames(
            messages: [
                ExtractedMessage(text: "Your order has arrived.", isFromUser: false),
                ExtractedMessage(text: "10:42\nThanks", isFromUser: true),
            ]
        ).isEmpty
    )
}

/// 手がかりの文字は、空白・記号・大文字小文字の違いを無視して比べられる形になること
@Test func comparableClueTextIgnoresSpacesSymbolsAndCase() {
    #expect(comparableClueText(text: "‹ # Design-Review") == comparableClueText(text: "#design review"))
    #expect(comparableClueText(text: "水瀬 あおい") == comparableClueText(text: "水瀬あおい"))
    #expect(comparableClueText(text: "# design-review") != comparableClueText(text: "# design"))
}

/// チャットの名前が一致する時: 発言した人の名前が違っても、その過去の記録を返すこと
@Test func mostSimilarChoiceMatchesSameChatTitle() {
    let sameChat = pastChoice(chatTitle: "# design-review", speakerNames: ["Mira Solberg"], relationship: .coworker)

    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "#design review",
            speakerNames: ["Priya Nakamoto"],
            pastChoices: [pastChoice(chatTitle: "Harbor Books", speakerNames: [], relationship: .stranger), sameChat]
        ) == sameChat
    )
}

/// チャットの名前が一致しない時: 発言した人が同じでも、別のチャットとして記録を返さない (nil) こと
@Test func mostSimilarChoiceDoesNotMatchDifferentChatTitleEvenWithSameSpeakers() {
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "# random",
            speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
            pastChoices: [pastChoice(chatTitle: "# design-review", speakerNames: ["Mira Solberg", "Tobias Lindqvist"], relationship: .coworker)]
        ) == nil
    )
}

/// チャットの名前を読めず、発言した人の名前が一部だけ一致する時: 半分以上が同じなら記録を返し、半分より少なければ返さないこと
@Test func mostSimilarChoiceMatchesPartialSpeakersOnlyWhenHalfOrMoreOverlap() {
    let pastGroup = pastChoice(chatTitle: nil, speakerNames: ["Mira Solberg", "Tobias Lindqvist"], relationship: .coworker)

    // 3 人のうち 2 人が同じ (2/3)
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: nil,
            speakerNames: ["Mira Solberg", "Tobias Lindqvist", "Priya Nakamoto"],
            pastChoices: [pastGroup]
        ) == pastGroup
    )
    // 2 人のうち 1 人が同じ (1/2。境目)
    #expect(
        mostSimilarScreenshotReadingChoice(chatTitleReadFromScreen: nil, speakerNames: ["Mira Solberg"], pastChoices: [pastGroup])
            == pastGroup
    )
    // 3 人のうち 1 人だけが同じ (1/3)
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: nil,
            speakerNames: ["Mira Solberg", "Priya Nakamoto"],
            pastChoices: [pastGroup]
        ) == nil
    )
    // 片方だけでチャットの名前を読めた時も、発言した人の名前で比べる
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "# design-review",
            speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
            pastChoices: [pastGroup]
        ) == pastGroup
    )
}

/// 手がかりが何も無い読み取りどうし (チャットの名前も発言した人の名前も読めない) は、似ているとしないこと
@Test func mostSimilarChoiceDoesNotMatchWhenNoClueIsRead() {
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: nil,
            speakerNames: [],
            pastChoices: [pastChoice(chatTitle: nil, speakerNames: [], relationship: .coworker)]
        ) == nil
    )
}

/// 似ている記録が複数ある時: チャットの名前が同じ記録を、発言した人の名前だけが同じ記録より先に選び、
/// どちらも同じくらい似ている時は新しい記録を選ぶこと
@Test func mostSimilarChoicePrefersSameTitleThenNewest() {
    let newer = pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .friendOrFamily, readAt: Date(timeIntervalSinceReferenceDate: 800_000_100))

    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "# design-review",
            speakerNames: ["Mira Solberg"],
            pastChoices: [
                pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker, readAt: Date(timeIntervalSinceReferenceDate: 800_000_000)),
                // 発言した人の名前だけが同じで、最も新しい記録
                pastChoice(chatTitle: nil, speakerNames: ["Mira Solberg"], relationship: .stranger, readAt: Date(timeIntervalSinceReferenceDate: 800_000_200)),
                newer,
            ]
        ) == newer
    )
}

/// 残す記録: 読んでから 14 日を過ぎた記録を除き (ちょうど 14 日は除き、その 1 秒前は残す)、新しい順に並べること
@Test func retainedChoicesDropRecordsOlderThan14Days() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let fourteenDays: TimeInterval = 14 * 24 * 60 * 60
    let justKept = pastChoice(chatTitle: "B", speakerNames: [], relationship: nil, readAt: now.addingTimeInterval(-fourteenDays + 1))
    let newest = pastChoice(chatTitle: "C", speakerNames: [], relationship: nil, readAt: now)

    #expect(
        retainedScreenshotReadingChoices(
            choices: [justKept, pastChoice(chatTitle: "A", speakerNames: [], relationship: nil, readAt: now.addingTimeInterval(-fourteenDays)), newest],
            now: now
        ) == [newest, justKept]
    )
}

/// 残す記録: 200 件までは全部残し、201 件の時は最も古い 1 件を除くこと
@Test func retainedChoicesKeepAtMost200Newest() {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let choices = (0..<201).map { pastChoice(chatTitle: "Chat \($0)", speakerNames: [], relationship: nil, readAt: now.addingTimeInterval(-Double($0))) }

    #expect(retainedScreenshotReadingChoices(choices: Array(choices.prefix(200)), now: now).count == 200)
    #expect(retainedScreenshotReadingChoices(choices: choices, now: now) == Array(choices.prefix(200)))
}

/// 記録が無い時と、記録として読めない中身の時は、空の記録として読むこと
@Test func loadChoicesIsEmptyWhenFileIsMissingOrBroken() throws {
    let fileURL = makeChoicesFileURL()
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: Date()).isEmpty)

    try Data("not json".utf8).write(to: fileURL)
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: Date()).isEmpty)
}

/// 相手 A で言語と関係を選び、相手 B で別のものを選んだ後に、A のスクリーンショットを読むと、A で選んだものが既定になること。
/// 直前に選んだもの (B の選択) ではないことで、相手ごとに覚えていることを確かめる
@Test func addChoiceUsesChoiceOfSameChatNotLastChoice() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: ["Mira Solberg 10:42 AM"]),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "Harbor Books", headers: ["Harbor Books 9:12 AM"]),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .superiorOrClient,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    let choiceForA = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: ["Tobias Lindqvist 11:02 AM"]),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .superiorOrClient,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(120),
        fileURL: fileURL
    )

    #expect(choiceForA.targetLanguageIdentifier == "en-Latn-US")
    #expect(choiceForA.chatPartnerRelationship == .coworker)
    #expect(choiceForA.chatTitleReadFromScreen == "# design-review")
    #expect(choiceForA.speakerNames == ["Tobias Lindqvist"])
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: now.addingTimeInterval(120)).count == 3)
}

/// 前に読んだことの無い相手のスクリーンショットでは、今選ばれている (直前に選んだ) 言語と関係が既定になり、そのまま記録されること
@Test func addChoiceUsesCurrentChoiceForUnknownChat() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "Harbor Books", headers: []),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .stranger,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(choice.targetLanguageIdentifier == "fr-Latn-FR")
    #expect(choice.chatPartnerRelationship == .stranger)
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: now.addingTimeInterval(60)).first == choice)
}

/// 似ている過去の記録で何も選んでいなかった (端末の言語・関係は未選択) 時は、今の選択ではなく未選択を既定にすること
@Test func addChoiceKeepsUnselectedChoiceOfSameChat() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: nil,
        chatPartnerRelationship: nil,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .stranger,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(choice.targetLanguageIdentifier == nil)
    #expect(choice.chatPartnerRelationship == nil)
}

/// 利用者が既に選び直していた時 (usesMostSimilarChoice が false) は、似ている記録があっても今の選択を既定にして記録すること
@Test func addChoiceIgnoresPastChoiceWhenUserAlreadyChose() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .friendOrFamily,
        usesMostSimilarChoice: false,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(choice.targetLanguageIdentifier == "fr-Latn-FR")
    #expect(choice.chatPartnerRelationship == .friendOrFamily)
}

/// 既定になった言語と関係を選び直すと、その読み取りの記録が書き換わり、次に同じ相手を読んだ時は選び直したものが既定になること
@Test func updatedChoiceBecomesDefaultForNextReadingOfSameChat() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let firstChoiceID = UUID()
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: firstChoiceID,
        now: now,
        fileURL: fileURL
    )
    try updateScreenshotReadingChoice(
        id: firstChoiceID,
        targetLanguageIdentifier: "de-Latn-DE",
        chatPartnerRelationship: .superiorOrClient,
        now: now.addingTimeInterval(10),
        fileURL: fileURL
    )

    let nextChoice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(nextChoice.targetLanguageIdentifier == "de-Latn-DE")
    #expect(nextChoice.chatPartnerRelationship == .superiorOrClient)
}

/// 書き換える記録が無い時 (消えた時) は、ほかの記録を書き換えず、記録を足さないこと
@Test func updateChoiceDoesNothingForMissingRecord() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    try updateScreenshotReadingChoice(
        id: UUID(),
        targetLanguageIdentifier: "de-Latn-DE",
        chatPartnerRelationship: .stranger,
        now: now,
        fileURL: fileURL
    )

    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: now) == [choice])
}

/// 記録を足す時に、残す期間を過ぎた記録を消すこと
@Test func addChoiceDropsExpiredRecords() throws {
    let fileURL = makeChoicesFileURL()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    try save(
        screenshotReadingChoices: [pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker, readAt: now.addingTimeInterval(-15 * 24 * 60 * 60))],
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", headers: []),
        targetLanguageIdentifier: nil,
        chatPartnerRelationship: .stranger,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    // 期間を過ぎた記録の選択 (仕事の仲間) は既定にならない
    #expect(choice.chatPartnerRelationship == .stranger)
    #expect(try JSONDecoder().decode([ScreenshotReadingChoice].self, from: Data(contentsOf: fileURL)) == [choice])
}

/// 似ている記録が複数ある時: チャットの名前が同じ記録どうしでは、発言した人の名前の重なりが大きい記録を、新しい記録より先に選ぶこと。
/// チャットの名前を読めない記録どうしでも同じこと
@Test func mostSimilarChoicePrefersLargerSpeakerOverlapOverNewer() {
    let largerOverlapOlder = pastChoice(
        chatTitle: "# design-review",
        speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
        relationship: .coworker,
        readAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "# design-review",
            speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
            pastChoices: [
                largerOverlapOlder,
                pastChoice(
                    chatTitle: "# design-review",
                    speakerNames: ["Priya Nakamoto"],
                    relationship: .stranger,
                    readAt: Date(timeIntervalSinceReferenceDate: 800_000_100)
                ),
            ]
        ) == largerOverlapOlder
    )

    let namesOnlyLargerOverlapOlder = pastChoice(
        chatTitle: nil,
        speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
        relationship: .coworker,
        readAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
    )
    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: nil,
            speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
            pastChoices: [
                namesOnlyLargerOverlapOlder,
                // 2 人のうち 1 人が同じ (1/2) で、似ているが重なりが小さい新しい記録
                pastChoice(
                    chatTitle: nil,
                    speakerNames: ["Mira Solberg"],
                    relationship: .stranger,
                    readAt: Date(timeIntervalSinceReferenceDate: 800_000_100)
                ),
            ]
        ) == namesOnlyLargerOverlapOlder
    )
}

/// 新しい読み取りでチャットの名前を読めず、過去の記録だけに名前がある時も、発言した人の名前で比べること
@Test func mostSimilarChoiceUsesSpeakersWhenOnlyPastChoiceHasTitle() {
    let pastWithTitle = pastChoice(chatTitle: "# design-review", speakerNames: ["Mira Solberg", "Tobias Lindqvist"], relationship: .coworker)

    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: nil,
            speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
            pastChoices: [pastWithTitle]
        ) == pastWithTitle
    )
    #expect(
        mostSimilarScreenshotReadingChoice(chatTitleReadFromScreen: nil, speakerNames: ["Priya Nakamoto"], pastChoices: [pastWithTitle]) == nil
    )
}

/// 手がかりの文字は数字も残すこと (数字だけが違うチャンネルを同じ相手にしないため)
@Test func comparableClueTextKeepsDigits() {
    #expect(comparableClueText(text: "# team-1") != comparableClueText(text: "# team-2"))
    #expect(comparableClueText(text: "# team-1") == "team1")
}

/// 記録を書き込めない場所 (無いディレクトリの下) では、記録を足す時と保存する時にエラーを投げること
@Test func choicesThrowWhenFileCannotBeWritten() {
    let unwritableFileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScreenshotReadingChoiceTests-missing-\(UUID().uuidString)")
        .appendingPathComponent("screenshot-reading-choices.json")

    #expect(throws: (any Error).self) {
        try addScreenshotReadingChoice(
            lines: chatScreenLines(chatTitle: "# design-review", headers: []),
            targetLanguageIdentifier: nil,
            chatPartnerRelationship: nil,
            usesMostSimilarChoice: true,
            id: UUID(),
            now: Date(),
            fileURL: unwritableFileURL
        )
    }
    #expect(throws: (any Error).self) {
        try save(screenshotReadingChoices: [], fileURL: unwritableFileURL)
    }
}

/// 保存したファイルは、端末のバックアップから外れていること (記録には相手の名前が入り、端末の外へ出さないため)
@Test func savedChoicesFileIsExcludedFromBackup() throws {
    let fileURL = makeChoicesFileURL()

    try save(screenshotReadingChoices: [], fileURL: fileURL)

    #expect(try fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}

/// 過去の記録の既定を当てた時に読み取りを始め直すか: 言語だけが違う時・関係だけが違う時・両方違う時は始め直し、
/// どちらも同じ時は始め直さないこと
@Test func defaultChoiceRestartsReadingWhenLanguageOrRelationshipDiffers() {
    // 既定は es-Latn-ES と仕事の仲間 (pastChoice の言語)
    let restarts = { (savedTargetLanguageIdentifier: String, chatPartnerRelationship: ChatPartnerRelationship?) in
        defaultChoiceRestartsChatReading(
            defaultChoice: pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker),
            savedTargetLanguageIdentifier: savedTargetLanguageIdentifier,
            chatPartnerRelationship: chatPartnerRelationship,
            preferredLanguages: ["ja-JP"]
        )
    }

    #expect(restarts("fr-Latn-FR", .coworker))
    #expect(restarts("es-Latn-ES", .stranger))
    #expect(restarts("fr-Latn-FR", .stranger))
    #expect(!restarts("es-Latn-ES", .coworker))
}

/// 保存の書き方だけが違い、訳す先の言語が同じ時は始め直さないこと: 記録は未選択 (端末の言語へ訳す) で、今は端末の言語と同じ言語を選んでいる時と、
/// その逆の時。始め直すと見込んで読み取りを止めると、.task(id:) が動き直さず画面が読み取り中のまま止まるため
@Test func defaultChoiceDoesNotRestartReadingWhenOnlySavedFormDiffers() {
    let unselectedChoice = ScreenshotReadingChoice(
        id: UUID(),
        readAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
        chatTitleReadFromScreen: "# design-review",
        speakerNames: [],
        targetLanguageIdentifier: nil,
        chatPartnerRelationship: nil
    )
    #expect(
        !defaultChoiceRestartsChatReading(
            defaultChoice: unselectedChoice,
            savedTargetLanguageIdentifier: "en-Latn-US",
            chatPartnerRelationship: nil,
            preferredLanguages: ["en-US"]
        )
    )

    var deviceLanguageChoice = unselectedChoice
    deviceLanguageChoice.targetLanguageIdentifier = "en-Latn-US"
    #expect(
        !defaultChoiceRestartsChatReading(
            defaultChoice: deviceLanguageChoice,
            savedTargetLanguageIdentifier: "",
            chatPartnerRelationship: nil,
            preferredLanguages: ["en-US"]
        )
    )
}
