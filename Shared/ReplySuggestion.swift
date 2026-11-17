/// 1 つの返信案
struct ReplySuggestion: Codable {
    /// タップした時に入力欄へ入る文 (相手の言語)
    let text: String
    /// その文の意味を利用者の言語で書いた文。送る前に内容を確かめるために出す
    let meaning: String
}
