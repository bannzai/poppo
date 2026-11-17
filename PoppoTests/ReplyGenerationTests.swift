import Testing
@testable import Poppo

/// 返信の文を作るモデルに渡す会話の文では、発言を渡した順に並べ、利用者自身の発言に「Me:」、相手の発言に「Them:」を付けること。
/// 自分の発言と相手の発言を、モデルが取り違えないようにする
@Test func replyPromptMarksEachMessageWithItsSpeaker() {
    #expect(
        replyPrompt(messages: [
            ExtractedMessage(text: "Are you free today?", isFromUser: false),
            ExtractedMessage(text: "Yes, after lunch", isFromUser: true),
            ExtractedMessage(text: "Great, see you then", isFromUser: false),
        ]) == "Them: Are you free today?\n\nMe: Yes, after lunch\n\nThem: Great, see you then"
    )
}

/// 発言が無い時は、会話の文が空になること
@Test func replyPromptIsEmptyWithoutMessages() {
    #expect(replyPrompt(messages: []) == "")
}
