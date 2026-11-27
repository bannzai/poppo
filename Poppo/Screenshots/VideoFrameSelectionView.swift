import AVFoundation
import Photos
import SwiftUI

/// 写真ライブラリの動画 (video) を、1 つのファイルの動画 (AVURLAsset) として読み出す。読み出せない時と、
/// 写真ライブラリが AVURLAsset 以外の AVAsset を返した時は nil を返す (AVURLAsset は AVFoundation が Sendable と宣言していて、
/// 場面を画像にする処理へ渡せるが、AVAsset は宣言していないため。どの動画で AVURLAsset 以外が返るかは Apple の文書に記述が無く未確認)。
/// 端末に無い時は iCloud から取る (利用者が読み取る 1 本として選んだ動画のため。documents/DIRECTION.md「決めたこと」2026-11-27 の、タップした 1 枚を取る行と同じ扱い)。
/// iCloud から取っている間は、取れた割合 (0 から 1) を progress に渡す (写真ライブラリが決めた別のキューから呼ばれる)
@concurrent nonisolated func loadVideoAsset(video: PHAsset, progress: @escaping @Sendable (Double) -> Void) async -> AVURLAsset? {
    await withCheckedContinuation { continuation in
        PHImageManager.default().requestAVAsset(forVideo: video, options: videoRequestOptions(progress: progress)) { asset, _, _ in
            continuation.resume(returning: asset as? AVURLAsset)
        }
    }
}

/// loadVideoAsset が写真ライブラリへ渡す読み出しの条件。編集を当てる前の元の版を求め、iCloud から取ることを許し、取れた割合を progress に渡す
nonisolated func videoRequestOptions(progress: @escaping @Sendable (Double) -> Void) -> PHVideoRequestOptions {
    let options = PHVideoRequestOptions()
    options.isNetworkAccessAllowed = true
    // 編集を当てる前の元の動画を求める。既定の current は編集を当てた版で、写真ライブラリが AVURLAsset 以外 (編集を合成した AVAsset) を
    // 返しうる (PHImageManager.h の requestAVAsset の結果の型は AVAsset)。loadVideoAsset は AVURLAsset しか受け取れないため、
    // 1 つのファイルになっている元の版を読む。切り取りなどの編集は場面を選ぶ画面に出ない (チャットの画面を読むのに編集は要らないため)。
    // 元の版は縮めていない動画のため、読み取る場面の小さい文字も読める (PHImageManager.h: 質を選ぶ deliveryMode は
    // 「only apply with PHVideoRequestOptionsVersionCurrent」で、元の版には効かない)。元の版でも AVURLAsset が返るかは実機で確かめていない
    options.version = .original
    options.progressHandler = { fractionCompleted, _, _, _ in
        progress(fractionCompleted)
    }
    return options
}

/// 動画 (asset) の長さを秒で返す
@concurrent nonisolated func videoDurationSeconds(asset: AVURLAsset) async throws -> Double {
    try await asset.load(.duration).seconds
}

/// 動画 (asset) の、始まりから seconds 秒の場面を画像にして返す。maximumSize は画像の大きさの上限で、.zero は動画の大きさのまま。
/// 指定した時刻からずれた場面を返さない (一覧で見せた場面と、読み取る場面を同じにするため)。画像にできない時は AVFoundation のエラーを投げる
@concurrent nonisolated func videoFrameImage(asset: AVURLAsset, seconds: Double, maximumSize: CGSize) async throws -> CGImage {
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
func recognizeTextLines(videoAsset: AVURLAsset, seconds: Double) async throws -> [RecognizedTextLine] {
    // .zero: 動画の大きさのまま読む (縮めると小さい文字を読めなくなるため)
    guard let image = try? await videoFrameImage(asset: videoAsset, seconds: seconds, maximumSize: .zero) else {
        throw ChatReadingError.imageUnavailable
    }
    return try await recognizeTextLines(image: image)
}

/// 動画の長さ (durationSeconds。AVFoundation が返した秒) が、場面を選べる長さなら、その長さを返す。
/// 長さが 0 以下と、有限でない (NaN・無限大。長さの決まらない動画で AVFoundation が返しうる) 時は nil を返す (場面を選ぶ範囲を作れないため)
nonisolated func selectableVideoDurationSeconds(durationSeconds: Double) -> Double? {
    durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : nil
}

/// 動画を選んだ時に、最初に見せる場面の時刻 (秒) を返す。durationSeconds は動画の長さ。
/// 真ん中にする: 画面収録はコントロールセンターから始めて止めるため、始まりと終わりの場面にはコントロールセンターが写りやすい
/// (Apple の画面収録の手順: 「In Control Center, you can start a screen recording」「Or open Control Center and tap the red Record button」
/// https://support.apple.com/en-us/102653 2026-11-27 に読んだ)
/// 長さが 0 以下か有限でない時は 0 (動画の始まり) を返す。始まりは長さによらず必ずある時刻のため
nonisolated func initialVideoFrameSeconds(durationSeconds: Double) -> Double {
    durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds / 2 : 0
}

/// 秒 (seconds) を、場面を選ぶ画面に出す「分:秒」の文にして返す。負の値と有限でない値は 0 秒として出す
/// (場面の時刻は動画の始まりより前にならず、読めない値を「0:00」より意味のある時刻で出す手段が無いため)
nonisolated func videoTimeText(seconds: Double) -> String {
    Duration.seconds(seconds.isFinite ? max(seconds, 0) : 0).formatted(.time(pattern: .minuteSecond))
}

/// 動画の読み出しの結果から、場面を選ぶ画面の状態を返す。asset は読み出した動画 (読み出せなかった時は nil)、
/// durationSeconds は AVFoundation が返した長さ (取れなかった時は nil)。動画が無い・長さが無い・場面を選べる長さでない時は .failed
nonisolated func videoFrameSelectionPhase(asset: AVURLAsset?, durationSeconds: Double?) -> VideoFrameSelectionPhase {
    guard let asset, let selectableDurationSeconds = durationSeconds.flatMap({ selectableVideoDurationSeconds(durationSeconds: $0) }) else {
        return .failed
    }
    return .loaded(asset: asset, durationSeconds: selectableDurationSeconds)
}

/// 読み出しの進み具合 (progress。0 から 1) が届いた時の、場面を選ぶ画面の状態を返す。current は届いた時の状態。
/// 読み込み中の時だけ進み具合を反映し、ほかの状態ではそのまま返す (読み出しが終わった後に遅れて届いた割合で、読み込み中の表示に戻さないため)
nonisolated func videoFrameSelectionPhaseAfterProgress(current: VideoFrameSelectionPhase, progress: Double) -> VideoFrameSelectionPhase {
    if case .loading = current {
        return .loading(progress: progress)
    }
    return current
}

/// 「この場面を読み取る」を押せるかを返す。previewSeconds は画面に出している場面の時刻 (場面の画像をまだ作っていない時は nil)、
/// previewHasImage はその時刻の場面を画像にできたか、selectedSeconds は Slider で選んでいる時刻。
/// 出している場面が選んだ時刻のもので、画像にできた時だけ押せる (見ている場面と違う場面と、画像にできない場面を読まないため)
nonisolated func canReadVideoFrame(previewSeconds: Double?, previewHasImage: Bool, selectedSeconds: Double) -> Bool {
    previewHasImage && previewSeconds == selectedSeconds
}

/// 動画の場面を選ぶ画面の状態
nonisolated enum VideoFrameSelectionPhase {
    /// 動画を読み出している。progress は iCloud から取れた割合 (0 から 1)。iCloud から取っていない間は nil
    case loading(progress: Double?)
    /// 動画を読み出せた。asset は動画、durationSeconds はその長さ (selectableVideoDurationSeconds を通した、0 より大きい有限の秒)
    case loaded(asset: AVURLAsset, durationSeconds: Double)
    /// 動画を読み出せなかった (iCloud から取れなかった・写真ライブラリが AVURLAsset 以外を返した・場面を選べる長さでない)
    case failed
}

/// 写真ライブラリの動画から、読み取る場面を選ぶ画面。選んだ場面の画像を、スクリーンショットと同じ読み取りの画面で読む。
/// 動画は 1 回に 1 つの場面だけを読む (動画の全体を読み、会話が変わった所ごとに分ける使い方は、読み取った時点を残す仕組みと一緒に決めるため。
/// documents/DIRECTION.md「決めたこと」2026-11-27 の動画の行)
struct VideoFrameSelectionView: View {
    /// 選んだ動画
    let video: PHAsset
    /// 画面の状態
    @State private var phase = VideoFrameSelectionPhase.loading(progress: nil)
    /// 動画を読み出した回数。読み込めなかった時のやり直しのボタンを押すと増やし、読み出しをやり直す
    @State private var loadAttempt = 0
    /// 選んでいる場面の時刻 (動画の始まりからの秒)
    @State private var selectedSeconds: Double = 0
    /// 画面に出している場面の画像 (image) と、その場面の時刻 (seconds。動画の始まりからの秒)。まだ画像にしていない時は nil。
    /// 画像にできなかった時は image が nil (その時刻の場面を読めないことを画面に出すため)。
    /// 時刻を画像と組で持つのは、出している場面が選んだ時刻 (selectedSeconds) のものかを、読み取るボタンで見分けるため
    @State private var preview: (image: CGImage?, seconds: Double)?

    var body: some View {
        Group {
            switch phase {
            case .loading(let progress):
                // ja: 動画を読み込んでいます
                ProgressView("Loading the video", value: progress)
                    .padding()
                    .accessibilityIdentifier("video_loading_progress")
            case .failed:
                ContentUnavailableView {
                    // ja: この動画を読み込めませんでした
                    Label("Couldn't load this video", systemImage: "exclamationmark.triangle")
                } description: {
                    // ja: iCloud にある動画は通信できる時にもう一度読み込んでください
                    Text("If the video is in iCloud try again when you're online")
                } actions: {
                    Button {
                        phase = .loading(progress: nil)
                        loadAttempt += 1
                    } label: {
                        // ja: もう一度試す
                        Text("Try again")
                    }
                    .accessibilityIdentifier("video_load_retry_button")
                }
            case .loaded(let asset, let durationSeconds):
                // 16: 場面の画像・Slider・読み取るボタンの 3 つの塊の間を、塊の中 (Slider と時刻の間の 4) より広げて塊ごとに見分けるため
                VStack(spacing: 16) {
                    Group {
                        if let previewImage = preview?.image {
                            Image(decorative: previewImage, scale: 1)
                                .resizable()
                                .scaledToFit()
                        } else if preview?.seconds == selectedSeconds {
                            // ja: この場面を画像にできませんでした
                            //
                            // ja: ほかの時刻を選んでください
                            ContentUnavailableView(
                                "Couldn't make an image of this frame",
                                systemImage: "exclamationmark.triangle",
                                description: Text("Pick another time")
                            )
                            .accessibilityIdentifier("video_frame_unavailable")
                        } else {
                            Color(uiColor: .secondarySystemBackground)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("video_frame_preview")
                    // 4: 時刻の文を、その時刻を選ぶ Slider の注記として近くに置くため
                    VStack(spacing: 4) {
                        Slider(value: $selectedSeconds, in: 0...durationSeconds) {
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
                    // 出している場面が選んだ時刻と違う間 (Slider を動かして、新しい場面の画像を作っている間) は押せなくする。見ている場面と読む場面を同じにするため
                    .disabled(!canReadVideoFrame(previewSeconds: preview?.seconds, previewHasImage: preview?.image != nil, selectedSeconds: selectedSeconds))
                    #if DEBUG
                    // 動画では、読み取りの画面を開くのはこのボタンのため、ここで押した時刻を控える (一覧のセルのタップと同じく、表示までの時間を測るため)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            debugLastScreenshotTapUptime = ProcessInfo.processInfo.systemUptime
                        }
                    )
                    #endif
                    .accessibilityIdentifier("video_frame_read_button")
                }
                .padding()
                // 場面を選び直すたびに、その場面の画像を作り直す。前の場面の画像を作っている途中なら、その結果は捨てる
                .task(id: selectedSeconds) { [selectedSeconds] in
                    // 画像を作り始めた時の時刻を、await の前に捕まえて画像と組にする (await の後に読んだ時刻と組にすると、
                    // 古い場面の画像に新しい時刻を付けてしまい、見ている場面と違う場面を読めるようになるため)
                    // 幅 1206・高さ 2622: iPhone 17 Pro の画面のピクセル数。画面に収めて見せるだけなので、これより大きい画像は作らない
                    let image = try? await videoFrameImage(asset: asset, seconds: selectedSeconds, maximumSize: CGSize(width: 1206, height: 2622))
                    if !Task.isCancelled {
                        preview = (image: image, seconds: selectedSeconds)
                    }
                }
            }
        }
        // ja: 場面を選ぶ
        .navigationTitle("Pick a frame")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadAttempt) {
            guard case .loading = phase else {
                return
            }
            let asset = await loadVideoAsset(
                video: video,
                progress: { progress in
                    Task { @MainActor in
                        phase = videoFrameSelectionPhaseAfterProgress(current: phase, progress: progress)
                    }
                }
            )
            // Optional の map は async の閉包を取れないため、if の式で長さを取る
            let durationSeconds: Double? = if let asset { try? await videoDurationSeconds(asset: asset) } else { nil }
            phase = videoFrameSelectionPhase(asset: asset, durationSeconds: durationSeconds)
            if case .loaded(_, let durationSeconds) = phase {
                selectedSeconds = initialVideoFrameSeconds(durationSeconds: durationSeconds)
            }
        }
    }
}
