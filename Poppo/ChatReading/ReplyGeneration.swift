import Foundation
import FoundationModels
// Claude をつなぐ package (ClaudeForFoundationModels) は iOS 27 の SDK (Swift 6.4 以降) でしかコンパイルできないため、
// 同じ条件でだけ依存に入れる PoppoClaude (Packages/PoppoClaude/Package.swift) を通して、下の #if と同じ条件で読み込む
#if compiler(>=6.4)
import DeviceCheck
import PoppoClaude
#endif

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

/// 返信の文を作るモデルへの指示の文。どのモデルでも同じ文を使う。
/// 「The replies are suggestions」から後ろの 3 つの文は、モデルが知らないこと (利用者の住所など) を聞かれた会話で、
/// 作り物の答えや `[Adresse]` のような埋めていない枠を返信の文に書かせないためのもの
/// (文を選んだ経緯と測った結果: documents/evaluation/2026-11-28-reply-instructions-unknown-facts.md)
let replyInstructions = """
    You help a person reply in a chat. The chat is listed from oldest to newest. \
    Lines starting with "Me:" were written by the person you help. \
    Lines starting with "Them:" were written by other people. \
    Write replies that the person could send next in response to the latest "Them:" lines. \
    Write every reply in the same language as the "Them:" lines. \
    The replies are suggestions on the person's keyboard: tapping one sends it exactly as written. \
    Yes-or-no questions, including whether the person is free or willing, are decided by the person choosing a reply, \
    so offer both answers. \
    For anything else that only the person knows, do not write it or a blank for it; \
    the person will type it themselves, so suggest replies that work without it.
    """

/// 返信の文を作るモデルへの指示の文。chatPartnerRelationship は、利用者が選んだ相手との関係 (nil は未選択)。
/// 未選択の時は replyInstructions をそのまま返し、関係を選んだ時は、その関係と合う口調を求める文を後ろに足す。どのモデルでも同じ文を使う
func replyInstructions(chatPartnerRelationship: ChatPartnerRelationship?) -> String {
    switch chatPartnerRelationship {
    case nil:
        replyInstructions
    case .friendOrFamily:
        replyInstructions + "\nThe other people are the person's friends or family. Write the replies in a casual, friendly tone."
    case .coworker:
        replyInstructions + "\nThe other people are the person's coworkers. Write the replies in a friendly but professional tone."
    case .superiorOrClient:
        replyInstructions
            + "\nThe other people are the person's superiors or business clients. Write the replies in a polite, respectful tone."
    case .stranger:
        replyInstructions
            + "\nThe person is talking with the other people for the first time. Write the replies in a polite tone."
    }
}

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

/// Claude の API を App Attest で使うための client ID。owner が Claude Console の app integration (Team ID と bundle ID の登録) で作った値。
/// API キーではなく、公開してよい設定の値 (package の README: 「The client ID it issues is public configuration that is safe to include
/// in the app binary.」 https://github.com/anthropics/ClaudeForFoundationModels )
private let claudeAppAttestClientID = "clid_01CC3t6y8WKskisGqkiMy9o1"

/// 返信案を作る Claude のモデル。Claude の値段の表で最も安い現行のモデル (Claude Haiku 5.5。10 万トークン以下の要求で
/// 入力 $0.10・出力 $0.50。100 万トークンあたり。https://platform.claude.com/docs/en/about-claude/pricing を 2026-11-21 に読んだ値)
private let claudeModel = ClaudeModel.haiku5_5

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
    case .claude:
        ClaudeLanguageModel(name: claudeModel, auth: .appAttest(clientID: claudeAppAttestClientID))
    }
}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す
func canGenerateReplies(replyModel: ReplyModel) -> Bool {
    canGenerateReplies(
        replyModel: replyModel,
        apiKeyKeychainService: replyModelAPIKeyKeychainService,
        isAppAttestSupported: DCAppAttestService.shared.isSupported
    )
}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す。
/// apiKeyKeychainService は、API キーが要るモデルのキーを保存してある Keychain の service。
/// isAppAttestSupported は、この端末が App Attest を使えるか (simulator では使えない)。
/// API キーが要るモデルは、キーを保存していて今読める時だけ、App Attest で認証するモデルは、isAppAttestSupported が true の時だけ true を返す
func canGenerateReplies(replyModel: ReplyModel, apiKeyKeychainService: String, isAppAttestSupported: Bool) -> Bool {
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
    case is ClaudeLanguageModel:
        isAppAttestSupported
    default:
        // 使えるかを聞けない型のモデルでは作らない: 使えるか分からないモデルで生成を試して、失敗の理由が診断の記録に残らなくなるのを避けるため
        false
    }
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で、chatPartnerRelationship (相手との関係。nil は未選択) に合う口調で作る。
/// モデルが使えない端末・状態では失敗するため、呼ぶ前に canGenerateReplies(replyModel:) を確かめる。
/// Private Cloud Compute では Apple の、OpenAI では OpenAI の、Gemini では Google の、Claude では Anthropic のサーバーへ、messages の発言が送られる
func generateReplyTexts(
    messages: [ExtractedMessage],
    replyModel: ReplyModel,
    chatPartnerRelationship: ChatPartnerRelationship?
) async throws -> [String] {
    try await generateReplyTexts(
        messages: messages,
        replyModel: replyModel,
        chatPartnerRelationship: chatPartnerRelationship,
        apiKeyKeychainService: replyModelAPIKeyKeychainService
    )
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で、chatPartnerRelationship (相手との関係。nil は未選択) に合う口調で作る。
/// apiKeyKeychainService は、API キーが要るモデルのキーを保存してある Keychain の service。
/// 端末の外へ送るモデル (sendsMessagesOutsideDevice(replyModel:) が true) では、messages の発言がそのモデルの提供元のサーバーへ送られる
func generateReplyTexts(
    messages: [ExtractedMessage],
    replyModel: ReplyModel,
    chatPartnerRelationship: ChatPartnerRelationship?,
    apiKeyKeychainService: String
) async throws -> [String] {
    try await generateReplyTexts(
        messages: messages,
        chatPartnerRelationship: chatPartnerRelationship,
        languageModel: languageModel(replyModel: replyModel, apiKeyKeychainService: apiKeyKeychainService)
    )
}

/// languageModel (Foundation Models の LanguageModel に準拠したモデル) で、会話に続けて利用者が送れる返信の文を、相手の言語で、
/// chatPartnerRelationship (相手との関係。nil は未選択) に合う口調で作る。
/// モデルへの指示の文と、出力の形 (GeneratedReplyTexts) は、どのモデルでも同じ
private func generateReplyTexts(
    messages: [ExtractedMessage],
    chatPartnerRelationship: ChatPartnerRelationship?,
    languageModel: some LanguageModel
) async throws -> [String] {
    try await LanguageModelSession(model: languageModel, instructions: replyInstructions(chatPartnerRelationship: chatPartnerRelationship))
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
    case .privateCloudCompute, .openAI, .gemini, .claude:
        false
    }
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で、chatPartnerRelationship (相手との関係。nil は未選択) に合う口調で作る。
/// この SDK には LanguageModel プロトコルが無いため、端末内のモデルのほかでは ReplyModelNotInSDKError を投げる (端末内のモデルへは切り替えない)
func generateReplyTexts(
    messages: [ExtractedMessage],
    replyModel: ReplyModel,
    chatPartnerRelationship: ChatPartnerRelationship?
) async throws -> [String] {
    switch replyModel {
    case .onDevice:
        try await LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: replyInstructions(chatPartnerRelationship: chatPartnerRelationship)
        )
        .respond(to: replyPrompt(messages: messages), generating: GeneratedReplyTexts.self)
        .content
        .texts
    case .privateCloudCompute, .openAI, .gemini, .claude:
        throw ReplyModelNotInSDKError()
    }
}
#endif
