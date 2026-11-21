import Foundation
import Synchronization
import Testing
@testable import Poppo

/// 差し替えた通信が受け取った要求 1 つ
private nonisolated struct ReceivedChatCompletionsRequest {
    /// 要求 (URL・メソッド・ヘッダー)
    let urlRequest: URLRequest
    /// 要求の本文
    let body: Data
}

/// 差し替えた通信が返す応答
private nonisolated struct StubbedChatCompletionsResponse {
    /// HTTP の status code。nil の時は、HTTP でない応答 (status code を持たない URLResponse) を返す
    let statusCode: Int?
    /// 応答の本文
    let body: Data
}

/// 差し替えた通信の状態。接続先の host ごとに、返す応答と、受け取った要求を持つ
private nonisolated struct ChatCompletionsStubState {
    /// host ごとの、返す応答。無い host への要求は失敗させる
    var responses: [String: StubbedChatCompletionsResponse] = [:]
    /// host ごとの、受け取った要求 (届いた順)
    var receivedRequests: [String: [ReceivedChatCompletionsRequest]] = [:]
}

/// OpenAI と Gemini の接続先への要求を、実際のサーバーへ送らずに受け取り、決めた応答を返す URLProtocol。
/// URLProtocol は継承で差し替える仕組みのため class で書く
private nonisolated final class ChatCompletionsStubURLProtocol: URLProtocol {
    /// 差し替えた通信の状態。URLProtocol のインスタンスは URLSession が作るため、テストとの受け渡しは static に置く
    static let state = Mutex(ChatCompletionsStubState())

    override class func canInit(with request: URLRequest) -> Bool {
        ["api.openai.com", "generativelanguage.googleapis.com"].contains(request.url?.host() ?? "")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host() else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let stubbedResponse = Self.state.withLock { state in
            state.receivedRequests[host, default: []].append(
                ReceivedChatCompletionsRequest(urlRequest: request, body: requestBody(urlRequest: request))
            )
            return state.responses[host]
        }
        guard let stubbedResponse else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        guard let statusCode = stubbedResponse.statusCode else {
            client?.urlProtocol(
                self,
                didReceive: URLResponse(url: url, mimeType: "application/json", expectedContentLength: stubbedResponse.body.count, textEncodingName: nil),
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: stubbedResponse.body)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        guard let httpURLResponse = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: httpURLResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stubbedResponse.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// urlRequest の本文を返す。URLProtocol に届く要求では、本文が httpBody ではなく httpBodyStream に入っているため、stream から読む
private nonisolated func requestBody(urlRequest: URLRequest) -> Data {
    guard let stream = urlRequest.httpBodyStream else {
        return urlRequest.httpBody ?? Data()
    }
    stream.open()
    defer {
        stream.close()
    }
    var body = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        guard readCount > 0 else {
            break
        }
        body.append(buffer, count: readCount)
    }
    return body
}

/// content を発言の文として持つ、Chat Completions の API の成功の応答の本文を作って返す
private func chatCompletionsResponseBody(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": content]]]])
}

/// OpenAI と Gemini の接続先への通信を差し替えて、要求の中身と応答の読み取りを確かめるテスト。
/// 差し替えの状態 (ChatCompletionsStubURLProtocol.state) を共有するため、1 つずつ順に実行する
@Suite(.serialized) struct ChatCompletionsRequestTests {
    /// API キーを置く、このテストだけの Keychain の service
    private let keychainService = "ChatCompletionsRequestTests-\(UUID().uuidString)"

    /// 通信の差し替えを始め、前のテストの応答と要求を消す
    init() {
        URLProtocol.registerClass(ChatCompletionsStubURLProtocol.self)
        ChatCompletionsStubURLProtocol.state.withLock { $0 = ChatCompletionsStubState() }
    }

    /// OpenAI と Gemini の API キーを Keychain から消す (テストの後片付け)
    private func deleteAPIKeys() {
        try? deleteAPIKey(replyModel: .openAI, keychainService: keychainService)
        try? deleteAPIKey(replyModel: .gemini, keychainService: keychainService)
    }

    /// OpenAI を選ぶと、OpenAI の接続先へ、OpenAI のキーを Authorization に付け、OpenAI のモデルの名前・会話・返信案の出力の形を
    /// 入れた要求を 1 回送り、応答の JSON の文 3 つが戻り値になること
    @Test func openAIRequestCarriesOwnKeyModelMessagesAndSchemaAndReturnsReplyTexts() async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        try save(apiKey: "test-gemini-key", replyModel: .gemini, keychainService: keychainService)
        try ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(
                statusCode: 200,
                body: try chatCompletionsResponseBody(content: #"{"texts":["Sure","After lunch works","Sorry, not today"]}"#)
            )
        }

        #expect(
            try await generateReplyTexts(
                messages: [
                    ExtractedMessage(text: "Are you free today?", isFromUser: false),
                    ExtractedMessage(text: "Let me check", isFromUser: true),
                ],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            ) == ["Sure", "After lunch works", "Sorry, not today"]
        )
        let receivedRequests = ChatCompletionsStubURLProtocol.state.withLock { $0.receivedRequests }
        #expect(receivedRequests["generativelanguage.googleapis.com"] == nil)
        let openAIRequests = try #require(receivedRequests["api.openai.com"])
        #expect(openAIRequests.count == 1)
        #expect(openAIRequests[0].urlRequest.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(openAIRequests[0].urlRequest.httpMethod == "POST")
        #expect(openAIRequests[0].urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-openai-key")
        #expect(openAIRequests[0].urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(JSONSerialization.jsonObject(with: openAIRequests[0].body) as? [String: Any])
        #expect(body["model"] as? String == "gpt-6-luna")
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages.map { $0["role"] } == ["system", "user"])
        #expect(messages[0]["content"]?.isEmpty == false)
        #expect(messages[1]["content"] == "Them: Are you free today?\n\nMe: Let me check")
        let responseFormat = try #require(body["response_format"] as? [String: Any])
        #expect(responseFormat["type"] as? String == "json_schema")
        let jsonSchema = try #require(responseFormat["json_schema"] as? [String: Any])
        #expect(jsonSchema["name"] as? String == "GeneratedReplyTexts")
        #expect(jsonSchema["strict"] as? Bool == true)
        #expect(((jsonSchema["schema"] as? [String: Any])?["properties"] as? [String: Any])?.keys.sorted() == ["texts"])
    }

    /// Gemini を選ぶと、Gemini の OpenAI 互換の接続先へ、Gemini のキーと Gemini のモデルの名前で要求を送り (OpenAI へは送らない)、
    /// 応答の JSON の文 3 つが戻り値になること
    @Test func geminiRequestGoesToGeminiEndpointWithOwnKeyAndModel() async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        try save(apiKey: "test-gemini-key", replyModel: .gemini, keychainService: keychainService)
        try ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["generativelanguage.googleapis.com"] = StubbedChatCompletionsResponse(
                statusCode: 200,
                body: try chatCompletionsResponseBody(content: #"{"texts":["Yes","Maybe","No"]}"#)
            )
        }

        #expect(
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .gemini,
                apiKeyKeychainService: keychainService
            ) == ["Yes", "Maybe", "No"]
        )
        let receivedRequests = ChatCompletionsStubURLProtocol.state.withLock { $0.receivedRequests }
        #expect(receivedRequests["api.openai.com"] == nil)
        let geminiRequests = try #require(receivedRequests["generativelanguage.googleapis.com"])
        #expect(geminiRequests.count == 1)
        #expect(
            geminiRequests[0].urlRequest.url?.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        )
        #expect(geminiRequests[0].urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-gemini-key")
        #expect((try JSONSerialization.jsonObject(with: geminiRequests[0].body) as? [String: Any])?["model"] as? String == "gemini-3.5-flash-lite")
    }

    /// 提供元が 200 番台以外を返すと、その status code を持つエラーになること。診断の記録に書く文は status code を持ち、
    /// 応答の本文に API キーが入っていても、キーを持たないこと
    @Test(arguments: [100, 199, 300, 401, 429, 500])
    func statusOutsideSuccessRangeThrowsErrorWithStatusCodeAndWithoutAPIKey(statusCode: Int) async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(
                statusCode: statusCode,
                body: Data(#"{"error":{"message":"Incorrect API key provided: test-openai-key"}}"#.utf8)
            )
        }

        let thrownError = await #expect(throws: ChatCompletionsError.self) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            )
        }

        #expect(thrownError == .unexpectedStatus(statusCode: statusCode))
        let failureDescription = screenReadingFailureDescription(error: try #require(thrownError))
        #expect(failureDescription.contains("HTTP status \(statusCode)"))
        #expect(failureDescription.contains("test-openai-key") == false)
    }

    /// 200 番台の両端 (200 と 299) は成功として応答を読むこと
    @Test(arguments: [200, 299])
    func statusInSuccessRangeReturnsReplyTexts(statusCode: Int) async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        try ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(
                statusCode: statusCode,
                body: try chatCompletionsResponseBody(content: #"{"texts":["A","B","C"]}"#)
            )
        }

        #expect(
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            ) == ["A", "B", "C"]
        )
    }

    /// 200 番台でも、本文が Chat Completions の応答として読めない時 (JSON でない・choices が無い) は、読み取りのエラー (DecodingError) になること
    @Test(arguments: [
        "not json",
        #"{"object":"chat.completion"}"#,
    ])
    func unreadableResponseBodyThrowsDecodingError(responseBody: String) async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(statusCode: 200, body: Data(responseBody.utf8))
        }

        await #expect(throws: DecodingError.self) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            )
        }
    }

    /// 通信そのものが失敗した時 (接続できない) は、通信のエラー (URLError) がそのまま届くこと
    @Test func connectionFailureThrowsURLError() async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)

        await #expect(throws: URLError.self) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            )
        }
    }

    /// HTTP でない応答 (status code が無い) が返った時は、status code が nil のエラーになること
    @Test func nonHTTPResponseThrowsErrorWithoutStatusCode() async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        try ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(
                statusCode: nil,
                body: try chatCompletionsResponseBody(content: #"{"texts":["A","B","C"]}"#)
            )
        }

        await #expect(throws: ChatCompletionsError.unexpectedStatus(statusCode: nil)) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            )
        }
    }

    /// 応答に候補が複数ある時は、先頭の候補の文だけを使うこと
    @Test func firstChoiceIsUsedWhenResponseHasMultipleChoices() async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        try ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(
                statusCode: 200,
                body: try JSONSerialization.data(withJSONObject: [
                    "choices": [
                        ["message": ["role": "assistant", "content": #"{"texts":["First 1","First 2","First 3"]}"#]],
                        ["message": ["role": "assistant", "content": #"{"texts":["Second 1","Second 2","Second 3"]}"#]],
                    ]
                ])
            )
        }

        #expect(
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            ) == ["First 1", "First 2", "First 3"]
        )
    }

    /// 応答に返信の文が無い時 (候補が空・文が null) は、「応答に文が無い」のエラーになること
    @Test(arguments: [
        #"{"choices":[]}"#,
        #"{"choices":[{"message":{"role":"assistant","content":null}}]}"#,
    ])
    func responseWithoutContentThrowsNoContent(responseBody: String) async throws {
        defer {
            deleteAPIKeys()
        }
        try save(apiKey: "test-openai-key", replyModel: .openAI, keychainService: keychainService)
        ChatCompletionsStubURLProtocol.state.withLock {
            $0.responses["api.openai.com"] = StubbedChatCompletionsResponse(statusCode: 200, body: Data(responseBody.utf8))
        }

        await #expect(throws: ChatCompletionsError.noContent) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .openAI,
                apiKeyKeychainService: keychainService
            )
        }
    }

    /// API キーを保存していないモデルで作ろうとすると、提供元へ要求を送らずに「API キーを保存していない」のエラーになること
    @Test func missingAPIKeyThrowsWithoutSendingRequest() async throws {
        await #expect(throws: ChatCompletionsError.missingAPIKey) {
            try await generateReplyTexts(
                messages: [ExtractedMessage(text: "Coming?", isFromUser: false)],
                replyModel: .gemini,
                apiKeyKeychainService: keychainService
            )
        }

        #expect(ChatCompletionsStubURLProtocol.state.withLock { $0.receivedRequests.isEmpty })
    }
}
