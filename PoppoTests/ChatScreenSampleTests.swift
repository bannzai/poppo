import Foundation
import Testing
import UIKit

@testable import Poppo

/// チャットの画面の画像の見本 1 枚の記録。`ChatScreenSamples/chat-screen-samples.json` の 1 要素
nonisolated private struct ChatScreenSample: Decodable, Sendable, CustomTestStringConvertible {
    /// 見本の画面に映っている 1 つの発言
    struct Message: Decodable, Sendable {
        /// 発言の文。画面で複数の行にわたる発言は、行を改行でつなぐ
        let text: String
        /// 利用者自身の発言か
        let isFromUser: Bool
    }

    /// 見本の画像のファイル名
    let imageFileName: String
    /// 画面の上部 (ナビゲーションバー) に出ているチャットの名前。期待するチャットの名前の読み取りの結果
    let chatTitle: String
    /// 発言の見出し (名前と時刻) に出ている、発言した人の名前。画面の上から下の順で、同じ名前は 1 つ。
    /// 見出しの無い吹き出しのチャットは空 (本文を名前として読まないことを確かめる)
    let speakerNames: [String]
    /// 発言した人の名前を記録どおりに読めない理由 (Vision の読み違い等)。読める見本は nil (JSON にキーを書かない)
    let speakerNamesKnownIssue: String?
    /// 画面の見た目 (どのチャットアプリに似せたか、何が映っているか)
    let appearance: String
    /// 発言の言語 (BCP 47 の言語コード)
    let language: String
    /// 出どころ (作った画像か、取ってきた URL)
    let source: String
    /// 利用の条件 (分かる範囲)
    let usageTerms: String
    /// 画面に映っている発言。上から下の順。期待する抜き出しの結果
    let messages: [Message]
    /// 画面に映っているが発言でない行の文字 (日付の区切り・既読・スレッドの返信の数)。抜き出した発言のどの行にも入らないことを確かめる
    let nonMessageTexts: [String]
    /// 今の実装で抜き出せない見本の、抜き出せない事実と理由。抜き出せる見本には無い
    let knownIssue: String?

    /// テストの結果の一覧で、引数の見本を見分けるための名前。見本の画像のファイル名を返す
    var testDescription: String { imageFileName }
}

/// テストのバンドル (見本の画像と記録が入っている) を `Bundle(for:)` で引くための型。
/// テストは本体アプリの中で動き、`Bundle.main` は本体アプリを指すため、テストのバンドルにある class が要る
nonisolated private final class ChatScreenSampleBundleLocator {}

/// テストのバンドルにある、名前で指定したファイルの中身を返す。ファイルが無い時と読めない時はエラーを投げる。
/// `@Test` の `arguments` は main actor の外で評価されるため、見本を読む関数と型は nonisolated にする (このターゲットの既定は main actor)
nonisolated private func chatScreenSampleData(fileName: String) throws -> Data {
    try Data(
        contentsOf: try #require(
            Bundle(for: ChatScreenSampleBundleLocator.self).url(forResource: fileName, withExtension: nil),
            "テストのバンドルに \(fileName) がありません"
        )
    )
}

/// 見本の記録をすべて読んで返す。記録が無い時と、項目が欠けていて読めない時はエラーを投げる
nonisolated private func chatScreenSamples() throws -> [ChatScreenSample] {
    try JSONDecoder().decode([ChatScreenSample].self, from: chatScreenSampleData(fileName: "chat-screen-samples.json"))
}

/// 見本の画像を Vision の実物で読み、抜き出した発言 (文と、利用者自身の発言か) が、記録に書いた画面の発言と一致すること。
/// 記録に抜き出せない理由 (`knownIssue`) がある見本は既知の不具合として扱い、抜き出せるようになった時に失敗して記録の直し忘れを知らせる。
/// 発言の数と、発言でない行 (`nonMessageTexts`) が発言に入らないことは、文字の読み違いに左右されないため、既知の不具合がある見本でも確かめる。
/// simulator で Vision が固まった時に CI の制限時間まで待たないよう、1 分で打ち切る
@Test(.timeLimit(.minutes(1)), arguments: try chatScreenSamples())
private func chatScreenSampleGivesRecordedMessages(sample: ChatScreenSample) async throws {
    let messages = extractMessages(
        lines: try await recognizeTextLines(
            image: try #require(UIImage(data: try chatScreenSampleData(fileName: sample.imageFileName))?.cgImage)
        )
    )

    #expect(messages.count == sample.messages.count)
    #expect(
        messages.flatMap { $0.text.split(separator: "\n").map(String.init) }.filter { sample.nonMessageTexts.contains($0) }.isEmpty
    )

    withKnownIssue(sample.knownIssue.map { Comment(rawValue: $0) }) {
        #expect(messages.map(\.text) == sample.messages.map(\.text))
        #expect(messages.map(\.isFromUser) == sample.messages.map(\.isFromUser))
    } when: {
        sample.knownIssue != nil
    }
}

/// 見本の画像を Vision の実物で読み、画面の上部から読んだチャットの名前が、記録に書いたチャットの名前と同じ相手を指すこと
/// (別のスクリーンショットの名前と比べる形 comparableClueText(text:) で比べる。戻るボタンの「‹」や空白の読み違いで名前が変わらないことも確かめる)。
/// ステータスバーの時刻・電波の文字 (「9:41」「5G」) を名前にしないことも、この比較で確かめる
@Test(.timeLimit(.minutes(1)), arguments: try chatScreenSamples())
private func chatScreenSampleGivesRecordedChatTitle(sample: ChatScreenSample) async throws {
    #expect(
        chatTitleReadFromScreen(
            lines: try await recognizeTextLines(
                image: try #require(UIImage(data: try chatScreenSampleData(fileName: sample.imageFileName))?.cgImage)
            )
        ).map { comparableClueText(text: $0) } == comparableClueText(text: sample.chatTitle)
    )
}

/// 見本の画像を Vision の実物で読み、見出しから読んだ発言した人の名前が、記録に書いた名前と同じ人を指すこと (comparableClueText(text:) の形で比べる)。
/// 吹き出しのチャット (時刻が吹き出しの中に付くものを含む) では、本文を名前として読まないこと
@Test(.timeLimit(.minutes(1)), arguments: try chatScreenSamples())
private func chatScreenSampleGivesRecordedSpeakerNames(sample: ChatScreenSample) async throws {
    let lines = try await recognizeTextLines(
        image: try #require(UIImage(data: try chatScreenSampleData(fileName: sample.imageFileName))?.cgImage)
    )
    // 読み違いの理由 (speakerNamesKnownIssue) がある見本は既知の不具合として扱い、読めるようになった時に失敗して記録の直し忘れを知らせる
    withKnownIssue(sample.speakerNamesKnownIssue.map { Comment(rawValue: $0) }) {
        // 失敗した時に、Vision が読んだ行の文字と枠を出す (名前と時刻をどう分けて読んだかを確かめるため)
        #expect(
            speakerNames(lines: lines).map { comparableClueText(text: $0) } == sample.speakerNames.map { comparableClueText(text: $0) },
            Comment(rawValue: lines.map { "\($0.text) \($0.boundingBox)" }.joined(separator: "\n"))
        )
    } when: {
        sample.speakerNamesKnownIssue != nil
    }
}
