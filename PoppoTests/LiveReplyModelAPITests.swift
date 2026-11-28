import Foundation
import Testing
@testable import Poppo

/// 提供元の実際の API を呼ぶテストで使う、モデルごとの API キーの環境変数の名前を返す。API キーが要らないモデルは nil を返す
/// (名前は .env.1password.github-actions の宣言と、.github/workflows/verify-reply-model-apis.yml が渡す名前と同じ)
private nonisolated func liveAPIKeyEnvironmentName(replyModel: ReplyModel) -> String? {
    switch replyModel {
    case .openAI:
        "OPENAI_API_KEY"
    case .gemini:
        "GEMINI_API_KEY"
    case .onDevice, .privateCloudCompute, .claude:
        nil
    }
}

/// environment (環境変数の名前と値) に replyModel の API キーが入っていればその値を、入っていない時は nil を返す。
/// 空文字は入っていない扱いにする (GitHub Actions は、登録していない Secret を空文字で渡すため)
private nonisolated func liveAPIKey(replyModel: ReplyModel, environment: [String: String]) -> String? {
    liveAPIKeyEnvironmentName(replyModel: replyModel)
        .flatMap { environment[$0] }
        .flatMap { $0.isEmpty ? nil : $0 }
}

/// environment (環境変数の名前と値) に、OpenAI と Gemini の両方の API キーが入っているかを返す。
/// 実際の API を呼ぶテストは、両方がある時だけ動かす (片方だけで動かすと、もう片方のモデルのテストがキーなしで落ちるため)
private nonisolated func hasLiveAPIKeys(environment: [String: String]) -> Bool {
    liveAPIKey(replyModel: .openAI, environment: environment) != nil && liveAPIKey(replyModel: .gemini, environment: environment) != nil
}

/// 誤ったキーのテストで保存する、どの提供元のキーでもない文字列
private nonisolated let wrongAPIKey = "poppo-live-test-wrong-key"

/// 実際の API を呼ぶテストを動かす条件: 両方のキーが空でなく入っている時だけ動かし、片方だけ・空文字・未設定では動かさないこと
@Test func liveAPITestsRunOnlyWithBothNonEmptyKeys() {
    #expect(hasLiveAPIKeys(environment: ["OPENAI_API_KEY": "a", "GEMINI_API_KEY": "b"]) == true)
    #expect(hasLiveAPIKeys(environment: ["OPENAI_API_KEY": "a"]) == false)
    #expect(hasLiveAPIKeys(environment: ["GEMINI_API_KEY": "b"]) == false)
    #expect(hasLiveAPIKeys(environment: ["OPENAI_API_KEY": "a", "GEMINI_API_KEY": ""]) == false)
    #expect(hasLiveAPIKeys(environment: ["OPENAI_API_KEY": "", "GEMINI_API_KEY": "b"]) == false)
    #expect(hasLiveAPIKeys(environment: [:]) == false)
}

/// OpenAI と Gemini の実際の API を呼んで、返信案を作る経路を端から端まで確かめるテスト。
/// 費用がかかり、API キーが要るため、環境変数に OpenAI と Gemini の両方のキーがある時だけ動く
/// (手動で起動する .github/workflows/verify-reply-model-apis.yml だけがキーを渡す。PR の CI では動かない)
@Suite(.serialized, .enabled(if: hasLiveAPIKeys(environment: ProcessInfo.processInfo.environment)))
struct LiveReplyModelAPITests {
    /// API キーを置く、このテストだけの Keychain の service
    private let keychainService = "LiveReplyModelAPITests-\(UUID().uuidString)"

    /// 保存した実際のキーで、提供元の API が要求 (会話と、返信の文 3 つの出力の形の指定) を受け取り、
    /// 空でない返信の文が 3 つ戻ること
    @Test(arguments: [ReplyModel.openAI, .gemini])
    func realAPIReturnsThreeReplyTexts(replyModel: ReplyModel) async throws {
        defer {
            try? deleteAPIKey(replyModel: replyModel, keychainService: keychainService)
        }
        try save(apiKey: try #require(liveAPIKey(replyModel: replyModel, environment: ProcessInfo.processInfo.environment)), replyModel: replyModel, keychainService: keychainService)

        let replyTexts = try await generateReplyTexts(
            messages: [
                ExtractedMessage(text: "Are you free for lunch tomorrow?", isFromUser: false),
                ExtractedMessage(text: "Let me check my schedule", isFromUser: true),
                ExtractedMessage(text: "Sure, no rush!", isFromUser: false),
            ],
            replyModel: replyModel,
            chatPartnerRelationship: nil,
            apiKeyKeychainService: keychainService
        )

        #expect(replyTexts.count == 3)
        #expect(replyTexts.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    /// 誤ったキーを保存すると、提供元が 400 番台の status を返し、診断の記録に書く文が status code を持ち、キーの値を持たないこと
    @Test(arguments: [ReplyModel.openAI, .gemini])
    func wrongAPIKeyThrowsClientErrorStatusWithoutAPIKey(replyModel: ReplyModel) async throws {
        defer {
            try? deleteAPIKey(replyModel: replyModel, keychainService: keychainService)
        }
        try save(apiKey: wrongAPIKey, replyModel: replyModel, keychainService: keychainService)

        let thrownError = try #require(
            await #expect(throws: ChatCompletionsError.self) {
                try await generateReplyTexts(
                    messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                    replyModel: replyModel,
                    chatPartnerRelationship: nil,
                    apiKeyKeychainService: keychainService
                )
            }
        )

        // 確かめた status code を実行記録に残す (提供元ごとに 400・401・403 のどれを返すかを、後から読めるようにする)
        print("LIVE_REPLY_MODEL_API wrongKey replyModel=\(replyModel.rawValue) failure=\(screenReadingFailureDescription(error: thrownError))")
        guard case .unexpectedStatus(let statusCode) = thrownError else {
            Issue.record("誤ったキーで、status のエラー以外になった: \(thrownError)")
            return
        }
        #expect((400..<500).contains(try #require(statusCode)))
        #expect(screenReadingFailureDescription(error: thrownError).contains(wrongAPIKey) == false)
    }
}
