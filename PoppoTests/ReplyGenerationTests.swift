import FoundationModels
import Testing
@testable import Poppo

/// 端末内は Foundation Models の端末内のモデル (SystemLanguageModel) を、Private Cloud Compute は
/// Apple のサーバーで動くモデル (PrivateCloudComputeLanguageModel) を指すこと。
/// 取り違えると、端末内を選んだのに発言を端末の外へ送る
@Test func languageModelMatchesReplyModel() {
    #expect(languageModel(replyModel: .onDevice) is SystemLanguageModel)
    #expect(languageModel(replyModel: .onDevice) is PrivateCloudComputeLanguageModel == false)
    #expect(languageModel(replyModel: .privateCloudCompute) is PrivateCloudComputeLanguageModel)
    #expect(languageModel(replyModel: .privateCloudCompute) is SystemLanguageModel == false)
}

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
