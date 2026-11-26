import Foundation

/// 読み取った発言を書いた相手が、利用者にとってどういう相手か。返信案の口調を分けるためだけに使う (翻訳には使わない)。
/// 選べる関係の一覧は、この enum の case だけに置く。何も選んでいない状態は、この型の Optional の nil で表す。
/// 生の値は、選んだ関係の保存 (selectedChatPartnerRelationshipUserDefaultsKey) に書くため、変えない
nonisolated enum ChatPartnerRelationship: String, CaseIterable {
    /// 友人・家族
    case friendOrFamily
    /// 仕事の仲間
    case coworker
    /// 目上・取引先
    case superiorOrClient
    /// 初めての相手
    case stranger
}

/// 訳す先として選んだ言語 (Locale.Language の maximalIdentifier) を保存する、UserDefaults のキー
let selectedTargetLanguageUserDefaultsKey = "selectedTargetLanguage"

/// 選んだ相手との関係 (ChatPartnerRelationship の生の値) を保存する、UserDefaults のキー
let selectedChatPartnerRelationshipUserDefaultsKey = "selectedChatPartnerRelationship"

/// 訳す先の言語として選ばれているものを返す。userDefaults は選んだ言語を保存してある場所、
/// preferredLanguages は利用者が端末で選んだ言語の並び (Locale.preferredLanguages)
func selectedTargetLanguage(userDefaults: UserDefaults, preferredLanguages: [String]) -> Locale.Language {
    targetLanguage(
        savedIdentifier: userDefaults.string(forKey: selectedTargetLanguageUserDefaultsKey),
        preferredLanguages: preferredLanguages
    )
}

/// 保存してある訳す先の言語の識別子 (savedIdentifier。nil か空文字は未選択) から、訳す先の言語を返す。
/// preferredLanguages は利用者が端末で選んだ言語の並び
func targetLanguage(savedIdentifier: String?, preferredLanguages: [String]) -> Locale.Language {
    // 何も選んでいない時 (保存した値が無い・空文字) は端末の言語: 訳す先を選べるようにする前の動き (端末の言語へ訳す) を変えないため
    savedIdentifier.flatMap { $0.isEmpty ? nil : Locale.Language(identifier: $0) }
        ?? userLanguage(preferredLanguages: preferredLanguages)
}

/// 相手との関係として選ばれているものを返す。userDefaults は選んだ関係を保存してある場所。
/// 何も選んでいない時と、保存してある値が今の一覧に無い時は nil (未選択) を返す
func selectedChatPartnerRelationship(userDefaults: UserDefaults) -> ChatPartnerRelationship? {
    userDefaults.string(forKey: selectedChatPartnerRelationshipUserDefaultsKey).flatMap { ChatPartnerRelationship(rawValue: $0) }
}

/// 文の組 (texts) を、訳す先として選ばれている言語 (selectedTargetLanguage(userDefaults:preferredLanguages:)) へ translate で訳して返す。
/// translate は、文の組と訳す先の言語を受け取って訳文を返す処理 (本物は translateOnDevice(texts:targetLanguage:))
func translateIntoSelectedLanguage(
    texts: [String],
    userDefaults: UserDefaults,
    preferredLanguages: [String],
    translate: (_ texts: [String], _ targetLanguage: Locale.Language) async throws -> [String]
) async throws -> [String] {
    try await translate(texts, selectedTargetLanguage(userDefaults: userDefaults, preferredLanguages: preferredLanguages))
}

/// 文の組 (texts) を、アプリに保存してある訳す先の言語へ端末内で訳して返す
func translateIntoSelectedLanguageOnDevice(texts: [String]) async throws -> [String] {
    try await translateIntoSelectedLanguage(
        texts: texts,
        userDefaults: .standard,
        preferredLanguages: Locale.preferredLanguages,
        translate: { try await translateOnDevice(texts: $0, targetLanguage: $1) }
    )
}

/// 発言 (messages) に続く返信の文を、相手との関係として選ばれているもの (selectedChatPartnerRelationship(userDefaults:)。nil は未選択) を
/// generate に渡して作って返す。generate は、発言と相手との関係を受け取って返信の文を返す処理 (本物は generateReplyTexts(messages:replyModel:chatPartnerRelationship:))
func generateReplyTextsForSelectedRelationship(
    messages: [ExtractedMessage],
    userDefaults: UserDefaults,
    generate: (_ messages: [ExtractedMessage], _ chatPartnerRelationship: ChatPartnerRelationship?) async throws -> [String]
) async throws -> [String] {
    try await generate(messages, selectedChatPartnerRelationship(userDefaults: userDefaults))
}

/// replyModel のモデルで、アプリに保存してある相手との関係に合う口調の返信の文を作る
func generateReplyTextsForSelectedRelationship(messages: [ExtractedMessage], replyModel: ReplyModel) async throws -> [String] {
    try await generateReplyTextsForSelectedRelationship(
        messages: messages,
        userDefaults: .standard,
        generate: { try await generateReplyTexts(messages: $0, replyModel: replyModel, chatPartnerRelationship: $1) }
    )
}
