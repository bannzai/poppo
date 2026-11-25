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

    #expect(
        messages.map(\.text) == [
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

    #expect(
        messages.map(\.text) == [
            "Alice 10:42 AM\nCan you review my PR?\nIt changes the login screen and the settings screen",
            "Bob 10:45 AM\nSure, I'll take a look",
        ])
    #expect(messages.map(\.isFromUser) == [false, false])
}

/// 画面の中央にある行 (日付の区切り) は発言に含めず、上下の発言はそのまま残すこと。区切りの文字が何語でも位置で除く
@Test func centeredLinesAreExcluded() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Today", minX: 0.44, minY: 0.2, width: 0.12),
            textLine(text: "Good morning", minX: 0.08, minY: 0.3, width: 0.3),
            textLine(text: "今日", minX: 0.46, minY: 0.4, width: 0.08),
            textLine(text: "Are you there?", minX: 0.08, minY: 0.5, width: 0.3),
        ]).map(\.text) == ["Good morning", "Are you there?"]
    )
}

/// 中心が画面の中央から幅の 1% ずれた行は中央の行として除き、3% ずれた行は発言として残すこと (中心のずれの境界 0.02 の両側)
@Test func centeredLineNeedsCenterWithinTwoPercent() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Center is off by 1 percent", minX: 0.36, minY: 0.3, width: 0.3),
            textLine(text: "Center is off by 3 percent", minX: 0.38, minY: 0.5, width: 0.3),
        ]).map(\.text) == ["Center is off by 3 percent"]
    )
}

/// 中心が画面の中央にあっても、左の余白が画面の幅の 24% の行 (幅いっぱいに近い発言) は残し、26% の行は除くこと
/// (左の余白の境界 0.25 の両側)
@Test func centeredLineNeedsLeftMarginOfTwentyFivePercent() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Left margin is 24 percent", minX: 0.24, minY: 0.3, width: 0.52),
            textLine(text: "Left margin is 26 percent", minX: 0.26, minY: 0.5, width: 0.48),
        ]).map(\.text) == ["Left margin is 24 percent"]
    )
}

/// 名前の右の時刻の行が、その行だけを見ると画面の中央にあっても、名前とつないだ見出しの行として発言に残すこと
/// (見本の Discord に似た画面の 4 つ目の発言の配置。CI の実測: https://github.com/bannzai/poppo/actions/runs/45587820896 )
@Test func timeInSameRowAsNameIsKeptEvenWhenCentered() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Marisol77", minX: 0.17, minY: 0.3, width: 0.2),
            RecognizedTextLine(text: "hoy a las 18:15", boundingBox: CGRect(x: 0.385, y: 0.304, width: 0.23, height: 0.015)),
            textLine(text: "Contad conmigo también.", minX: 0.17, minY: 0.324, width: 0.5),
        ]).map(\.text) == ["Marisol77 hoy a las 18:15\nContad conmigo también."]
    )
}

/// 右に寄った吹き出しの短い 2 行目が、その行だけを見ると画面の中央にあっても、発言の続きの行として残すこと
@Test func centeredLineContinuingMessageIsKept() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Then I will come by tomorrow", minX: 0.33, minY: 0.3, width: 0.6),
            textLine(text: "after work and dinner", minX: 0.33, minY: 0.324, width: 0.34),
        ]).map(\.text) == ["Then I will come by tomorrow\nafter work and dinner"]
    )
}

/// 「既読」だけの行 (利用者の吹き出しの横の印。人数が付く形を含む) は発言に含めず、「既読」を含む文は発言として残すこと
@Test func readReceiptLinesAreExcludedButSentencesWithReadAreKept() {
    #expect(
        extractMessages(lines: [
            textLine(text: "既読", minX: 0.3, minY: 0.2, width: 0.06),
            textLine(text: "既読 2", minX: 0.3, minY: 0.3, width: 0.09),
            textLine(text: "既読になりました", minX: 0.08, minY: 0.4, width: 0.3),
            textLine(text: "既読スルーしないで", minX: 0.08, minY: 0.5, width: 0.3),
        ]).map(\.text) == ["既読になりました", "既読スルーしないで"]
    )
}

/// スレッドの返信の数だけの行は発言の最後の行にせず、返信の数を含む文は発言として残すこと。
/// 返信の数の書き方 (英語の単数と複数、日本語) ごとに、除く行と、似ているが残す文を並べる
@Test func threadReplyCountLinesAreExcludedButSentencesWithReplyCountAreKept() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Any ideas would help a lot.", minX: 0.15, minY: 0.2, width: 0.5),
            textLine(text: "3 replies", minX: 0.15, minY: 0.224, width: 0.15),
            textLine(text: "1 reply", minX: 0.15, minY: 0.3, width: 0.12),
            textLine(text: "3件の返信", minX: 0.15, minY: 0.4, width: 0.15),
            textLine(text: "3 replies so far, thanks", minX: 0.15, minY: 0.5, width: 0.5),
            textLine(text: "1 reply is enough", minX: 0.15, minY: 0.6, width: 0.4),
            textLine(text: "3件の返信がありました", minX: 0.15, minY: 0.7, width: 0.4),
        ]).map(\.text) == [
            "Any ideas would help a lot.",
            "3 replies so far, thanks",
            "1 reply is enough",
            "3件の返信がありました",
        ]
    )
}

/// 名前の行と、同じ段のすぐ右にある時刻の行 (Discord の形。Vision が別の行として返す) は、空白でつないだ見出しの 1 行にし、
/// 下に続く本文と 1 つの発言にすること。時刻の行が名前の行より先に渡されても、左から順につなぐ
@Test func nameAndTimeInSameRowAreJoinedWithBodyIntoOneMessage() {
    let messages = extractMessages(lines: [
        RecognizedTextLine(text: "hoy a las 18:05", boundingBox: CGRect(x: 0.42, y: 0.204, width: 0.22, height: 0.015)),
        textLine(text: "luna_verde", minX: 0.17, minY: 0.2, width: 0.22),
        textLine(text: "¿Alguien quiere jugar esta noche?", minX: 0.17, minY: 0.224, width: 0.6),
        RecognizedTextLine(text: "hoy a las 18:07", boundingBox: CGRect(x: 0.44, y: 0.304, width: 0.22, height: 0.015)),
        textLine(text: "ElZorroAzul", minX: 0.17, minY: 0.3, width: 0.24),
        textLine(text: "Yo puedo después de las nueve.", minX: 0.17, minY: 0.324, width: 0.55),
    ])

    #expect(
        messages.map(\.text) == [
            "luna_verde hoy a las 18:05\n¿Alguien quiere jugar esta noche?",
            "ElZorroAzul hoy a las 18:07\nYo puedo después de las nueve.",
        ])
    #expect(messages.map(\.isFromUser) == [false, false])
}

/// 同じ段にあっても、間が画面の幅の 5% の行はつなぎ、7% 離れた行はつながず別の発言にすること (間の境界 0.06 の両側)
@Test func linesInSameRowAreJoinedOnlyWhenGapIsWithinSixPercent() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Gap is", minX: 0.08, minY: 0.3, width: 0.2),
            textLine(text: "5 percent", minX: 0.33, minY: 0.3, width: 0.2),
            textLine(text: "Gap is", minX: 0.08, minY: 0.5, width: 0.2),
            textLine(text: "7 percent", minX: 0.35, minY: 0.502, width: 0.2),
        ]).map(\.text) == ["Gap is 5 percent", "Gap is", "7 percent"]
    )
}

/// すぐ右にあっても、上下の中心が行の高さの 4 割ずれた行はつなぎ、6 割ずれた行はつながず別の発言にすること
/// (上下の中心のずれの境界 0.5 の両側。行の高さは 0.02)
@Test func adjacentLinesAreJoinedOnlyWhenVerticalCentersAreWithinHalfLineHeight() {
    #expect(
        extractMessages(lines: [
            textLine(text: "Offset is", minX: 0.08, minY: 0.3, width: 0.2),
            textLine(text: "40 percent", minX: 0.3, minY: 0.308, width: 0.2),
            textLine(text: "Offset is", minX: 0.08, minY: 0.5, width: 0.2),
            textLine(text: "60 percent", minX: 0.3, minY: 0.512, width: 0.2),
        ]).map(\.text) == ["Offset is 40 percent", "Offset is", "60 percent"]
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
