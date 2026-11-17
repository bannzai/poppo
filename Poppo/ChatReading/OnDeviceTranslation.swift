import Foundation
import NaturalLanguage
import Translation

/// 文の組を、端末内の Translation で targetLanguage に訳す。文はどれも同じ言語で書かれている前提で、原文の言語は文から判定する。
/// 訳文を texts と同じ順・同じ数で返す。
/// 訳す言語が端末に入っていない時は ChatReadingError.languageNotInstalled、原文の言語を判定できないか Translation が対応していない組の時は
/// ChatReadingError.untranslatableLanguage、訳文が一部しか返らなかった時は ChatReadingError.incompleteTranslation を投げる
@concurrent nonisolated func translateOnDevice(texts: [String], targetLanguage: Locale.Language) async throws -> [String] {
    guard let sourceLanguage = NLLanguageRecognizer.dominantLanguage(for: texts.joined(separator: "\n"))
        .map({ Locale.Language(identifier: $0.rawValue) })
    else {
        throw ChatReadingError.untranslatableLanguage
    }
    switch await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage) {
    case .installed:
        break
    case .supported:
        throw ChatReadingError.languageNotInstalled(source: sourceLanguage, target: targetLanguage)
    case .unsupported:
        throw ChatReadingError.untranslatableLanguage
    @unknown default:
        throw ChatReadingError.untranslatableLanguage
    }
    // 訳文と原文の対応を、返ってくる順に頼らず clientIdentifier (texts の中の位置) で取る
    let responses = try await TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
        .translations(from: texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) })
    return try texts.indices.map { index in
        guard let response = responses.first(where: { $0.clientIdentifier == String(index) }) else {
            throw ChatReadingError.incompleteTranslation
        }
        return response.targetText
    }
}
