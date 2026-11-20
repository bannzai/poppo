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

/// replyModel が指す Foundation Models のモデルを返す。モデルの種類と Foundation Models の型の対応は、この関数だけに置く
func languageModel(replyModel: ReplyModel) -> any LanguageModel {
    switch replyModel {
    case .onDevice:
        SystemLanguageModel.default
    case .privateCloudCompute:
        PrivateCloudComputeLanguageModel()
    }
}

/// replyModel のモデルで、今返信案を作れるか (モデルが使える端末・状態か) を返す
func canGenerateReplies(replyModel: ReplyModel) -> Bool {
    // 使えるか (isAvailable) は LanguageModel プロトコルの要件に無く、型ごとに持つため、型で分けて聞く
    switch languageModel(replyModel: replyModel) {
    case let systemLanguageModel as SystemLanguageModel:
        systemLanguageModel.isAvailable
    case let privateCloudComputeLanguageModel as PrivateCloudComputeLanguageModel:
        privateCloudComputeLanguageModel.isAvailable
    default:
        // 使えるかを聞けない型のモデルでは作らない: 使えるか分からないモデルで生成を試して、失敗の理由が診断の記録に残らなくなるのを避けるため
        false
    }
}

/// replyModel のモデルで、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// モデルが使えない端末・状態では失敗するため、呼ぶ前に canGenerateReplies(replyModel:) を確かめる。
/// Private Cloud Compute では、messages の発言が Apple のサーバーへ送られる
func generateReplyTexts(messages: [ExtractedMessage], replyModel: ReplyModel) async throws -> [String] {
    try await generateReplyTexts(messages: messages, languageModel: languageModel(replyModel: replyModel))
}

/// languageModel (Foundation Models の LanguageModel に準拠したモデル) で、会話に続けて利用者が送れる返信の文を、相手の言語で作る。
/// モデルへの指示の文と、出力の形 (GeneratedReplyTexts) は、どのモデルでも同じ
private func generateReplyTexts(messages: [ExtractedMessage], languageModel: some LanguageModel) async throws -> [String] {
    try await LanguageModelSession(
        model: languageModel,
        instructions: """
            You help a person reply in a chat. The chat is listed from oldest to newest. \
            Lines starting with "Me:" were written by the person you help. \
            Lines starting with "Them:" were written by other people. \
            Write replies that the person could send next in response to the latest "Them:" lines. \
            Write every reply in the same language as the "Them:" lines.
            """
    )
    .respond(to: replyPrompt(messages: messages), generating: GeneratedReplyTexts.self)
    .content
    .texts
}
