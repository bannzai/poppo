import Foundation
import Testing
import UIKit

@testable import Poppo

/// チャットの画面の画像の見本 1 枚の記録。`ChatScreenSamples/chat-screen-samples.json` の 1 要素
private struct ChatScreenSample: Decodable, Sendable, CustomTestStringConvertible {
    /// 見本の画面に映っている 1 つの発言
    struct Message: Decodable, Sendable {
        /// 発言の文。画面で複数の行にわたる発言は、行を改行でつなぐ
        let text: String
        /// 利用者自身の発言か
        let isFromUser: Bool
    }

    /// 見本の画像のファイル名
    let imageFileName: String
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
    /// 今の実装で抜き出せない見本の、抜き出せない事実と理由。抜き出せる見本には無い
    let knownIssue: String?

    var testDescription: String { imageFileName }
}

/// テストのバンドル (見本の画像と記録が入っている) を `Bundle(for:)` で引くための型。
/// テストは本体アプリの中で動き、`Bundle.main` は本体アプリを指すため、テストのバンドルにある class が要る
private final class ChatScreenSampleBundleLocator {}

/// テストのバンドルにある、名前で指定したファイルの中身を返す。ファイルが無い時と読めない時はエラーを投げる
private func chatScreenSampleData(fileName: String) throws -> Data {
    try Data(
        contentsOf: try #require(
            Bundle(for: ChatScreenSampleBundleLocator.self).url(forResource: fileName, withExtension: nil),
            "テストのバンドルに \(fileName) がありません"
        )
    )
}

/// 見本の記録をすべて読んで返す。記録が無い時と、項目が欠けていて読めない時はエラーを投げる
private func chatScreenSamples() throws -> [ChatScreenSample] {
    try JSONDecoder().decode([ChatScreenSample].self, from: chatScreenSampleData(fileName: "chat-screen-samples.json"))
}

/// 見本の画像を Vision の実物で読み、抜き出した発言 (文と、利用者自身の発言か) が、記録に書いた画面の発言と一致すること。
/// 記録に抜き出せない理由 (`knownIssue`) がある見本は既知の不具合として扱い、抜き出せるようになった時に失敗して記録の直し忘れを知らせる。
/// simulator で Vision が固まった時に CI の制限時間まで待たないよう、1 分で打ち切る
@Test(.timeLimit(.minutes(1)), arguments: try chatScreenSamples())
private func chatScreenSampleGivesRecordedMessages(sample: ChatScreenSample) async throws {
    let messages = extractMessages(
        lines: try await recognizeTextLines(
            image: try #require(UIImage(data: try chatScreenSampleData(fileName: sample.imageFileName))?.cgImage)
        )
    )

    withKnownIssue(sample.knownIssue.map { Comment(rawValue: $0) }) {
        #expect(messages.map(\.text) == sample.messages.map(\.text))
        #expect(messages.map(\.isFromUser) == sample.messages.map(\.isFromUser))
    } when: {
        sample.knownIssue != nil
    }
}
