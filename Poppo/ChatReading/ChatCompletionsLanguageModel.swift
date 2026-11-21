import Foundation
import FoundationModels

// Foundation Models の LanguageModel プロトコルは iOS 27 の SDK (Xcode 27。Swift 6.4 以降) にしか無いため、コンパイラの版で分ける
// (理由は ReplyGeneration.swift の同じ分け方のコメント)
#if compiler(>=6.4)
/// Chat Completions の形の API (`{接続先}/chat/completions`) で動くモデル。OpenAI と、Gemini の OpenAI 互換の接続先で共有する。
/// Foundation Models の LanguageModelSession に渡して使う。提供元ごとの違いは、接続先・モデルの名前・API キーの 3 つだけ。
/// API キーの値はこの型に持たず、要求を送る時に Keychain から読む
nonisolated struct ChatCompletionsLanguageModel: LanguageModel, Hashable {
    /// 接続先。この後ろに `chat/completions` を付けた URL へ要求を送る
    let baseURL: URL
    /// 提供元でのモデルの名前 (要求の `model` に入れる値)
    let modelName: String
    /// API キーを保存してある返信案を作るモデル (Keychain の account)
    let apiKeyReplyModel: ReplyModel
    /// API キーを保存してある Keychain の service
    let apiKeyKeychainService: String

    /// このモデルでできること。出力の形の指定 (@Generable の型での生成) だけで、画像・tool の呼び出し・推論の表示は使わない
    var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    /// 実行側 (Executor) を作る時に渡す設定。接続先・モデルの名前・API キーの置き場所が同じなら同じ実行側を使えるため、自分自身を渡す
    var executorConfiguration: ChatCompletionsLanguageModel {
        self
    }

    /// ChatCompletionsLanguageModel への要求を、Chat Completions の API へ送って応答を返す実行側
    nonisolated struct Executor: LanguageModelExecutor {
        /// 実行側を作る。自動で作られる init は引数が無く、LanguageModelExecutor が求める init(configuration:) にならないため書く。
        /// 要求に使う値は respond の model から読むため、configuration は持たない
        init(configuration: ChatCompletionsLanguageModel) {}

        /// request の会話と出力の形を model の接続先へ送り、返った文を channel へ流す。
        /// request.transcript の発言と指示の文が、model の接続先 (端末の外) へ送られる。
        /// API キーを保存していない時・提供元が 200 番台以外を返した時・応答に文が無い時は ChatCompletionsError を投げる
        nonisolated(nonsending) func respond(
            to request: LanguageModelExecutorGenerationRequest,
            model: ChatCompletionsLanguageModel,
            streamingInto channel: LanguageModelExecutorGenerationChannel
        ) async throws {
            guard let apiKey = try loadAPIKey(replyModel: model.apiKeyReplyModel, keychainService: model.apiKeyKeychainService) else {
                throw ChatCompletionsError.missingAPIKey
            }
            var urlRequest = URLRequest(url: model.baseURL.appending(path: "chat/completions"))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = try chatCompletionsRequestBody(request: request, modelName: model.modelName)
            let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
            guard let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode, (200..<300).contains(statusCode) else {
                throw ChatCompletionsError.unexpectedStatus(statusCode: (urlResponse as? HTTPURLResponse)?.statusCode)
            }
            guard let content = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data).choices.first?.message.content else {
                throw ChatCompletionsError.noContent
            }
            // tokenCount は 0: 使ったトークンの数をこのアプリは読まないため (LanguageModelSession の usage を使っていない)
            await channel.send(.response(action: .appendText(content, tokenCount: 0)))
        }
    }
}

/// Chat Completions の API で返信案を作れなかった理由。どの値も、API キーと、画面から読んだ文字を持たない
nonisolated enum ChatCompletionsError: Error, Equatable, LocalizedError {
    /// API キーを保存していない
    case missingAPIKey
    /// 提供元が 200 番台以外を返した。statusCode は HTTP の status code (HTTP の応答でなかった時は nil)
    case unexpectedStatus(statusCode: Int?)
    /// 応答に返信の文が無い
    case noContent

    /// 診断の記録に書く、失敗の説明 (英語。API キーと応答の本文を持たない)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "API key is not saved"
        case .unexpectedStatus(let statusCode):
            // 応答の本文は足さない: OpenAI は API キーが違う時の本文に、送ったキーの一部を入れるため
            "HTTP status \(statusCode.map { String($0) } ?? "unknown")"
        case .noContent:
            "Response has no content"
        }
    }
}

/// Chat Completions の API の応答のうち、このアプリが読む部分
private nonisolated struct ChatCompletionsResponse: Decodable {
    /// モデルが作った応答の候補。先頭の 1 つだけを使う
    let choices: [Choice]

    /// 応答の候補 1 つ
    nonisolated struct Choice: Decodable {
        /// モデルが書いた発言
        let message: Message
    }

    /// モデルが書いた発言
    nonisolated struct Message: Decodable {
        /// 発言の文。出力の形を指定した要求では、その形の JSON。モデルが答えなかった時は nil
        let content: String?
    }
}

/// request (Foundation Models が実行側に渡す要求) を、Chat Completions の API へ送る本文の JSON にして返す。
/// modelName は提供元でのモデルの名前。会話は `messages` に、出力の形 (request.schema) がある時は `response_format` の JSON schema に入れる
nonisolated func chatCompletionsRequestBody(request: LanguageModelExecutorGenerationRequest, modelName: String) throws -> Data {
    var body: [String: Any] = [
        "model": modelName,
        "messages": chatCompletionsMessages(transcript: request.transcript),
    ]
    if let schema = request.schema {
        body["response_format"] =
            [
                "type": "json_schema",
                "json_schema": [
                    "name": schema.name,
                    "strict": true,
                    "schema": removingVendorExtensionKeys(jsonSchema: try JSONSerialization.jsonObject(with: JSONEncoder().encode(schema))),
                ] as [String: Any],
            ] as [String: Any]
    }
    return try JSONSerialization.data(withJSONObject: body)
}

/// transcript (Foundation Models の会話の記録) を、Chat Completions の API の `messages` の並びにして返す。
/// 指示は system、利用者からの文は user、モデルの応答は assistant の発言にする。文でない部分 (画像・tool の呼び出しなど) は入れない
/// (ChatCompletionsLanguageModel は出力の形の指定だけを使うと宣言しているため)
private nonisolated func chatCompletionsMessages(transcript: Transcript) -> [[String: String]] {
    transcript.compactMap { entry in
        switch entry {
        case .instructions(let instructions):
            ["role": "system", "content": joinedText(segments: instructions.segments)]
        case .prompt(let prompt):
            ["role": "user", "content": joinedText(segments: prompt.segments)]
        case .response(let response):
            ["role": "assistant", "content": joinedText(segments: response.segments)]
        default:
            nil
        }
    }
}

/// segments (会話の記録の 1 つの発言の中身) のうち、文の部分を順につないで返す
private nonisolated func joinedText(segments: [Transcript.Segment]) -> String {
    segments.compactMap { segment in
        if case .text(let textSegment) = segment {
            textSegment.content
        } else {
            nil
        }
    }.joined()
}

/// jsonSchema (JSONSerialization の値で表した JSON schema) から、名前が `x-` で始まるキーワードを取り除いて返す。
/// Foundation Models の GenerationSchema は JSON にすると、JSON schema に無い `x-order` (プロパティの順) を含む
/// (macOS 27 で GeneratedReplyTexts の schema を JSON にした実測。https://github.com/bannzai/poppo/issues/39 の PR の本文)。
/// 提供元には JSON schema のキーワードだけを送る (OpenAI は受け取れない schema にエラーを返す。`x-order` を受け取るかは確かめていない)。
/// プロパティの名前 (`properties`・`$defs` の直下のキー) は `x-` で始まっても残す
nonisolated func removingVendorExtensionKeys(jsonSchema: Any) -> Any {
    switch jsonSchema {
    case let dictionary as [String: Any]:
        return dictionary.filter { !$0.key.hasPrefix("x-") }.reduce(into: [String: Any]()) { result, keyword in
            if ["properties", "$defs"].contains(keyword.key), let namedSchemas = keyword.value as? [String: Any] {
                result[keyword.key] = namedSchemas.mapValues { removingVendorExtensionKeys(jsonSchema: $0) }
            } else {
                result[keyword.key] = removingVendorExtensionKeys(jsonSchema: keyword.value)
            }
        }
    case let array as [Any]:
        return array.map { removingVendorExtensionKeys(jsonSchema: $0) }
    default:
        return jsonSchema
    }
}
#endif
