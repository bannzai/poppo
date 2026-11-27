import AVFoundation
import Photos
import SwiftUI

/// 写真ライブラリの動画 (video) を、再生や読み出しに使える AVAsset として読み出す。読み出せない時は nil を返す。
/// 端末に無い時は iCloud から取る (利用者が読み取る 1 本として選んだ動画のため。documents/DIRECTION.md「決めたこと」2026-11-27 の、タップした 1 枚を取る行と同じ扱い)
@concurrent nonisolated func loadVideoAsset(video: PHAsset) async -> AVAsset? {
    await withCheckedContinuation { continuation in
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        // 読み取る場面の小さい文字を、縮めた動画から読まないため。PHImageManager.h: 既定の automatic は iCloud から取る AVAsset で
        // 「typ. PHVideoRequestOptionsDeliveryModeMediumQualityFormat」(720p 前後) を選び、highQualityFormat は「best quality」
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestAVAsset(forVideo: video, options: options) { asset, _, _ in
            continuation.resume(returning: asset)
        }
    }
}

/// 動画 (asset) の長さを秒で返す
@concurrent nonisolated func videoDurationSeconds(asset: AVAsset) async throws -> Double {
    try await asset.load(.duration).seconds
}

/// 動画 (asset) の、始まりから seconds 秒の場面を画像にして返す。maximumSize は画像の大きさの上限で、.zero は動画の大きさのまま。
/// 指定した時刻からずれた場面を返さない (一覧で見せた場面と、読み取る場面を同じにするため)。画像にできない時は AVFoundation のエラーを投げる
@concurrent nonisolated func videoFrameImage(asset: AVAsset, seconds: Double, maximumSize: CGSize) async throws -> CGImage {
    let generator = AVAssetImageGenerator(asset: asset)
    // 縦向きで撮った画面収録が横に倒れた画像にならないよう、動画の向きの情報を当てる
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.maximumSize = maximumSize
    // 600: 24・25・30・60 の公倍数で、これらの fps の動画の 1 コマの時刻をどれも整数で表せるため
    return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
}

/// 動画 (asset) の始まりから seconds 秒の場面を画像にし、写っている文字を行ごとに読んで返す。
/// 画像にできない時は ChatReadingError.imageUnavailable を、ほかは recognizeTextLines(image:) と同じエラーを投げる
func recognizeTextLines(videoAsset: AVAsset, seconds: Double) async throws -> [RecognizedTextLine] {
    // .zero: 動画の大きさのまま読む (縮めると小さい文字を読めなくなるため)
    guard let image = try? await videoFrameImage(asset: videoAsset, seconds: seconds, maximumSize: .zero) else {
        throw ChatReadingError.imageUnavailable
    }
    return try await recognizeTextLines(image: image)
}

/// 動画を選んだ時に、最初に見せる場面の時刻 (秒) を返す。durationSeconds は動画の長さ。
/// 真ん中にする: 画面収録はコントロールセンターから始めて止めるため、始まりと終わりの場面にはコントロールセンターが写りやすい
/// (Apple の画面収録の手順: 「In Control Center, you can start a screen recording」「Or open Control Center and tap the red Record button」
/// https://support.apple.com/en-us/102653 2026-11-27 に読んだ)
nonisolated func initialVideoFrameSeconds(durationSeconds: Double) -> Double {
    durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds / 2 : 0
}

/// 秒 (seconds) を、場面を選ぶ画面に出す「分:秒」の文にして返す
nonisolated func videoTimeText(seconds: Double) -> String {
    Duration.seconds(seconds.isFinite ? max(seconds, 0) : 0).formatted(.time(pattern: .minuteSecond))
}

/// 動画の場面を選ぶ画面の状態
enum VideoFrameSelectionPhase {
    /// 動画を読み出している
    case loading
    /// 動画を読み出せた。asset は動画、durationSeconds はその長さ
    case loaded(asset: AVAsset, durationSeconds: Double)
    /// 動画を読み出せなかった
    case failed
}

/// 写真ライブラリの動画から、読み取る場面を選ぶ画面。選んだ場面の画像を、スクリーンショットと同じ読み取りの画面で読む。
/// 動画は 1 回に 1 つの場面だけを読む (動画の全体を読み、会話が変わった所ごとに分ける使い方は、読み取った時点を残す仕組みと一緒に決めるため。
/// documents/DIRECTION.md「決めたこと」2026-11-27 の動画の行)
struct VideoFrameSelectionView: View {
    /// 選んだ動画
    let video: PHAsset
    /// 画面の状態
    @State private var phase = VideoFrameSelectionPhase.loading
    /// 選んでいる場面の時刻 (動画の始まりからの秒)
    @State private var selectedSeconds: Double = 0
    /// 選んでいる場面の画像。まだ画像にしていない時と、画像にできなかった時は nil
    @State private var previewImage: CGImage?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                // ja: 動画を読み込んでいます
                ProgressView("Loading the video")
            case .failed:
                // ja: この動画を読み込めませんでした
                ContentUnavailableView("Couldn't load this video", systemImage: "exclamationmark.triangle")
            case .loaded(let asset, let durationSeconds):
                VStack(spacing: 16) {
                    Group {
                        if let previewImage {
                            Image(decorative: previewImage, scale: 1)
                                .resizable()
                                .scaledToFit()
                        } else {
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("video_frame_preview")
                    VStack(spacing: 4) {
                        Slider(value: $selectedSeconds, in: 0...max(durationSeconds, 0)) {
                            // ja: 読み取る場面
                            Text("Frame to read")
                        }
                        .accessibilityIdentifier("video_frame_slider")
                        Text(verbatim: "\(videoTimeText(seconds: selectedSeconds)) / \(videoTimeText(seconds: durationSeconds))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        ChatReadingView(
                            screenshot: video,
                            recognizeTextLines: { [selectedSeconds] in try await recognizeTextLines(videoAsset: asset, seconds: selectedSeconds) },
                            readChatContent: { try await readChat(lines: $0) }
                        )
                    } label: {
                        // ja: この場面を読み取る
                        Text("Read this frame")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("video_frame_read_button")
                }
                .padding()
                // 場面を選び直すたびに、その場面の画像を作り直す。前の場面の画像を作っている途中なら、その結果は捨てる
                .task(id: selectedSeconds) {
                    // 幅 1206・高さ 2622: iPhone 17 Pro の画面のピクセル数。画面に収めて見せるだけなので、これより大きい画像は作らない
                    let image = try? await videoFrameImage(asset: asset, seconds: selectedSeconds, maximumSize: CGSize(width: 1206, height: 2622))
                    if !Task.isCancelled {
                        previewImage = image
                    }
                }
            }
        }
        // ja: 場面を選ぶ
        .navigationTitle("Pick a frame")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: video.localIdentifier) {
            guard case .loading = phase else {
                return
            }
            guard let asset = await loadVideoAsset(video: video), let durationSeconds = try? await videoDurationSeconds(asset: asset) else {
                phase = .failed
                return
            }
            selectedSeconds = initialVideoFrameSeconds(durationSeconds: durationSeconds)
            phase = .loaded(asset: asset, durationSeconds: durationSeconds)
        }
    }
}
