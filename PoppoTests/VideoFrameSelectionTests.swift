import AVFoundation
import Foundation
import Photos
import Synchronization
import Testing

@testable import Poppo

/// 見本のチャットの動画 (writeDebugSampleChatVideo) をテストごとの一時ファイルに書き出し、AVURLAsset として返す
private func writtenDebugSampleChatVideoAsset() async throws -> AVURLAsset {
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

/// 場面を選べる長さは、0 より大きい有限の秒だけで、0 以下・NaN・無限大は選べない (場面を選ぶ範囲を作れないため)
@Test func selectableVideoDurationSecondsAcceptsOnlyPositiveFiniteDuration() {
    #expect(selectableVideoDurationSeconds(durationSeconds: 2) == 2)
    #expect(selectableVideoDurationSeconds(durationSeconds: 0.001) == 0.001)
    #expect(selectableVideoDurationSeconds(durationSeconds: 0) == nil)
    #expect(selectableVideoDurationSeconds(durationSeconds: -1) == nil)
    #expect(selectableVideoDurationSeconds(durationSeconds: .nan) == nil)
    #expect(selectableVideoDurationSeconds(durationSeconds: .infinity) == nil)
}

/// 動画でないファイルの場面を読もうとすると、読み取りの画面が読めなかった表示にするエラー (imageUnavailable) を投げること
@Test func recognizeTextLinesThrowsImageUnavailableForNonVideoFile() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "video-frame-selection-not-video-\(UUID().uuidString).mp4")
    try Data("not a video".utf8).write(to: fileURL)

    await #expect(throws: ChatReadingError.imageUnavailable) {
        try await recognizeTextLines(videoAsset: AVURLAsset(url: fileURL), seconds: 0)
    }
}

/// Slider で選べる範囲の始まり (0 秒) は 1 つ目のチャットの画面を、1 つ目と 2 つ目の画面の境目 (1 秒) は 2 つ目の画面を読むこと
@Test func recognizeTextLinesReadsFramesAtBoundaries() async throws {
    let asset = try await writtenDebugSampleChatVideoAsset()

    #expect(chatTitleReadFromScreen(lines: try await recognizeTextLines(videoAsset: asset, seconds: 0)) == DebugSampleChat.allCases[0].title)
    #expect(
        chatTitleReadFromScreen(lines: try await recognizeTextLines(videoAsset: asset, seconds: Double(debugSampleChatVideoSecondsPerChat)))
            == DebugSampleChat.allCases[1].title
    )
}

/// Slider で選べる範囲の終わり (動画の長さちょうど) を選んでも、最後のチャットの画面を読むこと
@Test func recognizeTextLinesReadsLastFrameAtVideoEnd() async throws {
    let asset = try await writtenDebugSampleChatVideoAsset()

    #expect(
        chatTitleReadFromScreen(lines: try await recognizeTextLines(videoAsset: asset, seconds: try await videoDurationSeconds(asset: asset)))
            == DebugSampleChat.allCases[DebugSampleChat.allCases.count - 1].title
    )
}

/// 大きさの上限を渡すと、場面の画像を縦横の比を保ったまま上限の中に縮めること (一覧に見せる画像を大きく作らないため)
@Test func videoFrameImageFitsWithinMaximumSize() async throws {
    // 幅 300・高さ 300: 見本の動画 (1206 × 2622) より小さく、縦長の画像なら高さで縮む上限
    let image = try await videoFrameImage(asset: try await writtenDebugSampleChatVideoAsset(), seconds: 0.5, maximumSize: CGSize(width: 300, height: 300))

    #expect(image.height == 300)
    // 1206 × 2622 の比を保った幅は 300 × 1206 / 2622 ≒ 138。画像の大きさの丸めで 1 ずれてもよい
    #expect(abs(image.width - 138) <= 1)
}

/// 動画の読み出しの条件が、iCloud から取ることを許し、編集を当てる前の元の版 (縮めていない 1 つのファイル) を求め、取れた割合を渡すこと
@Test func videoRequestOptionsAllowNetworkAndOriginalVersion() throws {
    let receivedProgress = Mutex<[Double]>([])
    let options = videoRequestOptions(progress: { fractionCompleted in receivedProgress.withLock { $0.append(fractionCompleted) } })

    #expect(options.isNetworkAccessAllowed)
    #expect(options.version == .original)
    let progressHandler = try #require(options.progressHandler)
    var stop = ObjCBool(false)

    progressHandler(0.25, nil, &stop, nil)
    #expect(receivedProgress.withLock { $0 } == [0.25])
}

/// 読み出しの結果から画面の状態を決める判定が、動画と選べる長さがある時だけ読み出せた状態にし、ほかは失敗の状態にすること
@Test func videoFrameSelectionPhaseFailsWithoutAssetOrSelectableDuration() async throws {
    let asset = try await writtenDebugSampleChatVideoAsset()

    guard case .loaded(_, let durationSeconds) = videoFrameSelectionPhase(asset: asset, durationSeconds: 2) else {
        Issue.record("動画と長さがあるのに読み出せた状態にならなかった")
        return
    }
    #expect(durationSeconds == 2)
    for (testAsset, testDurationSeconds) in [(nil, 2), (asset, nil), (asset, 0), (asset, .nan), (asset, .infinity)] as [(AVURLAsset?, Double?)] {
        guard case .failed = videoFrameSelectionPhase(asset: testAsset, durationSeconds: testDurationSeconds) else {
            Issue.record("動画 \(testAsset == nil ? "なし" : "あり")・長さ \(String(describing: testDurationSeconds)) で失敗の状態にならなかった")
            continue
        }
    }
}

/// 進み具合は読み込み中の時だけ反映し、読み出しが終わった後 (読み出せた・失敗した) に届いた進み具合では状態を変えないこと
@Test func videoFrameSelectionPhaseAfterProgressUpdatesOnlyWhileLoading() async throws {
    guard case .loading(let progress) = videoFrameSelectionPhaseAfterProgress(current: .loading(progress: nil), progress: 0.5) else {
        Issue.record("読み込み中に進み具合が反映されなかった")
        return
    }
    #expect(progress == 0.5)
    guard case .failed = videoFrameSelectionPhaseAfterProgress(current: .failed, progress: 0.5) else {
        Issue.record("失敗の後に届いた進み具合で状態が変わった")
        return
    }
    guard
        case .loaded(_, let durationSeconds) = videoFrameSelectionPhaseAfterProgress(
            current: .loaded(asset: try await writtenDebugSampleChatVideoAsset(), durationSeconds: 2),
            progress: 0.5
        )
    else {
        Issue.record("読み出せた後に届いた進み具合で状態が変わった")
        return
    }
    #expect(durationSeconds == 2)
}

/// 「この場面を読み取る」は、出している場面が選んだ時刻のものの時だけ押せること
@Test func canReadVideoFrameOnlyWhenPreviewMatchesSelection() {
    #expect(canReadVideoFrame(previewSeconds: 1, selectedSeconds: 1))
    #expect(canReadVideoFrame(previewSeconds: 0, selectedSeconds: 0))
    // Slider を動かした直後 (前の時刻の場面を出している間)
    #expect(!canReadVideoFrame(previewSeconds: 1, selectedSeconds: 1.5))
    // 場面の画像がまだ無い・作れなかった時
    #expect(!canReadVideoFrame(previewSeconds: nil, selectedSeconds: 1))
}

/// 見本の動画を同じファイルに 2 回書き出しても失敗せず、2 回目の動画も読めること (開発者メニューの操作を冪等にするため)
@Test func writeDebugSampleChatVideoReplacesExistingFile() async throws {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "video-frame-selection-replace-\(UUID().uuidString).mp4")

    try await writeDebugSampleChatVideo(fileURL: fileURL)
    try await writeDebugSampleChatVideo(fileURL: fileURL)

    #expect(
        try await videoDurationSeconds(asset: AVURLAsset(url: fileURL))
            == Double(DebugSampleChat.allCases.count * debugSampleChatVideoSecondsPerChat)
    )
}
