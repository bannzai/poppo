import CoreGraphics
import Foundation
import Testing
@testable import Poppo

/// テストで readChat に渡す 1 ピクセルの画像。文字の読み取りは偽物に差し替えるため、中身は使われない
private func makeTestImage() throws -> CGImage {
    try #require(
        CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage()
    )
}

/// 文字の読み取りの偽物が返す、相手の発言 1 つと利用者の発言 1 つが写った画面の行
private let recognizedChatLines = [
    RecognizedTextLine(text: "Are you free today?", boundingBox: CGRect(x: 0.08, y: 0.3, width: 0.5, height: 0.02)),
    RecognizedTextLine(text: "Yes, after lunch", boundingBox: CGRect(x: 0.55, y: 0.4, width: 0.37, height: 0.02)),
]

/// 画像 1 枚から、発言ごとの原文と訳文を画面の上から下の順に返し、返信案には返信の文と、その文を訳した意味を入れること
@Test func readChatReturnsTranslatedMessagesAndReplySuggestions() async throws {
    let reading = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { texts in texts.map { "訳: " + $0 } },
        canGenerateReplies: true,
        generateReplyTexts: { _ in ["Sounds good", "Maybe tomorrow"] }
    )

    #expect(reading.messages.map(\.originalText) == ["Are you free today?", "Yes, after lunch"])
    #expect(reading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
    #expect(reading.replySuggestions.map(\.text) == ["Sounds good", "Maybe tomorrow"])
    #expect(reading.replySuggestions.map(\.meaning) == ["訳: Sounds good", "訳: Maybe tomorrow"])
}

/// 返信の文の生成には、読み取った発言をすべて、利用者自身の発言かどうかの区別を付けて渡すこと
@Test func readChatPassesEveryMessageWithItsSpeakerToReplyGeneration() async throws {
    var receivedMessages: [ExtractedMessage] = []
    _ = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { $0 },
        canGenerateReplies: true,
        generateReplyTexts: { messages in
            receivedMessages = messages
            return []
        }
    )

    #expect(receivedMessages.map(\.text) == ["Are you free today?", "Yes, after lunch"])
    #expect(receivedMessages.map(\.isFromUser) == [false, true])
}

/// 端末内のモデルが使えない時は、返信の文の生成を呼ばず、返信案を空にして翻訳だけを返すこと
@Test func readChatReturnsOnlyTranslationWhenModelIsUnavailable() async throws {
    var replyGenerationCallCount = 0
    let reading = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { texts in texts.map { "訳: " + $0 } },
        canGenerateReplies: false,
        generateReplyTexts: { _ in
            replyGenerationCallCount += 1
            return ["Sounds good"]
        }
    )

    #expect(replyGenerationCallCount == 0)
    #expect(reading.replySuggestions.isEmpty)
    #expect(reading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
}

/// 返信の文の生成が失敗した時は、翻訳を失わず、返信案を空にして返すこと
@Test func readChatReturnsOnlyTranslationWhenReplyGenerationFails() async throws {
    let reading = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { texts in texts.map { "訳: " + $0 } },
        canGenerateReplies: true,
        generateReplyTexts: { _ in throw CocoaError(.featureUnsupported) }
    )

    #expect(reading.replySuggestions.isEmpty)
    #expect(reading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
}

/// 返信の文の意味の翻訳が失敗した時は、発言の翻訳を失わず、返信案を空にして返すこと
@Test func readChatReturnsOnlyTranslationWhenReplyMeaningTranslationFails() async throws {
    var translationCallCount = 0
    let reading = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { texts in
            translationCallCount += 1
            guard translationCallCount == 1 else {
                throw CocoaError(.featureUnsupported)
            }
            return texts.map { "訳: " + $0 }
        },
        canGenerateReplies: true,
        generateReplyTexts: { _ in ["Sounds good"] }
    )

    #expect(reading.replySuggestions.isEmpty)
    #expect(reading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
}

/// 返信の文の意味の訳文が返信の文より少なく返った時は、意味のずれた返信案を出さず、返信案を空にして返すこと
@Test func readChatReturnsNoReplySuggestionsWhenReplyMeaningsAreIncomplete() async throws {
    var translationCallCount = 0
    let reading = try await readChat(
        image: makeTestImage(),
        recognizeTextLines: { _ in recognizedChatLines },
        translateTexts: { texts in
            translationCallCount += 1
            return translationCallCount == 1 ? texts.map { "訳: " + $0 } : ["訳: Sounds good"]
        },
        canGenerateReplies: true,
        generateReplyTexts: { _ in ["Sounds good", "Maybe tomorrow"] }
    )

    #expect(reading.replySuggestions.isEmpty)
    #expect(reading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
}

/// 画像から文字を 1 行も読み取れなかった時は、発言が無いことを表すエラーを投げること
@Test func readChatThrowsNoMessagesWhenNoTextIsRecognized() async throws {
    let image = try makeTestImage()
    await #expect(throws: ChatReadingError.noMessages) {
        _ = try await readChat(
            image: image,
            recognizeTextLines: { _ in [] },
            translateTexts: { $0 },
            canGenerateReplies: true,
            generateReplyTexts: { _ in [] }
        )
    }
}

/// 訳文が発言の数より少なく返った時は、発言の一部だけを出さず、訳文が足りないことを表すエラーを投げること
@Test func readChatThrowsIncompleteTranslationWhenTranslationsAreMissing() async throws {
    let image = try makeTestImage()
    await #expect(throws: ChatReadingError.incompleteTranslation) {
        _ = try await readChat(
            image: image,
            recognizeTextLines: { _ in recognizedChatLines },
            translateTexts: { _ in ["訳: Are you free today?"] },
            canGenerateReplies: true,
            generateReplyTexts: { _ in [] }
        )
    }
}

/// 訳す言語が端末に入っていない失敗は、言語の組を保ったまま呼び出し元へ伝えること (画面が言語のダウンロードを促すために使う)
@Test func readChatRethrowsLanguageNotInstalled() async throws {
    let image = try makeTestImage()
    await #expect(
        throws: ChatReadingError.languageNotInstalled(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ja")
        )
    ) {
        _ = try await readChat(
            image: image,
            recognizeTextLines: { _ in recognizedChatLines },
            translateTexts: { _ in
                throw ChatReadingError.languageNotInstalled(
                    source: Locale.Language(identifier: "en"),
                    target: Locale.Language(identifier: "ja")
                )
            },
            canGenerateReplies: true,
            generateReplyTexts: { _ in [] }
        )
    }
}

/// 訳す言語が端末に入っていない時は、画面の状態が、その言語の組でダウンロードを促す状態になること
@Test func phaseAsksForLanguageDownloadWhenLanguageIsNotInstalled() async {
    guard
        case .needsLanguageDownload(let source, let target) = await chatReadingPhase(read: {
            throw ChatReadingError.languageNotInstalled(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ja")
            )
        })
    else {
        Issue.record("言語のダウンロードを促す状態になっていない")
        return
    }

    #expect(source == Locale.Language(identifier: "en"))
    #expect(target == Locale.Language(identifier: "ja"))
}

/// 読み取りが終わった時は、画面の状態が、読み取った翻訳と返信案を出す状態になること
@Test func phaseIsLoadedWithMessagesAndReplySuggestions() async {
    guard
        case .loaded(let messages, let replySuggestions) = await chatReadingPhase(read: {
            (
                messages: [TranslatedMessage(originalText: "Hello", translatedText: "こんにちは")],
                replySuggestions: [ReplySuggestion(text: "Hi there", meaning: "やあ")]
            )
        })
    else {
        Issue.record("翻訳と返信案を出す状態になっていない")
        return
    }

    #expect(messages.map(\.originalText) == ["Hello"])
    #expect(messages.map(\.translatedText) == ["こんにちは"])
    #expect(replySuggestions.map(\.text) == ["Hi there"])
    #expect(replySuggestions.map(\.meaning) == ["やあ"])
}

/// 言語が入っていない以外の失敗 (発言が無い等) では、言語のダウンロードを促さず、その失敗を持った失敗の状態になること
@Test func phaseIsFailedForOtherErrors() async {
    guard case .failed(let error) = await chatReadingPhase(read: { throw ChatReadingError.noMessages }) else {
        Issue.record("失敗の状態になっていない")
        return
    }

    #expect(error as? ChatReadingError == .noMessages)
}
