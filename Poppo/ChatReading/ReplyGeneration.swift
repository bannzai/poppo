import Foundation
import FoundationModels

/// 返信案を作るモデルに書かせる返信の文の組。モデルの出力をこの形に絞るために使う
@Generable
nonisolated struct GeneratedReplyTexts {
    /// 返信の文。3 つにするのは、画面を長くせずに読み比べられる数にするため
    /// (主要画面のモックの案 https://github.com/bannzai/poppo/pull/9 の読み取り結果の画面と同じ数)
    @Guide(description: "Three short replies the person could send next. Each reply differs in content or tone", .count(3))
    var texts: [String]
}

/// 返信の文を作るモデルに渡す会話の文。
/// 発言を画面の上から下の順に、利用者自身の発言には「Me:」、相手の発言には「Them:」を付けて並べる
nonisolated func replyPrompt(messages: [ExtractedMessage]) -> String {
    messages.map { ($0.isFromUser ? "Me: " : "Them: ") + $0.text }.joined(separator: "\n\n")
}

/// 返信の文を作るモデルへの指示の文。どのモデルでも同じ文を使う
let replyInstructions = """
    You help a person reply in a chat. The chat is listed from oldest to newest. \
    Lines starting with "Me:" were written by the person you help. \
    Lines starting with "Them:" were written by other people. \
    Write replies that the person could send next in response to the latest "Them:" lines. \
    Write every reply in the same language as the "Them:" lines.
    """

// Foundation Models の LanguageModel プロトコルと PrivateCloudComputeLanguageModel は iOS 27 の SDK (Xcode 27。Swift 6.4 以降) にしか無い。
// CodeQL の Swift の解析 (.github/workflows/codeql.yml) は Xcode 26 (Swift 6.3) でアプリをビルドするため、
// コンパイラの版で分ける (Xcode 26.6 のビルドの実測: 「cannot find type 'LanguageModel' in scope」
// https://github.com/bannzai/poppo/actions/runs/44748277599 )。配るビルドとテストは Xcode 27 で作るため、#else の側は配らない
#if compiler(>=6.4)
/// OpenAI の API の接続先
private let openAIBaseURL = URL(string: "https://api.openai.com/v1")!

/// 返信案を作る OpenAI のモデルの名前。OpenAI の値段の表で、廃止の予定が無いモデルのうち最も安いもの
/// (入力 $0.10・出力 $0.50。100 万トークンあたり。https://developers.openai.com/api/docs/pricing を 2026-11-21 に読んだ値。
/// 表でこれより安い gpt-5-nano は 2026-12-11 に止まる予定で、置き換え先がこのモデル: https://developers.openai.com/api/docs/deprecations )
private let openAIModelName = "gpt-6-luna"

/// Gemini API の、OpenAI 互換の接続先 ( https://ai.google.dev/gemini-api/docs/openai )
private let geminiBaseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!

/// 返信案を作る Gemini のモデルの名前。Gemini の値段の表で最も安い現行のモデル
/// (入力 $0.30・出力 $2.50。100 万トークンあたり。https://ai.google.dev/gemini-api/docs/pricing を 2026-11-20 に読んだ値)
private let geminiModelName = "gemini-3.5-flash-lite"

/// replyModel が指す Foundation Models のモデルを返す。モデルの種類と Foundation Models の型の対応は、この関数だけに置く。
/// apiKeyKeychainService は、API キーが要るモデルのキーを保存してある Keychain の service
func languageModel(replyModel: ReplyModel, apiKeyKeychainService: String) -> any LanguageModel {
    switch replyModel {
    case .onDevice:
        SystemLanguageModel.default
    case .privateCloudCompute:
        PrivateCloudComputeLanguageModel()
    case .openAI:
        ChatCompletionsLanguageModel(
            baseURL: openAIBaseURL,
            modelName: openAIModelName,
            apiKeyReplyModel: replyModel,
            apiKeyKeychainService: apiKeyKeychainService
        )
    case .gemini:
        ChatCompletionsLanguageModel(
            baseURL: geminiBaseURL,
            modelName: geminiModelName,
            apiKeyReplyModel: replyModel,
            apiKeyKeychainService: apiKeyKeychainService
        )
    }
}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す
func canGenerateReplies(replyModel: ReplyModel) -> Bool {
    canGenerateReplies(replyModel: replyModel, apiKeyKeychainService: replyModelAPIKeyKeychainService)
}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す。
/// apiKeyKeychainService は、API キーが要るモデルのキーを保存してある Keychain の service。
/// API キーが要るモデルは、キーを保存していて今読める時だけ true を返す
func canGenerateReplies(replyModel: ReplyModel, apiKeyKeychainService: String) -> Bool {
    // 使えるか (isAvailable) は LanguageModel プロトコルの要件に無く、型ごとに持つため、型で分けて聞く
    switch languageModel(replyModel: replyModel, apiKeyKeychainService: apiKeyKeychainService) {
    case let systemLanguageModel as SystemLanguageModel:
        systemLanguageModel.isAvailable
    case let privateCloudComputeLanguageModel as PrivateCloudComputeLanguageModel:
        privateCloudComputeLanguageModel.isAvailable
    case let chatCompletionsLanguageModel as ChatCompletionsLanguageModel:
        (try? loadAPIKey(
            replyModel: chatCompletionsLanguageModel.apiKeyReplyModel,
            keychainService: chatCompletionsLanguageModel.apiKeyKeychainService
        )) != nil
    default:
        // 使えるかを聞けない型のモデルでは作らない: 使えるか分からないモデルで生成を試して、失敗の理由が診断の記録に残らなくなるのを避けるため
        false
    }
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// モデルが使えない端末・状態では失敗するため、呼ぶ前に canGenerateReplies(replyModel:) を確かめる。
/// Private Cloud Compute では Apple の、OpenAI では OpenAI の、Gemini では Google のサーバーへ、messages の発言が送られる
func generateReplyTexts(messages: [ExtractedMessage], replyModel: ReplyModel) async throws -> [String] {
    try await generateReplyTexts(messages: messages, replyModel: replyModel, apiKeyKeychainService: replyModelAPIKeyKeychainService)
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// apiKeyKeychainService は、API キーが要るモデルのキーを保存してある Keychain の service。
/// 端末の外へ送るモデル (sendsMessagesOutsideDevice(replyModel:) が true) では、messages の発言がそのモデルの提供元のサーバーへ送られる
func generateReplyTexts(messages: [ExtractedMessage], replyModel: ReplyModel, apiKeyKeychainService: String) async throws -> [String] {
    try await generateReplyTexts(
        messages: messages,
        languageModel: languageModel(replyModel: replyModel, apiKeyKeychainService: apiKeyKeychainService)
    )
}

/// languageModel (Foundation Models の LanguageModel に準拠したモデル) で、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// モデルへの指示の文と、出力の形 (GeneratedReplyTexts) は、どのモデルでも同じ
private func generateReplyTexts(messages: [ExtractedMessage], languageModel: some LanguageModel) async throws -> [String] {
    try await LanguageModelSession(model: languageModel, instructions: replyInstructions)
        .respond(to: replyPrompt(messages: messages), generating: GeneratedReplyTexts.self)
        .content
        .texts
}
#else
/// 端末内のモデルしか持たない SDK (LanguageModel プロトコルが無い SDK) でビルドした時に、ほかのモデルでの生成を求められたことを表すエラー
struct ReplyModelNotInSDKError: Error {}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す。
/// この SDK には LanguageModel プロトコルが無いため、端末内のモデルのほかは使えないと答える (端末内のモデルへは切り替えない)
func canGenerateReplies(replyModel: ReplyModel) -> Bool {
    switch replyModel {
    case .onDevice:
        SystemLanguageModel.default.isAvailable
    case .privateCloudCompute, .openAI, .gemini:
        false
    }
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// この SDK には LanguageModel プロトコルが無いため、端末内のモデルのほかでは ReplyModelNotInSDKError を投げる (端末内のモデルへは切り替えない)
func generateReplyTexts(messages: [ExtractedMessage], replyModel: ReplyModel) async throws -> [String] {
    switch replyModel {
    case .onDevice:
        try await LanguageModelSession(model: SystemLanguageModel.default, instructions: replyInstructions)
            .respond(to: replyPrompt(messages: messages), generating: GeneratedReplyTexts.self)
            .content
            .texts
    case .privateCloudCompute, .openAI, .gemini:
        throw ReplyModelNotInSDKError()
    }
}
#endif
