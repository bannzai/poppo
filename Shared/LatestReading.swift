import Foundation

/// 読み取り結果。本体アプリが直前に画面から読んだ発言と、その翻訳と、返信案の組。
/// 本体アプリが画面を読むたびに上書きし、キーボードはこれを読んで表示する。
struct LatestReading: Codable {
    /// 画面を読んだ時刻。キーボードが「何分前の内容か」を出すのに使う
    let capturedAt: Date
    /// 画面に見えていた発言。画面の上から下の順
    let messages: [TranslatedMessage]
    /// 返信案。端末内のモデルが使えない端末では空
    let replySuggestions: [ReplySuggestion]
}

/// 本体アプリとキーボードが共有する App Group の識別子。
/// Config/Poppo.entitlements と Config/PoppoKeyboard.entitlements の値と同じにする (scripts/test/test-app-group-entitlements.sh が確かめる)
let appGroupIdentifier = "group.com.bannzai.poppo"

/// 読み取り結果を置くファイルの場所を返す。本体アプリが書き、キーボードが読む App Group の共有コンテナの中にある。
/// App Group を使えない時 (署名していないビルド等) は nil を返す
func latestReadingFileURL() -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
        .appendingPathComponent("latest-reading.json")
}

/// 読み取り結果を fileURL に保存する。前に保存した読み取り結果は上書きされ、残らない。
/// 書き込めない時はエラーを投げる
func save(latestReading: LatestReading, fileURL: URL) throws {
    // atomic: 書いている途中のファイルをキーボードが読まないようにするため
    try JSONEncoder().encode(latestReading).write(to: fileURL, options: .atomic)
}

/// fileURL に保存してある読み取り結果を返す。保存していない時と、読み取り結果として読めない中身の時は nil を返す
func loadLatestReading(fileURL: URL) -> LatestReading? {
    (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(LatestReading.self, from: $0) }
}

/// fileURL に保存してある読み取り結果を削除する。保存していない時は何もしない。
/// 削除できない時はエラーを投げる
func deleteLatestReading(fileURL: URL) throws {
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        return
    }
    try FileManager.default.removeItem(at: fileURL)
}

/// 読み取り結果が古いか。古い読み取り結果は、キーボードが色を変えて出す。
/// capturedAt は画面を読んだ時刻、now は今の時刻
func isStale(capturedAt: Date, now: Date) -> Bool {
    // 300 秒 (5 分): 読んだ後に相手の新しい発言が届いていてもおかしくない長さとして置いた値。
    // 実機で使った時の感覚を確かめて決め直す (documents/DIRECTION.md「決めたこと」)
    now.timeIntervalSince(capturedAt) >= 300
}
