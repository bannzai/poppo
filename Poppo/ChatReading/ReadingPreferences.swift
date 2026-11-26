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
    // 何も選んでいない時は端末の言語: 訳す先を選べるようにする前の動き (端末の言語へ訳す) を変えないため
    userDefaults.string(forKey: selectedTargetLanguageUserDefaultsKey).map { Locale.Language(identifier: $0) }
        ?? userLanguage(preferredLanguages: preferredLanguages)
}

/// 訳す先の言語として selectedTargetLanguage を選んだことを、userDefaults に保存する。前に選んだ言語は上書きされる
func save(selectedTargetLanguage: Locale.Language, userDefaults: UserDefaults) {
    userDefaults.set(selectedTargetLanguage.maximalIdentifier, forKey: selectedTargetLanguageUserDefaultsKey)
}

/// 相手との関係として選ばれているものを返す。userDefaults は選んだ関係を保存してある場所。
/// 何も選んでいない時と、保存してある値が今の一覧に無い時は nil (未選択) を返す
func selectedChatPartnerRelationship(userDefaults: UserDefaults) -> ChatPartnerRelationship? {
    userDefaults.string(forKey: selectedChatPartnerRelationshipUserDefaultsKey).flatMap { ChatPartnerRelationship(rawValue: $0) }
}

/// 相手との関係として selectedChatPartnerRelationship を選んだことを、userDefaults に保存する。前に選んだ関係は上書きされる。
/// nil (未選択) を渡すと、保存してある関係を消す
func save(selectedChatPartnerRelationship: ChatPartnerRelationship?, userDefaults: UserDefaults) {
    userDefaults.set(selectedChatPartnerRelationship?.rawValue, forKey: selectedChatPartnerRelationshipUserDefaultsKey)
}

/// 文の組 (texts) を、訳す先として選ばれている言語 (selectedTargetLanguage(userDefaults:preferredLanguages:)) へ translate で訳して返す。
/// translate は、文の組と訳す先の言語を受け取って訳文を返す処理 (本物は translateOnDevice(texts:targetLanguage:))。
/// スクリーンショットからの読み取りと、取り込んだ画面の読み取りの両方が、訳す先の言語をこの関数で決める
func translateIntoSelectedLanguage(
    texts: [String],
    userDefaults: UserDefaults,
    preferredLanguages: [String],
    translate: (_ texts: [String], _ targetLanguage: Locale.Language) async throws -> [String]
) async throws -> [String] {
    try await translate(texts, selectedTargetLanguage(userDefaults: userDefaults, preferredLanguages: preferredLanguages))
}

/// 文の組 (texts) を、アプリに保存してある訳す先の言語へ端末内で訳して返す。
/// スクリーンショットからの読み取りと、取り込んだ画面の読み取りの両方が使う、本物の翻訳の処理
func translateIntoSelectedLanguageOnDevice(texts: [String]) async throws -> [String] {
    try await translateIntoSelectedLanguage(
        texts: texts,
        userDefaults: .standard,
        preferredLanguages: Locale.preferredLanguages,
        translate: { try await translateOnDevice(texts: $0, targetLanguage: $1) }
    )
}

/// replyModel のモデルで、アプリに保存してある相手との関係に合う口調の返信の文を作る。
/// スクリーンショットからの読み取りと、取り込んだ画面の読み取りの両方が使う、本物の返信の文を作る処理
func generateReplyTextsForSelectedRelationship(messages: [ExtractedMessage], replyModel: ReplyModel) async throws -> [String] {
    try await generateReplyTexts(
        messages: messages,
        replyModel: replyModel,
        chatPartnerRelationship: selectedChatPartnerRelationship(userDefaults: .standard)
    )
}
