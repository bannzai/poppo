import Foundation
import Testing
@testable import Poppo

/// テストごとに別の、まだ何も置いていないファイルの場所を返す。テストどうしが同じファイルを読み書きしないようにする
func temporaryFileURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
}

/// テストで保存する読み取り結果。capturedAt は読んだ時刻、label は発言と返信案の文に入れて、どの読み取り結果かを見分ける文字列
func sampleLatestReading(capturedAt: Date, label: String) -> LatestReading {
    LatestReading(
        capturedAt: capturedAt,
        messages: [
            TranslatedMessage(originalText: "\(label) original 1", translatedText: "\(label) 訳 1"),
            TranslatedMessage(originalText: "\(label) original 2", translatedText: "\(label) 訳 2"),
        ],
        replySuggestions: [ReplySuggestion(text: "\(label) reply", meaning: "\(label) 返信の意味")]
    )
}

/// 保存した読み取り結果を読み出すと、読んだ時刻・発言の順と中身・返信案が保存した時と同じ値で返ること
@Test func savedLatestReadingLoadsWithSameValues() throws {
    let fileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1000.5), label: "first"), fileURL: fileURL)

    let loaded = try #require(loadLatestReading(fileURL: fileURL))
    #expect(loaded.capturedAt == Date(timeIntervalSinceReferenceDate: 1000.5))
    #expect(loaded.messages.map(\.originalText) == ["first original 1", "first original 2"])
    #expect(loaded.messages.map(\.translatedText) == ["first 訳 1", "first 訳 2"])
    #expect(loaded.replySuggestions.map(\.text) == ["first reply"])
    #expect(loaded.replySuggestions.map(\.meaning) == ["first 返信の意味"])
}

/// 何も保存していない時は、読み出しが nil を返すこと
@Test func latestReadingIsNilWhenNothingIsSaved() {
    #expect(loadLatestReading(fileURL: temporaryFileURL()) == nil)
}

/// 削除の後は読み出せないこと
@Test func latestReadingIsNilAfterDelete() throws {
    let fileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), label: "first"), fileURL: fileURL)

    try deleteLatestReading(fileURL: fileURL)

    #expect(loadLatestReading(fileURL: fileURL) == nil)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
}

/// 何も保存していない時に削除しても、エラーにならないこと (削除を何度呼んでも同じ結果になる)
@Test func deletingLatestReadingTwiceDoesNotFail() throws {
    let fileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), label: "first"), fileURL: fileURL)

    try deleteLatestReading(fileURL: fileURL)
    try deleteLatestReading(fileURL: fileURL)

    #expect(loadLatestReading(fileURL: fileURL) == nil)
}

/// 2 回保存すると後の値だけが残ること (持つのは最新の 1 つだけ)
@Test func secondSaveReplacesFirstLatestReading() throws {
    let fileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), label: "first"), fileURL: fileURL)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 2000), label: "second"), fileURL: fileURL)

    let loaded = try #require(loadLatestReading(fileURL: fileURL))
    #expect(loaded.capturedAt == Date(timeIntervalSinceReferenceDate: 2000))
    #expect(loaded.messages.map(\.originalText) == ["second original 1", "second original 2"])
    #expect(loaded.replySuggestions.map(\.text) == ["second reply"])
    #expect(try !String(contentsOf: fileURL, encoding: .utf8).contains("first"))
}

/// 読み取り結果として読めない中身のファイルは、読み出しが nil を返すこと (キーボードが壊れた内容を表示しない)
@Test func latestReadingIsNilWhenFileIsNotALatestReading() throws {
    let fileURL = temporaryFileURL()
    try Data("{\"capturedAt\": 1000}".utf8).write(to: fileURL)

    #expect(loadLatestReading(fileURL: fileURL) == nil)
}

/// 保存するファイルの形 (項目の名前と、時刻の表し方) が変わっていないこと。
/// 本体アプリとキーボードは同じファイルを読むため、形を変えると片方が読めなくなる
@Test func latestReadingFileFormatIsStable() throws {
    let fileURL = temporaryFileURL()
    try Data(
        """
        {
          "capturedAt": 1000.5,
          "messages": [{"originalText": "Hello", "translatedText": "こんにちは"}],
          "replySuggestions": [{"text": "Hi", "meaning": "やあ"}]
        }
        """.utf8
    ).write(to: fileURL)

    let loaded = try #require(loadLatestReading(fileURL: fileURL))
    #expect(loaded.capturedAt == Date(timeIntervalSinceReferenceDate: 1000.5))
    #expect(loaded.messages.map(\.originalText) == ["Hello"])
    #expect(loaded.messages.map(\.translatedText) == ["こんにちは"])
    #expect(loaded.replySuggestions.map(\.text) == ["Hi"])
    #expect(loaded.replySuggestions.map(\.meaning) == ["やあ"])
}

/// 読んでから 5 分 (300 秒) 経っていない読み取り結果は、古い扱いにならないこと
@Test func latestReadingIsNotStaleBeforeFiveMinutes() {
    #expect(!isStale(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), now: Date(timeIntervalSinceReferenceDate: 1000)))
    #expect(!isStale(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), now: Date(timeIntervalSinceReferenceDate: 1299.9)))
}

/// 読んでからちょうど 5 分 (300 秒) 以上経った読み取り結果は、古い扱いになること
@Test func latestReadingIsStaleFromFiveMinutes() {
    #expect(isStale(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), now: Date(timeIntervalSinceReferenceDate: 1300)))
    #expect(isStale(capturedAt: Date(timeIntervalSinceReferenceDate: 1000), now: Date(timeIntervalSinceReferenceDate: 9000)))
}

/// 読んだ時刻が今より後 (端末の時計を戻した時) の読み取り結果は、古い扱いにならないこと
@Test func latestReadingCapturedInTheFutureIsNotStale() {
    #expect(!isStale(capturedAt: Date(timeIntervalSinceReferenceDate: 2000), now: Date(timeIntervalSinceReferenceDate: 1000)))
}
