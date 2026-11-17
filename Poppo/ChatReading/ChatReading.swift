import CoreGraphics
import Foundation

/// 画像からの読み取りが、翻訳まで終えられなかった理由
nonisolated enum ChatReadingError: Error, Equatable {
    /// 選んだ画像を読み出せなかった (端末に無く iCloud にだけある画像を含む)
    case imageUnavailable
    /// 画像から発言を 1 つも読み取れなかった
    case noMessages
    /// 訳す言語が端末に入っていない。言語をダウンロードすれば訳せる
    case languageNotInstalled(source: Locale.Language, target: Locale.Language)
    /// 原文の言語を判定できないか、原文の言語から利用者の言語への翻訳に Translation が対応していない (2 つが同じ言語の時を含む)
    case untranslatableLanguage
    /// 訳文が、渡した文の一部にしか返らなかった
    case incompleteTranslation
}

/// 画像 1 枚から、写っている発言ごとの原文と訳文と、返信案を作る。
/// 発言は画面の上から下の順に、利用者自身の発言も含めてすべて訳す。返信案は canGenerateReplies が true の時だけ作り、
/// 作れなかった時 (モデルが使えない・生成に失敗した) は返信案を空にして翻訳だけを返す。
/// 文字の読み取り・翻訳・返信の文の生成は引数で受け取る (simulator では翻訳と生成が動かないため、テストで差し替える)。
/// 発言を読み取れない時と、翻訳できない時は ChatReadingError か、引数の処理が投げたエラーを投げる
func readChat(
    image: CGImage,
    recognizeTextLines: @MainActor (CGImage) async throws -> [RecognizedTextLine],
    translateTexts: @MainActor ([String]) async throws -> [String],
    canGenerateReplies: Bool,
    generateReplyTexts: @MainActor ([ExtractedMessage]) async throws -> [String]
) async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion]) {
    let extractedMessages = extractMessages(lines: try await recognizeTextLines(image))
    guard !extractedMessages.isEmpty else {
        throw ChatReadingError.noMessages
    }
    let translatedTexts = try await translateTexts(extractedMessages.map(\.text))
    guard translatedTexts.count == extractedMessages.count else {
        throw ChatReadingError.incompleteTranslation
    }
    let messages = zip(extractedMessages, translatedTexts).map {
        TranslatedMessage(originalText: $0.text, translatedText: $1)
    }
    guard canGenerateReplies else {
        return (messages, [])
    }
    do {
        let replyTexts = try await generateReplyTexts(extractedMessages)
        // 返信案の意味は、モデルに書かせず返信の文そのものを訳して作る (送る前に確かめる文が、送る文の訳であるようにするため)
        let replyMeanings = try await translateTexts(replyTexts)
        guard replyMeanings.count == replyTexts.count else {
            return (messages, [])
        }
        return (messages, zip(replyTexts, replyMeanings).map { ReplySuggestion(text: $0, meaning: $1) })
    } catch {
        // 返信案だけが作れなかった時に、できている翻訳まで失わないため
        return (messages, [])
    }
}
