import Foundation
import FoundationModels
import PoppoClaude
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

/// Claude は、Anthropic の API の接続先と Claude Haiku 5.5 を指し、owner が作った client ID の App Attest で認証すること (API キーを使わない)。
/// 取り違えると、別の workspace に請求が行くか、高いモデルで作る
@Test func languageModelForClaudeAuthenticatesByAppAttestWithClientID() throws {
    let claudeLanguageModel = try #require(
        languageModel(replyModel: .claude, apiKeyKeychainService: "unused") as? ClaudeLanguageModel
    )

    #expect(claudeLanguageModel.executorConfiguration.authMode == .appAttest(clientID: "clid_01CC3t6y8WKskisGqkiMy9o1"))
    #expect(claudeLanguageModel.model == .haiku5_5)
    #expect(claudeLanguageModel.baseURL == URL(string: "https://api.anthropic.com"))
    #expect(claudeLanguageModel.userProfileID == nil)
}

/// Claude は、端末が App Attest を使える時だけ返信案を作れると答えること (simulator は使えないので、作れないと答える)。
/// App Attest を使えることは、API キーが要るモデル (キーを保存していない OpenAI・Gemini) を作れると答える理由にならないこと
@Test func claudeCanGenerateRepliesOnlyWhenAppAttestIsSupported() {
    #expect(canGenerateReplies(replyModel: .claude, apiKeyKeychainService: "unused", isAppAttestSupported: false) == false)
    #expect(canGenerateReplies(replyModel: .claude, apiKeyKeychainService: "unused", isAppAttestSupported: true) == true)
    #expect(
        canGenerateReplies(
            replyModel: .openAI,
            apiKeyKeychainService: "ReplyGenerationTests-\(UUID().uuidString)",
            isAppAttestSupported: true
        ) == false
    )
    #expect(
        canGenerateReplies(
            replyModel: .gemini,
            apiKeyKeychainService: "ReplyGenerationTests-\(UUID().uuidString)",
            isAppAttestSupported: true
        ) == false
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

/// 相手との関係が未選択の時は、モデルへの指示の文が、関係を選べるようにする前と同じ文 (replyInstructions) のままであること
@Test func replyInstructionsWithoutRelationshipAreUnchanged() {
    #expect(
        replyInstructions(chatPartnerRelationship: nil)
            == """
            You help a person reply in a chat. The chat is listed from oldest to newest. \
            Lines starting with "Me:" were written by the person you help. \
            Lines starting with "Them:" were written by other people. \
            Write replies that the person could send next in response to the latest "Them:" lines. \
            Write every reply in the same language as the "Them:" lines.
            """
    )
}

/// 相手との関係を選んだ時は、関係を選ばない時の指示の文に続けて、その関係と、関係に合う口調を求める文が入ること
@Test(arguments: [
    (ChatPartnerRelationship.friendOrFamily, "friends or family", "casual"),
    (.coworker, "coworkers", "friendly but professional"),
    (.superiorOrClient, "superiors or business clients", "polite, respectful"),
    (.stranger, "for the first time", "polite"),
])
func replyInstructionsWithRelationshipNameRelationshipAndTone(
    chatPartnerRelationship: ChatPartnerRelationship,
    relationshipText: String,
    toneText: String
) {
    let instructions = replyInstructions(chatPartnerRelationship: chatPartnerRelationship)

    #expect(instructions.hasPrefix(replyInstructions(chatPartnerRelationship: nil) + "\n"))
    #expect(instructions.contains(relationshipText))
    #expect(instructions.contains("Write the replies in a \(toneText)"))
}

/// 関係ごとの指示の文はどれも違うこと (別の関係を選んでも同じ口調の返信案にならないようにする)
@Test func replyInstructionsDifferForEachRelationship() {
    #expect(
        Set(([nil] + ChatPartnerRelationship.allCases).map { replyInstructions(chatPartnerRelationship: $0) }).count
            == ChatPartnerRelationship.allCases.count + 1
    )
}

/// 発言が無い時は、会話の文が空になること
@Test func replyPromptIsEmptyWithoutMessages() {
    #expect(replyPrompt(messages: []) == "")
}
