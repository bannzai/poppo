import AVFoundation
import Foundation
import Testing

@testable import Poppo

/// 見本のチャットの動画 (writeDebugSampleChatVideo) をテストごとの一時ファイルに書き出し、AVAsset として返す
private func writtenDebugSampleChatVideoAsset() async throws -> AVAsset {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "video-frame-selection-\(UUID().uuidString).mp4")
    try await writeDebugSampleChatVideo(fileURL: fileURL)
    return AVURLAsset(url: fileURL)
}

/// 動画の長さが、見本のチャットの画面の数 × 1 つの画面を映す秒数になること (書き出した動画を AVFoundation が読めること)
@Test func videoDurationSecondsOfDebugSampleChatVideo() async throws {
    #expect(
        try await videoDurationSeconds(asset: try await writtenDebugSampleChatVideoAsset())
            == Double(DebugSampleChat.allCases.count * debugSampleChatVideoSecondsPerChat)
    )
}

/// 動画から選んだ時刻の場面を読むと、その時刻に映っているチャットの画面の名前を読むこと。
/// 見本の動画は始まりから 1 秒が「# design-review」、続く 1 秒が「Harbor Books」の画面で、
/// 1 つ目と 2 つ目の画面の真ん中の時刻で読む (選んだ時刻と違う場面を読まないことを確かめるため)
@Test(arguments: zip(DebugSampleChat.allCases.indices, DebugSampleChat.allCases))
func recognizeTextLinesReadsSelectedVideoFrame(index: Int, sampleChat: DebugSampleChat) async throws {
    #expect(
        chatTitleReadFromScreen(
            lines: try await recognizeTextLines(
                videoAsset: try await writtenDebugSampleChatVideoAsset(),
                // 0.5: 1 つの画面を映す秒数の真ん中
                seconds: (Double(index) + 0.5) * Double(debugSampleChatVideoSecondsPerChat)
            )
        ) == sampleChat.title
    )
}

/// 動画の場面を画像にした大きさが、書き出した動画の大きさ (iPhone 17 Pro の画面のピクセル数) のままであること
/// (読み取りに使う場面を縮めないため)
@Test func videoFrameImageKeepsVideoSizeWithoutMaximumSize() async throws {
    // 0.5: 1 つ目のチャットの画面を映している間の時刻
    let image = try await videoFrameImage(asset: try await writtenDebugSampleChatVideoAsset(), seconds: 0.5, maximumSize: .zero)

    #expect(image.width == Int(DebugSampleScreenshotShape.portrait.pixelSize.width))
    #expect(image.height == Int(DebugSampleScreenshotShape.portrait.pixelSize.height))
}

/// 動画を選んだ時に最初に見せる場面は真ん中で、長さが 0 か読めない値の時は始まりにすること
@Test func initialVideoFrameSecondsIsMiddleOfVideo() {
    #expect(initialVideoFrameSeconds(durationSeconds: 10) == 5)
    #expect(initialVideoFrameSeconds(durationSeconds: 0) == 0)
    #expect(initialVideoFrameSeconds(durationSeconds: .nan) == 0)
    #expect(initialVideoFrameSeconds(durationSeconds: .infinity) == 0)
}

/// 場面の時刻の文が「分:秒」で、負の値と読めない値は 0 秒として出すこと
@Test func videoTimeTextFormatsMinuteSecond() {
    #expect(videoTimeText(seconds: 0) == "0:00")
    #expect(videoTimeText(seconds: 75) == "1:15")
    #expect(videoTimeText(seconds: -3) == "0:00")
    #expect(videoTimeText(seconds: .nan) == "0:00")
}
