import CoreGraphics
import Testing
@testable import Poppo

/// テスト用に、文字と位置 (左上が原点。画像の幅と高さを 1 とした値) から、読み取った 1 行を作る
private func textLine(text: String, minX: Double, minY: Double, width: Double) -> RecognizedTextLine {
    // 高さ 0.02: iPhone の画面 (高さ約 870pt) で、本文の 1 行 (約 17pt) にあたる値
    RecognizedTextLine(text: text, boundingBox: CGRect(x: minX, y: minY, width: width, height: 0.02))
}

/// 吹き出しで並ぶチャット (相手は左、利用者は右) から、発言を 1 つずつ抜き出し、利用者自身の発言を見分けること。
/// 複数行の発言は 1 つにまとめ、行を改行でつなぐ
@Test func bubbleChatIsSplitIntoMessagesWithUserMessagesMarked() {
    let messages = extractMessages(lines: [
        textLine(text: "Are you free today?", minX: 0.08, minY: 0.2, width: 0.5),
        textLine(text: "I need help with the report", minX: 0.08, minY: 0.224, width: 0.6),
        textLine(text: "Sure, what do you need?", minX: 0.55, minY: 0.28, width: 0.37),
        textLine(text: "Thanks!", minX: 0.08, minY: 0.34, width: 0.2),
    ])

    #expect(messages.map(\.text) == [
        "Are you free today?\nI need help with the report",
        "Sure, what do you need?",
        "Thanks!",
    ])
    #expect(messages.map(\.isFromUser) == [false, true, false])
}

/// 相手の発言のすぐ下に利用者の発言が続いていても (行間が発言の中の行間と同じでも)、左右の位置が違えば別の発言にすること。
/// 自分の発言と相手の発言を 1 つに混ぜない
@Test func adjacentLinesOnDifferentSidesAreSeparateMessages() {
    let messages = extractMessages(lines: [
        textLine(text: "Did you see my message?", minX: 0.08, minY: 0.3, width: 0.5),
        textLine(text: "Yes, I did", minX: 0.6, minY: 0.324, width: 0.32),
    ])

    #expect(messages.map(\.text) == ["Did you see my message?", "Yes, I did"])
    #expect(messages.map(\.isFromUser) == [false, true])
}

/// 行間が行の高さの半分で、左端のずれが画面の幅の 3% の行は、同じ発言の続きにすること (行間・左端のどちらも境界の内側)
@Test func closeLinesWithAlmostAlignedLeftEdgesAreOneMessage() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Good morning", minX: 0.08, minY: 0.3, width: 0.3),
            textLine(text: "Are you there?", minX: 0.11, minY: 0.33, width: 0.3),
        ]).map(\.text) == ["Good morning\nAre you there?"]
    )
}

/// 行間が行の高さと同じだけ空いた行は、左端がそろっていても別の発言にすること (行間が境界の外側)
@Test func linesOneLineHeightApartAreSeparateMessages() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Good morning", minX: 0.08, minY: 0.3, width: 0.3),
            textLine(text: "Are you there?", minX: 0.08, minY: 0.34, width: 0.3),
        ]).map(\.text) == ["Good morning", "Are you there?"]
    )
}

/// 左端が画面の幅の 6% ずれた行は、行間が狭くても別の発言にすること (左端が境界の外側)
@Test func closeLinesWithShiftedLeftEdgesAreSeparateMessages() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Good morning", minX: 0.08, minY: 0.3, width: 0.3),
            textLine(text: "Are you there?", minX: 0.14, minY: 0.33, width: 0.3),
        ]).map(\.text) == ["Good morning", "Are you there?"]
    )
}

/// 利用者の複数行の発言は、最後の行が短くても (右の余白が広くても) 全体で 1 つの利用者の発言にすること
@Test func multiLineUserMessageWithShortLastLineIsUserMessage() {
    let messages = extractMessages(lines: [
        textLine(text: "I will send the report by tomorrow", minX: 0.3, minY: 0.3, width: 0.62),
        textLine(text: "morning", minX: 0.3, minY: 0.324, width: 0.12),
    ])

    #expect(messages.map(\.text) == ["I will send the report by tomorrow\nmorning"])
    #expect(messages.map(\.isFromUser) == [true])
}

/// 右端まで届く発言でも、左の余白が画面の幅の 2 割に届かなければ相手の発言、2 割を超えれば利用者の発言にすること
/// (左の余白の境界の両側。0.19 と 0.21)
@Test func userMessageNeedsLeftMarginOfTwentyPercent() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Left margin is 19 percent", minX: 0.19, minY: 0.3, width: 0.73),
            textLine(text: "Left margin is 21 percent", minX: 0.21, minY: 0.5, width: 0.71),
        ]).map(\.isFromUser) == [false, true]
    )
}

/// 左の余白が 2 割を超えていても、右の余白との差が画面の幅の 1 割に届かなければ相手の発言、1 割を超えれば利用者の発言にすること
/// (左右の余白の差の境界の両側。0.05 と 0.15)
@Test func userMessageNeedsLeftMarginLargerThanRightMargin() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Margins differ by 5 percent", minX: 0.3, minY: 0.3, width: 0.45),
            textLine(text: "Margins differ by 15 percent", minX: 0.3, minY: 0.5, width: 0.55),
        ]).map(\.isFromUser) == [false, true]
    )
}

/// 全員の発言が左に並ぶチャット (Slack・Discord の形。名前と時刻の行の下に本文が続く) では、
/// 発言ごとにまとめ、画面の幅いっぱいの行があっても、すべて相手の発言として返すこと。名前と時刻の行は発言の先頭に残す
@Test func leftAlignedChatReturnsEveryMessageAsFromOthers() {
    let messages = extractMessages(lines: [
        textLine(text: "Alice 10:42 AM", minX: 0.15, minY: 0.2, width: 0.3),
        textLine(text: "Can you review my PR?", minX: 0.15, minY: 0.224, width: 0.45),
        textLine(text: "It changes the login screen and the settings screen", minX: 0.15, minY: 0.248, width: 0.81),
        textLine(text: "Bob 10:45 AM", minX: 0.15, minY: 0.31, width: 0.28),
        textLine(text: "Sure, I'll take a look", minX: 0.15, minY: 0.334, width: 0.4),
    ])

    #expect(messages.map(\.text) == [
        "Alice 10:42 AM\nCan you review my PR?\nIt changes the login screen and the settings screen",
        "Bob 10:45 AM\nSure, I'll take a look",
    ])
    #expect(messages.map(\.isFromUser) == [false, false])
}

/// 画面の中央にある行 (日付の区切り等) は、左の余白が広くても利用者の発言にしないこと
@Test func centeredLineIsNotUserMessage() {
    #expect(
        extractMessages(lines: [textLine(text: "Today", minX: 0.44, minY: 0.3, width: 0.12)]).map(\.isFromUser) == [false]
    )
}

/// 時刻だけの行 (発言の横や下に出る送信時刻) は発言に含めず、時刻を含む文は発言として残すこと
@Test func timeOnlyLinesAreExcludedButSentencesWithTimeAreKept() {
    #expect(
        extractMessages(lines: [
            textLine(text: "10:42", minX: 0.08, minY: 0.2, width: 0.1),
            textLine(text: "See you at 10:30", minX: 0.08, minY: 0.3, width: 0.4),
            textLine(text: "10:42 AM", minX: 0.08, minY: 0.4, width: 0.15),
            textLine(text: "10:42 is fine", minX: 0.08, minY: 0.5, width: 0.3),
            textLine(text: "午後3:41", minX: 0.08, minY: 0.6, width: 0.15),
        ]).map(\.text) == ["See you at 10:30", "10:42 is fine"]
    )
}

/// 画面の上のバー (相手やチャンネルの名前) と下の入力欄にあたる帯の行は発言に含めず、帯のすぐ内側の行は残すこと
/// (上は 0.12 の両側の 0.11 と 0.125、下は 0.9 の両側の 0.895 と 0.905)
@Test func linesInTopAndBottomBarsAreExcluded() {
    #expect(
        extractMessages(lines: [
            textLine(text: "#general", minX: 0.4, minY: 0.11, width: 0.2),
            textLine(text: "First message", minX: 0.08, minY: 0.125, width: 0.3),
            textLine(text: "Last message", minX: 0.08, minY: 0.875, width: 0.3),
            textLine(text: "Message #general", minX: 0.5, minY: 0.885, width: 0.4),
        ]).map(\.text) == ["First message", "Last message"]
    )
}

/// 渡した行の順に関係なく、発言を画面の上から下の順に返すこと
@Test func messagesAreReturnedFromTopToBottom() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Third", minX: 0.08, minY: 0.6, width: 0.2),
            textLine(text: "First", minX: 0.08, minY: 0.2, width: 0.2),
            textLine(text: "Second", minX: 0.08, minY: 0.4, width: 0.2),
        ]).map(\.text) == ["First", "Second", "Third"]
    )
}

/// 読み取れた行が無い時は、発言を 1 つも返さないこと
@Test func noLinesGiveNoMessages() {
    #expect(extractMessages(lines: []).isEmpty)
}
