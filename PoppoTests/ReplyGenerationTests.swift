import Foundation
import FoundationModels
import Testing
@testable import Poppo

/// 端末内は Foundation Models の端末内のモデル (SystemLanguageModel) を、Private Cloud Compute は
/// Apple のサーバーで動くモデル (PrivateCloudComputeLanguageModel) を指すこと。
/// 取り違えると、端末内を選んだのに発言を端末の外へ送る
@Test func languageModelMatchesReplyModel() {
    #expect(languageModel(replyModel: .onDevice, apiKeyKeychainService: "unused") is SystemLanguageModel)
    #expect(languageModel(replyModel: .onDevice, apiKeyKeychainService: "unused") is PrivateCloudComputeLanguageModel == false)
    #expect(languageModel(replyModel: .privateCloudCompute, apiKeyKeychainService: "unused") is PrivateCloudComputeLanguageModel)
    #expect(languageModel(replyModel: .privateCloudCompute, apiKeyKeychainService: "unused") is SystemLanguageModel == false)
}

/// OpenAI は OpenAI の接続先とモデルを、Gemini は Gemini の OpenAI 互換の接続先とモデルを指し、API キーはそれぞれ自分のモデルの分を、
/// 渡した Keychain の service から読むこと。取り違えると、選んだ提供元と違う提供元へ発言とキーを送る
@Test func languageModelForOpenAIAndGeminiPointsAtOwnEndpointModelAndAPIKey() throws {
    #expect(
        languageModel(replyModel: .openAI, apiKeyKeychainService: "service-a") as? ChatCompletionsLanguageModel
            == ChatCompletionsLanguageModel(
                baseURL: try #require(URL(string: "https://api.openai.com/v1")),
                modelName: "gpt-6-luna",
                apiKeyReplyModel: .openAI,
                apiKeyKeychainService: "service-a"
            )
    )
    #expect(
        languageModel(replyModel: .gemini, apiKeyKeychainService: "service-b") as? ChatCompletionsLanguageModel
            == ChatCompletionsLanguageModel(
                baseURL: try #require(URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")),
                modelName: "gemini-3.5-flash-lite",
                apiKeyReplyModel: .gemini,
                apiKeyKeychainService: "service-b"
            )
    )
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
