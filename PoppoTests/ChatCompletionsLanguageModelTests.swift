import Foundation
import FoundationModels
import Testing
@testable import Poppo

/// テストごとに別の、何も保存していない Keychain の service の名前を作って返す。
/// アプリが使う service (replyModelAPIKeyKeychainService) と、ほかのテストの API キーを混ぜないため
private func makeUnusedKeychainService() -> String {
    "ChatCompletionsLanguageModelTests-\(UUID().uuidString)"
}

/// 文だけの発言 1 つ分の中身 (会話の記録の segments) を作って返す
private func textSegments(content: String) -> [Transcript.Segment] {
    [.text(Transcript.TextSegment(content: content))]
}

/// transcript の会話と schema の出力の形を持つ、実行側への要求を作って返す。tool と生成の指定は使わないため空・既定にする
private func makeGenerationRequest(transcript: Transcript, schema: GenerationSchema?) -> LanguageModelExecutorGenerationRequest {
    LanguageModelExecutorGenerationRequest(
        id: UUID(),
        transcript: transcript,
        enabledTools: [],
        schema: schema,
        generationOptions: GenerationOptions(),
        contextOptions: ContextOptions(),
        metadata: [:]
    )
}

/// 保存していないモデルの API キーは nil で、保存すると同じ値を読めること。別のモデルのキーは保存した値と混ざらないこと
/// (混ざると、OpenAI のキーを Google へ送る)
@Test func savedAPIKeyIsLoadedOnlyForItsReplyModel() throws {
    let keychainService = makeUnusedKeychainService()
    defer {
        try? deleteAPIKey(replyModel: .openAI, keychainService: keychainService)
    }

    #expect(try loadAPIKey(replyModel: .openAI, keychainService: keychainService) == nil)

    try save(apiKey: "openai-key-1", replyModel: .openAI, keychainService: keychainService)

    #expect(try loadAPIKey(replyModel: .openAI, keychainService: keychainService) == "openai-key-1")
    #expect(try loadAPIKey(replyModel: .gemini, keychainService: keychainService) == nil)
}

/// 同じモデルにもう一度保存すると、前のキーが新しいキーで置き換わること (同じ保存を繰り返しても失敗しないこと)
@Test func savingAPIKeyAgainOverwritesPreviousKey() throws {
    let keychainService = makeUnusedKeychainService()
    defer {
        try? deleteAPIKey(replyModel: .gemini, keychainService: keychainService)
    }

    try save(apiKey: "gemini-key-1", replyModel: .gemini, keychainService: keychainService)
    try save(apiKey: "gemini-key-2", replyModel: .gemini, keychainService: keychainService)
    try save(apiKey: "gemini-key-2", replyModel: .gemini, keychainService: keychainService)

    #expect(try loadAPIKey(replyModel: .gemini, keychainService: keychainService) == "gemini-key-2")
}

/// 削除すると、そのモデルのキーだけが読めなくなり、別のモデルのキーは残ること。保存していないキーの削除と、削除の繰り返しは失敗しないこと
@Test func deletingAPIKeyRemovesOnlyItsReplyModelKey() throws {
    let keychainService = makeUnusedKeychainService()
    defer {
        try? deleteAPIKey(replyModel: .openAI, keychainService: keychainService)
        try? deleteAPIKey(replyModel: .gemini, keychainService: keychainService)
    }
    try save(apiKey: "openai-key", replyModel: .openAI, keychainService: keychainService)
    try save(apiKey: "gemini-key", replyModel: .gemini, keychainService: keychainService)

    try deleteAPIKey(replyModel: .openAI, keychainService: keychainService)
    try deleteAPIKey(replyModel: .openAI, keychainService: keychainService)

    #expect(try loadAPIKey(replyModel: .openAI, keychainService: keychainService) == nil)
    #expect(try loadAPIKey(replyModel: .gemini, keychainService: keychainService) == "gemini-key")
}

/// OpenAI と Gemini は、自分の API キーを保存している時だけ返信案を作れると答えること。
/// 別のモデルのキーだけを保存していても作れると答えない (キーが無いまま生成を試して失敗するのを避ける)
@Test func modelsUsingAPIKeyCanGenerateRepliesOnlyWithOwnSavedKey() throws {
    let keychainService = makeUnusedKeychainService()
    defer {
        try? deleteAPIKey(replyModel: .openAI, keychainService: keychainService)
    }

    #expect(canGenerateReplies(replyModel: .openAI, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == false)
    #expect(canGenerateReplies(replyModel: .gemini, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == false)

    try save(apiKey: "openai-key", replyModel: .openAI, keychainService: keychainService)

    #expect(canGenerateReplies(replyModel: .openAI, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == true)
    #expect(canGenerateReplies(replyModel: .gemini, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == false)
}

/// Gemini も、自分の API キーを保存すると返信案を作れると答え、消すと作れないと答えること。Gemini のキーだけでは OpenAI は作れないと答えること
@Test func geminiCanGenerateRepliesOnlyWhileOwnKeyIsSaved() throws {
    let keychainService = makeUnusedKeychainService()
    defer {
        try? deleteAPIKey(replyModel: .gemini, keychainService: keychainService)
    }

    try save(apiKey: "gemini-key", replyModel: .gemini, keychainService: keychainService)

    #expect(canGenerateReplies(replyModel: .gemini, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == true)
    #expect(canGenerateReplies(replyModel: .openAI, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == false)

    try deleteAPIKey(replyModel: .gemini, keychainService: keychainService)

    #expect(canGenerateReplies(replyModel: .gemini, apiKeyKeychainService: keychainService, isAppAttestSupported: false) == false)
}

/// API キーを保存していないモデルで返信案を作ろうとすると、提供元へ何も送らずに「API キーを保存していない」のエラーになること
@Test func respondingWithoutSavedAPIKeyThrowsMissingAPIKey() async throws {
    let model = ChatCompletionsLanguageModel(
        baseURL: try #require(URL(string: "https://example.invalid/v1")),
        modelName: "model-a",
        apiKeyReplyModel: .openAI,
        apiKeyKeychainService: makeUnusedKeychainService()
    )

    await #expect(throws: ChatCompletionsError.missingAPIKey) {
        try await ChatCompletionsLanguageModel.Executor(configuration: model).respond(
            to: makeGenerationRequest(transcript: Transcript(entries: []), schema: nil),
            model: model,
            streamingInto: LanguageModelExecutorGenerationChannel()
        )
    }
}

/// 要求の本文は、モデルの名前と、会話を順に並べた messages (指示は system、利用者からの文は user、モデルの応答は assistant) を持つこと。
/// 出力の形の指定が無い時は response_format を入れないこと
@Test func requestBodyHasModelNameAndMessagesInTranscriptOrder() throws {
    #expect(
        try JSONSerialization.jsonObject(
            with: chatCompletionsRequestBody(
                request: makeGenerationRequest(
                    transcript: Transcript(entries: [
                        .instructions(Transcript.Instructions(segments: textSegments(content: "Suggest replies"), toolDefinitions: [])),
                        .prompt(Transcript.Prompt(metadata: [:], segments: textSegments(content: "Them: Hello"))),
                        .response(Transcript.Response(segments: textSegments(content: "Hi"))),
                        .prompt(Transcript.Prompt(metadata: [:], segments: textSegments(content: "Them: Bye"))),
                    ]),
                    schema: nil
                ),
                modelName: "model-a"
            )
        ) as? NSDictionary == [
            "model": "model-a",
            "messages": [
                ["role": "system", "content": "Suggest replies"],
                ["role": "user", "content": "Them: Hello"],
                ["role": "assistant", "content": "Hi"],
                ["role": "user", "content": "Them: Bye"],
            ],
        ] as NSDictionary
    )
}

/// 1 つの発言が文を複数持つ時は順につなぎ、文でない部分 (構造を持つ部分) と、対象外の記録 (tool の出力) は messages に入れないこと
@Test func requestBodyJoinsTextSegmentsAndOmitsNonTextSegmentsAndOtherEntries() throws {
    #expect(
        try JSONSerialization.jsonObject(
            with: chatCompletionsRequestBody(
                request: makeGenerationRequest(
                    transcript: Transcript(entries: [
                        .prompt(
                            Transcript.Prompt(
                                metadata: [:],
                                segments: [
                                    .text(Transcript.TextSegment(content: "Them: Hel")),
                                    .structure(Transcript.StructuredSegment(schemaName: "Sample", content: GeneratedContent("not text"))),
                                    .text(Transcript.TextSegment(content: "lo")),
                                ]
                            )
                        ),
                        .toolOutput(
                            Transcript.ToolOutput(id: "tool-output", toolName: "lookup", segments: textSegments(content: "tool text"))
                        ),
                    ]),
                    schema: nil
                ),
                modelName: "model-a"
            )
        ) as? NSDictionary == [
            "model": "model-a",
            "messages": [
                ["role": "user", "content": "Them: Hello"]
            ],
        ] as NSDictionary
    )
}

/// 入力欄の文の前後の空白と改行は取り除き、途中の空白は残すこと。空白と改行だけの入力と空の入力は空文字になること
/// (空文字の時、開発者メニューは保存のボタンを押せなくする)
@Test func apiKeyFromEnteredTextDropsSurroundingWhitespaceAndNewlines() {
    #expect(apiKey(enteredText: "  key-1\n") == "key-1")
    #expect(apiKey(enteredText: "\n\tkey 2 \r\n") == "key 2")
    #expect(apiKey(enteredText: "key-3") == "key-3")
    #expect(apiKey(enteredText: " \n\t") == "")
    #expect(apiKey(enteredText: "") == "")
}

/// 会話が空の時は、messages が空の並びになること
@Test func requestBodyHasEmptyMessagesForEmptyTranscript() throws {
    #expect(
        try JSONSerialization.jsonObject(
            with: chatCompletionsRequestBody(
                request: makeGenerationRequest(transcript: Transcript(entries: []), schema: nil),
                modelName: "model-a"
            )
        ) as? NSDictionary == ["model": "model-a", "messages": [Any]()] as NSDictionary
    )
}

/// 返信案の出力の形 (文を 3 つ) を指定した要求の本文は、response_format に、その形を strict な JSON schema として持つこと。
/// schema には文の数 (3 つ) の指定が残り、JSON schema に無い x-order は入らないこと
@Test func requestBodyHasStrictJSONSchemaOfReplyTextsWithoutVendorExtension() throws {
    #expect(
        (try JSONSerialization.jsonObject(
            with: chatCompletionsRequestBody(
                request: makeGenerationRequest(transcript: Transcript(entries: []), schema: GeneratedReplyTexts.generationSchema),
                modelName: "model-a"
            )
        ) as? NSDictionary)?["response_format"] as? NSDictionary == [
            "type": "json_schema",
            "json_schema": [
                "name": "GeneratedReplyTexts",
                "strict": true,
                "schema": [
                    "additionalProperties": false,
                    "properties": [
                        "texts": [
                            "description": "Three short replies the person could send next. Each reply differs in content or tone",
                            "items": ["type": "string"],
                            "maxItems": 3,
                            "minItems": 3,
                            "type": "array",
                        ]
                    ],
                    "required": ["texts"],
                    "title": "GeneratedReplyTexts",
                    "type": "object",
                ],
            ],
        ] as NSDictionary
    )
}

/// 名前が x- で始まるキーワードは、入れ子の schema (properties の中・items の中・並びの中) からも取り除くこと。
/// x- で始まらないキーワード (x だけ・途中に x- を含む名前) と、x- で始まるプロパティの名前 (properties・$defs の直下のキー) は残すこと
@Test func vendorExtensionKeywordsAreRemovedButPropertyNamesAreKept() {
    #expect(
        removingVendorExtensionKeys(
            jsonSchema: [
                "type": "object",
                "x-order": ["x-rating", "note"],
                "x": 1,
                "max-x-value": 2,
                "properties": [
                    "x-rating": ["type": "integer", "x-hint": "remove"],
                    "note": ["type": "array", "items": ["type": "string", "x-hint": "remove"]],
                ],
                "$defs": [
                    "x-shared": ["type": "string", "x-hint": "remove"]
                ],
                "anyOf": [
                    ["type": "string", "x-hint": "remove"]
                ],
            ] as [String: Any]) as? NSDictionary == [
                "type": "object",
                "x": 1,
                "max-x-value": 2,
                "properties": [
                    "x-rating": ["type": "integer"],
                    "note": ["type": "array", "items": ["type": "string"]],
                ],
                "$defs": [
                    "x-shared": ["type": "string"]
                ],
                "anyOf": [
                    ["type": "string"]
                ],
            ] as NSDictionary
    )
}

/// 取り除くキーワードが無い schema と、schema でない値 (文字列) は、そのまま返すこと
@Test func schemaWithoutVendorExtensionKeywordsIsUnchanged() {
    #expect(removingVendorExtensionKeys(jsonSchema: ["type": "string"] as [String: Any]) as? NSDictionary == ["type": "string"] as NSDictionary)
    #expect(removingVendorExtensionKeys(jsonSchema: [String: Any]()) as? NSDictionary == [:] as NSDictionary)
    #expect(removingVendorExtensionKeys(jsonSchema: "x-order") as? String == "x-order")
}

/// 診断の記録に書く失敗の説明は、status code を持ち、応答の本文を持たないこと
@Test func chatCompletionsErrorDescriptionsNameTheFailure() {
    #expect(ChatCompletionsError.missingAPIKey.localizedDescription == "API key is not saved")
    #expect(ChatCompletionsError.unexpectedStatus(statusCode: 429).localizedDescription == "HTTP status 429")
    #expect(ChatCompletionsError.unexpectedStatus(statusCode: nil).localizedDescription == "HTTP status unknown")
    #expect(ChatCompletionsError.noContent.localizedDescription == "Response has no content")
}
