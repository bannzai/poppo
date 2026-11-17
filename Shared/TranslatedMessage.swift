/// 画面から読んだ 1 つの発言と、その翻訳
struct TranslatedMessage: Codable {
    /// 画面から読んだままの文 (相手の言語)
    let originalText: String
    /// 利用者の言語に訳した文
    let translatedText: String
}
