import Foundation
import NaturalLanguage
import Translation

/// 利用者の言語 (訳す先の言語)。利用者が端末で選んだ言語の並び (Locale.preferredLanguages) を受け取り、その先頭の言語を返す。
/// アプリが対応している言語に関わらず、利用者が選んだ言語へ訳すために使う (Apple の文書: 「A list of the user’s preferred languages.」
/// https://developer.apple.com/documentation/foundation/locale/preferredlanguages )。並びが空の時は、アプリが動いている言語を返す
nonisolated func userLanguage(preferredLanguages: [String]) -> Locale.Language {
    // 並びが空の時の Locale.current.language: 訳す先を決められずに読み取りの全体を失敗にするより、
    // アプリの表示と同じ言語へ訳す方が利用者の期待に近いため
    preferredLanguages.first.map { Locale.Language(identifier: $0) } ?? Locale.current.language
}

/// 文の組を、端末内の Translation で targetLanguage に訳し、texts と同じ順・同じ数で返す。
/// targetLanguage で書かれた文 (利用者自身の発言など) は訳さず、そのまま返す。残りの文はどれも同じ言語で書かれている前提で、
/// 原文の言語を残りの文から判定する。
/// 訳す言語が端末に入っていない時は ChatReadingError.languageNotInstalled、訳す文が無い (どの文も targetLanguage で書かれている)・
/// 原文の言語を判定できない・Translation が対応していない組の時は ChatReadingError.untranslatableLanguage、
/// 訳文が一部しか返らなかった時は ChatReadingError.incompleteTranslation を投げる
@concurrent nonisolated func translateOnDevice(texts: [String], targetLanguage: Locale.Language) async throws -> [String] {
    try await translateForeignTexts(texts: texts, targetLanguage: targetLanguage) { foreignTexts, sourceLanguage in
        try await translateWithInstalledLanguages(texts: foreignTexts, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
    }
}

/// 文の組のうち、targetLanguage で書かれていない文だけを translate で訳し、texts と同じ順・同じ数で返す。
/// targetLanguage で書かれた文はそのまま返す。translate には、訳す文 (元の順) と、その文から判定した原文の言語を渡す。
/// 訳す文が無い (どの文も targetLanguage で書かれている)・原文の言語を判定できない時は、translate を呼ばずに
/// ChatReadingError.untranslatableLanguage を投げる。translate が投げたエラーはそのまま投げる
nonisolated func translateForeignTexts(
    texts: [String],
    targetLanguage: Locale.Language,
    translate: (_ foreignTexts: [String], _ sourceLanguage: Locale.Language) async throws -> [String]
) async throws -> [String] {
    let foreignIndices = texts.indices.filter { !isWritten(text: texts[$0], language: targetLanguage) }
    guard let sourceLanguage = detectSourceLanguage(texts: foreignIndices.map { texts[$0] }, targetLanguage: targetLanguage) else {
        throw ChatReadingError.untranslatableLanguage
    }
    return replacingTexts(
        texts: texts,
        indices: foreignIndices,
        replacements: try await translate(foreignIndices.map { texts[$0] }, sourceLanguage)
    )
}

/// 同じ言語 (sourceLanguage) で書かれた文の組を、端末に入っている言語で targetLanguage に訳し、texts と同じ順・同じ数で返す。
/// 訳す言語が端末に入っていない時は ChatReadingError.languageNotInstalled、Translation が対応していない組の時は
/// ChatReadingError.untranslatableLanguage、訳文が一部しか返らなかった時は ChatReadingError.incompleteTranslation を投げる
@concurrent nonisolated func translateWithInstalledLanguages(
    texts: [String],
    sourceLanguage: Locale.Language,
    targetLanguage: Locale.Language
) async throws -> [String] {
    try await requireInstalledLanguages(
        status: LanguageAvailability().status(from: sourceLanguage, to: targetLanguage),
        source: sourceLanguage,
        target: targetLanguage
    )
    return try await orderedTargetTexts(
        responses: TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
            .translations(from: translationRequests(texts: texts)),
        count: texts.count
    )
}

/// 訳す文の組から、Translation に渡す依頼の組を、文を渡した順に作る。
/// 返ってきた訳文と文の対応を取るため、文の位置 (0 始まり) を文字列にして clientIdentifier に入れる
nonisolated func translationRequests(texts: [String]) -> [TranslationSession.Request] {
    texts.enumerated().map { TranslationSession.Request(sourceText: $1, clientIdentifier: String($0)) }
}

/// 文が language で書かれているか。言語を判定できない文 (短すぎる文・数字だけの文など) は false を返す。
/// 文字の種類の違い (簡体字と繁体字など) は区別せず、言語が同じなら true を返す
nonisolated func isWritten(text: String, language: Locale.Language) -> Bool {
    language.languageCode != nil
        && NLLanguageRecognizer.dominantLanguage(for: text).flatMap { Locale.Language(identifier: $0.rawValue).languageCode }
            == language.languageCode
}

/// 訳す文の組が書かれている言語 (原文の言語) を、文から判定して返す。
/// 文が無い・言語を判定できない・判定した言語が targetLanguage と同じ (訳す必要が無い) 時は nil を返す
nonisolated func detectSourceLanguage(texts: [String], targetLanguage: Locale.Language) -> Locale.Language? {
    NLLanguageRecognizer.dominantLanguage(for: texts.joined(separator: "\n"))
        .map { Locale.Language(identifier: $0.rawValue) }
        .flatMap { $0.languageCode == targetLanguage.languageCode ? nil : $0 }
}

/// texts のうち indices の位置の文を、同じ順に並んだ replacements の文に置き換えて返す。ほかの位置の文はそのまま返す
nonisolated func replacingTexts(texts: [String], indices: [Int], replacements: [String]) -> [String] {
    zip(indices, replacements).reduce(into: texts) { replacedTexts, replacement in
        replacedTexts[replacement.0] = replacement.1
    }
}

/// 訳す言語の組が、端末で訳せる状態 (言語が入っている) かを確かめる。訳せる状態なら何も返さずに戻る。
/// 対応しているが言語が入っていない時は、その言語の組を持った ChatReadingError.languageNotInstalled を、
/// Translation が対応していない組の時は ChatReadingError.untranslatableLanguage を投げる
nonisolated func requireInstalledLanguages(
    status: LanguageAvailability.Status,
    source: Locale.Language,
    target: Locale.Language
) throws {
    switch status {
    case .installed:
        return
    case .supported:
        throw ChatReadingError.languageNotInstalled(source: source, target: target)
    case .unsupported:
        throw ChatReadingError.untranslatableLanguage
    @unknown default:
        throw ChatReadingError.untranslatableLanguage
    }
}

/// Translation が返した訳文を、訳す時に渡した文の順に count 個並べて返す。
/// 訳文と渡した文の対応は、返ってきた順に頼らず clientIdentifier (渡した文の位置を文字列にしたもの) で取る。
/// どれかの位置の訳文が無い時は ChatReadingError.incompleteTranslation を投げる
nonisolated func orderedTargetTexts(responses: [TranslationSession.Response], count: Int) throws -> [String] {
    try (0..<count).map { index in
        guard let response = responses.first(where: { $0.clientIdentifier == String(index) }) else {
            throw ChatReadingError.incompleteTranslation
        }
        return response.targetText
    }
}
