import CoreGraphics
import Foundation
import Testing

@testable import Poppo

/// テストごとに別の、まだ無い記録のファイルの場所を返す。ほかのテストと本体アプリの記録を混ぜないため
private func makeChoicesFileURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotReadingChoiceTests-\(UUID().uuidString).json")
}

/// 文字の読み取りの偽物が返す、チャットの画面の行。ステータスバーの時刻と電波、上部のチャットの名前 (chatTitle。nil は上部に文字が無い画面)、
/// 発言ごとの見出し (speakers の名前と、その右に別の行として並ぶ時刻) と本文を、見本の画像 (PoppoTests/ChatScreenSamples/) と同じ並びで置く
private func chatScreenLines(chatTitle: String?, speakers: [String]) -> [RecognizedTextLine] {
    [
        RecognizedTextLine(text: "9:41", boundingBox: CGRect(x: 0.08, y: 0.025, width: 0.1, height: 0.02)),
        RecognizedTextLine(text: "5G", boundingBox: CGRect(x: 0.86, y: 0.025, width: 0.06, height: 0.02)),
    ]
        + (chatTitle.map { [RecognizedTextLine(text: $0, boundingBox: CGRect(x: 0.33, y: 0.078, width: 0.34, height: 0.02))] } ?? [])
        + speakers.enumerated().flatMap { index, speaker in
            threadMessageLines(name: speaker, time: "10:42 AM", body: "Message \(index)", top: 0.2 + 0.1 * CGFloat(index))
        }
}

/// 全員の発言が左に並ぶチャット (Slack) の 1 つの発言の行。名前 (name) と、その右に別の行として並ぶ時刻 (time) の見出しを top の高さに置き、
/// 本文 (body) をすぐ下に同じ左端で置く。位置は見本の画像 (chat-screen-sample-thread-light-english.png) の配置に合わせる
private func threadMessageLines(name: String, time: String, body: String, top: CGFloat) -> [RecognizedTextLine] {
    [
        RecognizedTextLine(text: name, boundingBox: CGRect(x: 0.16, y: top, width: 0.25, height: 0.02)),
        RecognizedTextLine(text: time, boundingBox: CGRect(x: 0.43, y: top, width: 0.12, height: 0.02)),
        RecognizedTextLine(text: body, boundingBox: CGRect(x: 0.16, y: top + 0.03, width: 0.6, height: 0.02)),
    ]
}

/// テストの記録の、読んだ時刻の基準。値に意味は無く、テストの結果が実行した日時で変わらないよう固定する
private let testReadAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// テストで比べる過去の記録を作る。どの記録が選ばれたかは関係 (relationship) で見分ける。
/// 言語は、どの記録でも同じ es-Latn-ES にする (テストの端末の言語 (ja-JP・en-US) と違う言語にして、未選択と見分けるため)
private func pastChoice(
    chatTitle: String?,
    speakerNames: [String],
    relationship: ChatPartnerRelationship?,
    // testReadAt: 読んだ時刻の順を見ないテストでは、どの記録も同じ時刻でよいため
    readAt: Date = testReadAt
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
            lines: chatScreenLines(chatTitle: "# design-review", speakers: [])
                + [RecognizedTextLine(text: "‹", boundingBox: CGRect(x: 0.03, y: 0.078, width: 0.03, height: 0.02))]
        ) == "# design-review"
    )
}

/// 上部の段に文字が無く、ステータスバーにだけ文字がある画面では、チャットの名前を読まない (nil) こと。
/// ステータスバーの文字を名前にすると、どの画面も同じチャットになってしまうため
@Test func chatTitleIsNilWhenOnlyStatusBarHasText() {
    #expect(chatTitleReadFromScreen(lines: chatScreenLines(chatTitle: nil, speakers: ["Mira Solberg"])) == nil)
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

/// 見出し (名前と、その右の時刻) から発言した人の名前を、画面の上から下の順に読み、同じ人 (空白と大文字小文字の違いを含む) は 1 つにまとめること。
/// 時刻の前に語が付く時刻の行 (「hoy a las 18:05」) も見出しの時刻として読み、名前には含めないこと
@Test func speakerNamesAreReadFromHeaderRowsWithoutDuplicates() {
    #expect(
        speakerNames(
            lines: threadMessageLines(name: "Mira Solberg", time: "10:42 AM", body: "Can someone review?", top: 0.2)
                + threadMessageLines(name: "水瀬 あおい", time: "14:05", body: "確認をお願いします。", top: 0.3)
                + threadMessageLines(name: "MiraSolberg", time: "10:47 AM", body: "Thanks!", top: 0.4)
                + threadMessageLines(name: "luna_verde", time: "hoy a las 18:05", body: "¿Alguien?", top: 0.5)
        ) == ["Mira Solberg", "水瀬 あおい", "luna_verde"]
    )
}

/// ほかの見出しと並べるための、画面の下の方の 2 つの発言 (otherSpeakerNames の 2 人の見出しと本文)。見出しの形の行が 2 つ以上ある時だけ名前を読むため、
/// 1 つの行を見出しにするかを確かめるテストに足し、その行を見出しにしなくても名前を読める入力にする
private let otherHeaderMessageLines =
    threadMessageLines(name: "Priya Nakamoto", time: "11:02 AM", body: "Other message", top: 0.6)
    + threadMessageLines(name: "Kenji Sato", time: "11:05 AM", body: "Another message", top: 0.7)

/// otherHeaderMessageLines から読む発言した人の名前 (画面の上から下の順)
private let otherSpeakerNames = ["Priya Nakamoto", "Kenji Sato"]

/// 名前と時刻を Vision が 1 つの行に読んだ見出し (「Mira Solberg 10:42 AM」「水瀬あおい 14:05」「Bob 午後 3:41」) から、時刻を除いた名前を読むこと
@Test func speakerNamesAreReadFromSingleLineHeaders() {
    let message = { (header: String, top: CGFloat) in
        [
            RecognizedTextLine(text: header, boundingBox: CGRect(x: 0.16, y: top, width: 0.4, height: 0.02)),
            RecognizedTextLine(text: "Body", boundingBox: CGRect(x: 0.16, y: top + 0.03, width: 0.6, height: 0.02)),
        ]
    }

    #expect(
        speakerNames(lines: message("Mira Solberg 10:42 AM", 0.2) + message("水瀬あおい 14:05", 0.3) + message("Bob 午後 3:41", 0.4))
            == ["Mira Solberg", "水瀬あおい", "Bob"]
    )
}

/// 見出しの形の行が画面に 1 つだけの時は名前を読まず、2 つの時は読むこと (境目の対)。
/// 時刻で終わる本文 (「Meet me at 10:42」の下に「See you」) が 1 つだけ見出しの形になっても、名前として残さないため
@Test func speakerNamesRequireTwoOrMoreHeaders() {
    let line = { (text: String, x: CGFloat, y: CGFloat) in RecognizedTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.25, height: 0.02)) }

    #expect(speakerNames(lines: [line("Meet me at 10:42", 0.16, 0.2), line("See you", 0.16, 0.23)]).isEmpty)
    #expect(speakerNames(lines: threadMessageLines(name: "Mira Solberg", time: "10:42 AM", body: "Body", top: 0.2)).isEmpty)
    #expect(
        speakerNames(
            lines: threadMessageLines(name: "Mira Solberg", time: "10:42 AM", body: "Body", top: 0.2)
                + threadMessageLines(name: "Priya Nakamoto", time: "11:02 AM", body: "Other message", top: 0.6)
        ) == ["Mira Solberg", "Priya Nakamoto"]
    )
}

/// 時刻で終わる発言の本文を、名前として読まないこと: 吹き出しの中で最後の行の右に時刻が付く本文 (下に本文が続かない)、
/// 本文の右の行が 4 語以上の文で時刻で終わる時、発言の 2 行目以降が時刻で終わる時 (発言の最初の行でない)
@Test func speakerNamesIgnoreMessageBodiesEndingWithTime() {
    let line = { (text: String, x: CGFloat, y: CGFloat) in RecognizedTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.25, height: 0.02)) }

    // 吹き出しの最後の行の右に時刻 (下に本文が続かない)
    #expect(speakerNames(lines: [line("Bonjour", 0.16, 0.2), line("10:42", 0.43, 0.2)] + otherHeaderMessageLines) == otherSpeakerNames)
    // 右の行が 4 語以上の文で時刻で終わる (時刻の行ではない)
    #expect(
        speakerNames(
            lines: [line("Mira Solberg", 0.16, 0.2), line("we can meet at 10:42", 0.43, 0.2), line("Body", 0.16, 0.23)] + otherHeaderMessageLines
        ) == otherSpeakerNames
    )
    // 時刻の前の語が 3 語なら時刻の行として読む (上の 4 語の場合と対になる境目)
    #expect(
        speakerNames(
            lines: [line("luna_verde", 0.16, 0.2), line("hoy a las 18:05", 0.43, 0.2), line("Body", 0.16, 0.23)] + otherHeaderMessageLines
        ) == ["luna_verde"] + otherSpeakerNames
    )
    // 発言の 2 行目が時刻で終わり、下に 3 行目が続く
    #expect(
        speakerNames(
            lines: [line("Let's talk", 0.16, 0.2), line("Meet me at 10:42", 0.16, 0.23), line("See you", 0.16, 0.26)] + otherHeaderMessageLines
        ) == otherSpeakerNames
    )
}

/// 右に寄った利用者の発言の行と、発言の並ぶ範囲の外 (上部のバー) の行は、見出しの形でも名前として読まないこと
@Test func speakerNamesIgnoreUserMessagesAndRowsOutsideChatArea() {
    let line = { (text: String, x: CGFloat, y: CGFloat) in RecognizedTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.2, height: 0.02)) }

    #expect(
        speakerNames(lines: [line("Sure thing", 0.5, 0.2), line("10:42", 0.72, 0.2), line("See you", 0.5, 0.23)] + otherHeaderMessageLines)
            == otherSpeakerNames
    )
    #expect(
        speakerNames(lines: [line("Sure thing 10:42", 0.6, 0.2), line("See you", 0.6, 0.23)] + otherHeaderMessageLines) == otherSpeakerNames
    )
    #expect(
        speakerNames(lines: [line("Mira Solberg", 0.16, 0.07), line("10:42", 0.38, 0.07), line("Body", 0.16, 0.1)] + otherHeaderMessageLines)
            == otherSpeakerNames
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
    let newer = pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .friendOrFamily, readAt: testReadAt.addingTimeInterval(100))

    #expect(
        mostSimilarScreenshotReadingChoice(
            chatTitleReadFromScreen: "# design-review",
            speakerNames: ["Mira Solberg"],
            pastChoices: [
                pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker, readAt: testReadAt),
                // 発言した人の名前だけが同じで、最も新しい記録
                pastChoice(chatTitle: nil, speakerNames: ["Mira Solberg"], relationship: .stranger, readAt: testReadAt.addingTimeInterval(200)),
                newer,
            ]
        ) == newer
    )
}

/// 残す記録: 読んでから 14 日を過ぎた記録を除き (ちょうど 14 日は除き、その 1 秒前は残す)、新しい順に並べること
@Test func retainedChoicesDropRecordsOlderThan14Days() {
    let now = testReadAt
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
    let now = testReadAt
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
    let now = testReadAt
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: ["Mira Solberg"]),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "Harbor Books", speakers: ["Harbor Books"]),
        targetLanguageIdentifier: "fr-Latn-FR",
        chatPartnerRelationship: .superiorOrClient,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now.addingTimeInterval(60),
        fileURL: fileURL
    )

    let choiceForA = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: ["Tobias Lindqvist", "Mira Solberg"]),
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
    #expect(choiceForA.speakerNames == ["Tobias Lindqvist", "Mira Solberg"])
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: now.addingTimeInterval(120)).count == 3)
}

/// 前に読んだことの無い相手のスクリーンショットでは、今選ばれている (直前に選んだ) 言語と関係が既定になり、そのまま記録されること
@Test func addChoiceUsesCurrentChoiceForUnknownChat() throws {
    let fileURL = makeChoicesFileURL()
    let now = testReadAt
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "Harbor Books", speakers: []),
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
    let now = testReadAt
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
        targetLanguageIdentifier: nil,
        chatPartnerRelationship: nil,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
    let now = testReadAt
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
        targetLanguageIdentifier: "en-Latn-US",
        chatPartnerRelationship: .coworker,
        usesMostSimilarChoice: true,
        id: UUID(),
        now: now,
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
    let now = testReadAt
    let firstChoiceID = UUID()
    _ = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
    let now = testReadAt
    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
    let now = testReadAt
    try save(
        screenshotReadingChoices: [pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker, readAt: now.addingTimeInterval(-15 * 24 * 60 * 60))],
        fileURL: fileURL
    )

    let choice = try addScreenshotReadingChoice(
        lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
        readAt: testReadAt
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
                    readAt: testReadAt.addingTimeInterval(100)
                ),
            ]
        ) == largerOverlapOlder
    )

    let namesOnlyLargerOverlapOlder = pastChoice(
        chatTitle: nil,
        speakerNames: ["Mira Solberg", "Tobias Lindqvist"],
        relationship: .coworker,
        readAt: testReadAt
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
                    readAt: testReadAt.addingTimeInterval(100)
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
            lines: chatScreenLines(chatTitle: "# design-review", speakers: []),
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
        readAt: testReadAt,
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

/// 記録が 2 件以上ある時に書き換えると、指定した id の記録だけが変わり、ほかの記録はそのままであること
@Test func updateChoiceChangesOnlyRecordWithGivenID() throws {
    let fileURL = makeChoicesFileURL()
    let targetChoice = pastChoice(chatTitle: "# design-review", speakerNames: [], relationship: .coworker)
    let otherChoice = pastChoice(chatTitle: "Harbor Books", speakerNames: [], relationship: .stranger)
    try save(screenshotReadingChoices: [targetChoice, otherChoice], fileURL: fileURL)

    try updateScreenshotReadingChoice(
        id: targetChoice.id,
        targetLanguageIdentifier: "de-Latn-DE",
        chatPartnerRelationship: .superiorOrClient,
        now: testReadAt,
        fileURL: fileURL
    )

    let choices = loadScreenshotReadingChoices(fileURL: fileURL, now: testReadAt)
    #expect(choices.first { $0.id == targetChoice.id }?.chatPartnerRelationship == .superiorOrClient)
    #expect(choices.first { $0.id == targetChoice.id }?.targetLanguageIdentifier == "de-Latn-DE")
    #expect(choices.first { $0.id == otherChoice.id } == otherChoice)
}

/// 読み取りの画面が文字を読み終えた時: 前に読んだ同じ相手の記録があれば、その言語と関係を既定にして読み取りを始め直すこと。
/// 2 回目に開いた同じ相手では、記録が足されて 2 件になること
@MainActor @Test func recordScreenshotReadingAppliesPastChoiceOfSameChatAndRestarts() throws {
    let fileURL = makeChoicesFileURL()
    let lines = chatScreenLines(chatTitle: "# design-review", speakers: ["Mira Solberg"])
    let first = recordScreenshotReading(
        lines: lines,
        savedTargetLanguageIdentifier: "da-Latn-DK",
        chatPartnerRelationship: .coworker,
        hasUserChangedChoice: false,
        preferredLanguages: ["en-US"],
        id: UUID(),
        now: testReadAt,
        fileURL: fileURL
    )
    #expect(first.choice?.chatPartnerRelationship == .coworker)
    #expect(!first.restartsReading)

    let second = recordScreenshotReading(
        lines: lines,
        savedTargetLanguageIdentifier: "nl-Latn-NL",
        chatPartnerRelationship: .friendOrFamily,
        hasUserChangedChoice: false,
        preferredLanguages: ["en-US"],
        id: UUID(),
        now: testReadAt.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(second.choice?.targetLanguageIdentifier == "da-Latn-DK")
    #expect(second.choice?.chatPartnerRelationship == .coworker)
    #expect(second.restartsReading)
    #expect(loadScreenshotReadingChoices(fileURL: fileURL, now: testReadAt.addingTimeInterval(60)).count == 2)
}

/// 利用者が文字を読み終える前に選び直していた時は、前に読んだ同じ相手の記録を当てず、今の選択で記録して始め直さないこと
@MainActor @Test func recordScreenshotReadingKeepsChoiceWhenUserAlreadyChose() throws {
    let fileURL = makeChoicesFileURL()
    let lines = chatScreenLines(chatTitle: "# design-review", speakers: [])
    _ = recordScreenshotReading(
        lines: lines,
        savedTargetLanguageIdentifier: "da-Latn-DK",
        chatPartnerRelationship: .coworker,
        hasUserChangedChoice: false,
        preferredLanguages: ["en-US"],
        id: UUID(),
        now: testReadAt,
        fileURL: fileURL
    )

    let reading = recordScreenshotReading(
        lines: lines,
        savedTargetLanguageIdentifier: "nl-Latn-NL",
        chatPartnerRelationship: .friendOrFamily,
        hasUserChangedChoice: true,
        preferredLanguages: ["en-US"],
        id: UUID(),
        now: testReadAt.addingTimeInterval(60),
        fileURL: fileURL
    )

    #expect(reading.choice?.targetLanguageIdentifier == "nl-Latn-NL")
    #expect(reading.choice?.chatPartnerRelationship == .friendOrFamily)
    #expect(!reading.restartsReading)
}

/// 記録の場所が無い時と、記録を保存できない時は、記録を返さず (既定を当てず) 始め直さないこと。
/// 未選択 (空文字) の言語は、記録に未選択 (nil) として残すこと
@MainActor @Test func recordScreenshotReadingWithoutStorageKeepsCurrentChoice() throws {
    let lines = chatScreenLines(chatTitle: "# design-review", speakers: [])
    // 2 つ目: 無いディレクトリの下 (書き込めない場所)
    for fileURL in [
        nil,
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotReadingChoiceTests-missing-\(UUID().uuidString)")
            .appendingPathComponent("screenshot-reading-choices.json"),
    ] {
        let reading = recordScreenshotReading(
            lines: lines,
            savedTargetLanguageIdentifier: "",
            chatPartnerRelationship: .coworker,
            hasUserChangedChoice: false,
            preferredLanguages: ["en-US"],
            id: UUID(),
            now: testReadAt,
            fileURL: fileURL
        )
        #expect(reading.choice == nil)
        #expect(!reading.restartsReading)
    }

    #expect(
        recordScreenshotReading(
            lines: lines,
            savedTargetLanguageIdentifier: "",
            chatPartnerRelationship: .coworker,
            hasUserChangedChoice: false,
            preferredLanguages: ["en-US"],
            id: UUID(),
            now: testReadAt,
            fileURL: makeChoicesFileURL()
        ).choice?.targetLanguageIdentifier == nil
    )
}

#if DEBUG
/// 開発者メニューの見本のチャットの画面を Vision の実物で読むと、上部から各見本のチャットの名前を読み、2 つの見本が別の相手になること
/// (simulator で相手を交互に読んで、既定が相手ごとに変わることを確かめるための見本のため)
@MainActor @Test(.timeLimit(.minutes(1))) func debugSampleChatScreensAreReadAsDifferentChats() async throws {
    var chatTitles: [String] = []
    for sampleChat in DebugSampleChat.allCases {
        let chatTitle = try #require(
            chatTitleReadFromScreen(lines: try await recognizeTextLines(image: try debugSampleChatScreenImage(sampleChat: sampleChat)))
        )
        #expect(comparableClueText(text: chatTitle) == comparableClueText(text: sampleChat.title))
        chatTitles.append(comparableClueText(text: chatTitle))
    }
    #expect(Set(chatTitles).count == DebugSampleChat.allCases.count)
}
#endif

/// 見出しの形の行 (名前と右の時刻) の下に行があっても、同じ発言の続きでない時 (行間が離れている・左端がずれている) は名前として読まないこと。
/// すぐ下に同じ左端で続く時は読むこと (境目の対)
@Test func speakerNamesRequireBodyLineContinuingBelowHeader() {
    let line = { (text: String, x: CGFloat, y: CGFloat) in RecognizedTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: 0.25, height: 0.02)) }
    let header = [line("Mira Solberg", 0.16, 0.2), line("10:42 AM", 0.43, 0.2)]

    // 行間 0.05 (行の高さ 0.02 の 0.75 倍を超える)
    #expect(speakerNames(lines: header + [line("Body", 0.16, 0.27)] + otherHeaderMessageLines) == otherSpeakerNames)
    // 左端が 0.1 ずれる (0.04 を超える)
    #expect(speakerNames(lines: header + [line("Body", 0.26, 0.23)] + otherHeaderMessageLines) == otherSpeakerNames)
    // 行間 0.01・左端が同じ
    #expect(speakerNames(lines: header + [line("Body", 0.16, 0.23)] + otherHeaderMessageLines) == ["Mira Solberg"] + otherSpeakerNames)
}

/// 端末に保存してある訳す先の言語を記録に残す形: 空文字 (未選択) は nil、選んだ言語はそのまま
@Test func recordedTargetLanguageIdentifierTreatsEmptyAsUnselected() {
    #expect(recordedTargetLanguageIdentifier(savedIdentifier: "") == nil)
    #expect(recordedTargetLanguageIdentifier(savedIdentifier: "da-Latn-DK") == "da-Latn-DK")
}

/// 上部の段の題名は左右の中央の行から読むこと: 中央の短い名前 (「Bob」) を、左の長い戻るボタンのラベル (「‹ Messages」) より先に選ぶこと。
/// 題名の下に出る補助の行 (「online」) より上の題名を選ぶこと。中央に行が無い (名前を左に寄せる) 画面では読まないこと
@Test func chatTitleIsCenteredTopmostNavigationLine() {
    let line = { (text: String, x: CGFloat, y: CGFloat, width: CGFloat) in
        RecognizedTextLine(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: 0.02))
    }

    #expect(chatTitleReadFromScreen(lines: [line("‹ Messages", 0.03, 0.07, 0.25), line("Bob", 0.46, 0.07, 0.08)]) == "Bob")
    #expect(chatTitleReadFromScreen(lines: [line("online", 0.44, 0.095, 0.12), line("Bob", 0.46, 0.07, 0.08)]) == "Bob")
    #expect(chatTitleReadFromScreen(lines: [line("‹", 0.03, 0.07, 0.03), line("Bob Smith", 0.15, 0.07, 0.2)]) == nil)
}

/// 中央とみなす範囲の境目: 行の枠の中心が画面の中央から 0.15 以内なら題名にし、それより外なら題名にしないこと
@Test func chatTitleCenterBoundary() {
    let line = { (midX: CGFloat) in RecognizedTextLine(text: "Harbor Books", boundingBox: CGRect(x: midX - 0.1, y: 0.07, width: 0.2, height: 0.02)) }

    #expect(chatTitleReadFromScreen(lines: [line(0.649)]) == "Harbor Books")
    #expect(chatTitleReadFromScreen(lines: [line(0.651)]) == nil)
    #expect(chatTitleReadFromScreen(lines: [line(0.351)]) == "Harbor Books")
    #expect(chatTitleReadFromScreen(lines: [line(0.349)]) == nil)
}
