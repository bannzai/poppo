#if DEBUG
import AVFoundation
import CoreVideo
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// 一覧でスクリーンショットをタップした時刻 (端末の起動からの秒数)。読み取りの画面が出た時に、タップから表示までの時間を出すために読み、読んだら nil に戻す。
/// 開発者メニューのあるビルドでだけ控える
@MainActor var debugLastScreenshotTapUptime: TimeInterval?

/// 読み取りの画面に開発者メニューのあるビルドでだけ出す、読んでいる 1 枚の撮影日時の文。creationDate は読んでいる 1 枚の撮影日時で、無い時は nil
nonisolated func debugReadingScreenshotText(creationDate: Date?) -> String {
    "読んでいる画像: \(creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "撮影日時なし")"
}

/// 読み取りの画面に開発者メニューのあるビルドでだけ出す、一覧でタップしてからその画面が出るまでの時間の文。milliseconds はその時間で、測っていない時は nil
nonisolated func debugTapToAppearText(milliseconds: Int?) -> String {
    "タップから表示まで: \(milliseconds.map { "\($0) ms" } ?? "なし")"
}

/// 開発者メニューで読む、見本のチャットの画面。前に読んだ同じ相手のスクリーンショットの選択が既定になるかを、
/// 2 つの相手を交互に読んで見比べるために 2 つ置く (1 つだけでは、直前の選択が既定になる動きと見分けられないため)
nonisolated enum DebugSampleChat: CaseIterable {
    /// 全員の発言が左に並ぶチャンネル (Slack に似せた形)
    case designReview
    /// 1 対 1 の相手とのチャット (店とのやり取り)
    case harborBooks

    /// 画面の上部に出すチャットの名前
    var title: String {
        switch self {
        case .designReview:
            "# design-review"
        case .harborBooks:
            "Harbor Books"
        }
    }

    /// 画面に並べる発言。見出し行 (名前と時刻) と本文の組で、上から下の順
    var messages: [(header: String, body: String)] {
        switch self {
        case .designReview:
            [
                (header: "Mira Solberg 10:42 AM", body: "Can someone review the onboarding flow?"),
                (header: "Tobias Lindqvist 10:45 AM", body: "Sure, I will take a look after lunch."),
            ]
        case .harborBooks:
            [
                (header: "Harbor Books 9:12 AM", body: "Your order has arrived at the store."),
                (header: "Harbor Books 9:13 AM", body: "We are open until 7 pm today."),
            ]
        }
    }
}

/// 見本のチャット (sampleChat) の画面の画像を、iPhone 17 Pro のスクリーンショットと同じ大きさで描いて返す。
/// ステータスバーの時刻・上部のチャットの名前・発言の見出し行と本文を、文字の読み取り (Vision) が読める大きさで描く。描けなかった時は CocoaError.fileWriteUnknown を投げる
func debugSampleChatScreenImage(sampleChat: DebugSampleChat) throws -> CGImage {
    let pixelSize = DebugSampleScreenshotShape.portrait.pixelSize
    let format = UIGraphicsImageRendererFormat()
    // ピクセル数を pixelSize のままにするため
    format.scale = 1
    guard
        let cgImage = UIGraphicsImageRenderer(size: pixelSize, format: format).image(actions: { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: pixelSize))
            // 位置と大きさは、見本の画像 (PoppoTests/ChatScreenSamples/chat-screen-sample-thread-light-english.png) の配置に合わせる:
            // ステータスバーの文字の中心が高さの 3% 前後、チャットの名前の中心が 9% 前後、発言は 18% から下
            ("9:41" as NSString).draw(
                at: CGPoint(x: 90, y: 50),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 48), .foregroundColor: UIColor.black]
            )
            let titleAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 52), .foregroundColor: UIColor.black]
            let titleSize = (sampleChat.title as NSString).size(withAttributes: titleAttributes)
            (sampleChat.title as NSString).draw(
                at: CGPoint(x: (pixelSize.width - titleSize.width) / 2, y: pixelSize.height * 0.09 - titleSize.height / 2),
                withAttributes: titleAttributes
            )
            for (index, message) in sampleChat.messages.enumerated() {
                // 1 つの発言の高さ 260px: 見出し行と本文の 2 行と、発言の間の余白
                let messageTop = pixelSize.height * 0.18 + CGFloat(index) * 260
                (message.header as NSString).draw(
                    at: CGPoint(x: 190, y: messageTop),
                    withAttributes: [.font: UIFont.boldSystemFont(ofSize: 46), .foregroundColor: UIColor.black]
                )
                (message.body as NSString).draw(
                    at: CGPoint(x: 190, y: messageTop + 70),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 46), .foregroundColor: UIColor.black]
                )
            }
        }).cgImage
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    return cgImage
}

/// 開発者メニューで写真ライブラリに足した、見本のスクリーンショットの localIdentifier を控える UserDefaults のキー
private let debugSampleScreenshotIdentifiersKey = "debugSampleScreenshotIdentifiers"

/// 前に足した見本のスクリーンショットの localIdentifier。足していない時は空
private func debugSavedSampleScreenshotIdentifiers() -> [String] {
    UserDefaults.standard.stringArray(forKey: debugSampleScreenshotIdentifiersKey) ?? []
}

/// 見本のスクリーンショット 1 枚の形。一覧の縮小画像の枠 (9:19.5) より横長の画像が隣のセルのタップを受けるかを確かめるため、縦長のほかに横長と正方形を混ぜる
nonisolated enum DebugSampleScreenshotShape: Equatable {
    /// ホームボタンの無い iPhone の画面と同じ縦長
    case portrait
    /// 横向きの iPhone の画面
    case landscape
    /// 正方形 (切り抜いた画像の代わり)
    case square

    /// 画像のピクセル数。縦長と横長は iPhone 17 Pro の画面のピクセル数、正方形は縦長の短い辺と長い辺の間の大きさ
    var pixelSize: CGSize {
        switch self {
        case .portrait:
            CGSize(width: 1206, height: 2622)
        case .landscape:
            CGSize(width: 2622, height: 1206)
        case .square:
            CGSize(width: 1600, height: 1600)
        }
    }
}

/// 見本のスクリーンショットの number 枚目 (1 が最も新しい) の形を返す。
/// 3 列の一覧で、左端のセルの右隣が横長・正方形・縦長になる行を 1 つずつ作り、どの形の右隣でタップが右隣に渡るかを 1 回の一覧で見比べるための並び
nonisolated func debugSampleScreenshotShape(number: Int) -> DebugSampleScreenshotShape {
    switch number {
    case 2:
        .landscape
    case 5:
        .square
    default:
        .portrait
    }
}

/// 見本のスクリーンショットを足すかを返す。savedCount は前に足した見本の控えの数、remainingCount はそのうち写真ライブラリに残っている数。
/// 控えが無い時 (まだ足していない) と、一部か全部が消されていた時に true
nonisolated func debugSampleScreenshotsNeedAdding(savedCount: Int, remainingCount: Int) -> Bool {
    savedCount == 0 || remainingCount != savedCount
}

/// 見本のスクリーンショットを写真ライブラリに足す。前に足した見本がすべて残っていれば何もしない。
/// 一部が消されていた時は 1 組を足し直し、残っていた見本は控えから外れる (写真アプリで消す)。同時に 2 回呼ばない前提で、呼び出し側が足している間の再実行を止める。
/// number 枚目の撮影日時は今から number 分前にする。一覧のセルの撮影日時の表示 (分まで) で、どの 1 枚かを見分けるため。
/// EXIF の UserComment に「Screenshot」を入れる。写真アプリがスクリーンショットの種別を付けるかは simulator で確かめる (付かない時は debugSampleScreenshots() の一覧で確かめる)。
/// 写真ライブラリへの書き込みの許可が要る
func addDebugSampleScreenshots() async throws {
    let savedIdentifiers = debugSavedSampleScreenshotIdentifiers()
    guard
        debugSampleScreenshotsNeedAdding(
            savedCount: savedIdentifiers.count,
            remainingCount: PHAsset.fetchAssets(withLocalIdentifiers: savedIdentifiers, options: nil).count
        )
    else {
        return
    }
    let now = Date()
    UserDefaults.standard.set(
        // 一覧に並べる上限の枚数まで足し、11 枚目より後の縮小画像も確かめる。
        // performChanges の変更のブロックは main actor の外で呼ばれるため、画像はその前に作って渡す
        try await createDebugSampleScreenshotAssets(
            samples: try (1...recentScreenshotsLimit).map { number in
                (pngData: try debugSampleScreenshotPNGData(number: number), creationDate: now.addingTimeInterval(-60 * Double(number)))
            }
        ),
        forKey: debugSampleScreenshotIdentifiersKey
    )
}

/// samples の画像を写真ライブラリに足し、足した asset の localIdentifier を samples の順に返す。
/// main actor の外 (nonisolated) に置くのは、main actor の関数の中で書いた変更のブロックは main actor に隔離され、
/// 写真ライブラリはそのブロックを別のキューで呼ぶため (main actor の関数の中に書いた版は、simtunnel の simulator で足す操作の後にアプリが終了し、写真に 1 枚も入らなかった)
nonisolated private func createDebugSampleScreenshotAssets(
    samples: [(pngData: Data, creationDate: Date)]
) async throws -> [String] {
    // 変更のブロックは performChanges が戻る前に 1 度だけ呼ばれ、ほかから同時に触られないため、検査の対象から外す
    nonisolated(unsafe) var createdIdentifiers: [String] = []
    try await PHPhotoLibrary.shared().performChanges {
        createdIdentifiers = samples.compactMap { sample in
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: sample.pngData, options: nil)
            request.creationDate = sample.creationDate
            return request.placeholderForCreatedAsset?.localIdentifier
        }
    }
    return createdIdentifiers
}

/// 開発者メニューで足した見本のスクリーンショットのうち、写真ライブラリに残っているものを新しい順に返す。足していない時は空
func debugSampleScreenshots() -> [PHAsset] {
    let savedIdentifiers = debugSavedSampleScreenshotIdentifiers()
    guard !savedIdentifiers.isEmpty else {
        return []
    }
    let options = PHFetchOptions()
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: savedIdentifiers, options: options)
    return fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
}

/// 見本のスクリーンショットの縮小画像の読み出しで、number 枚目 (1 が最も新しい) をどう扱うか
nonisolated enum DebugSampleScreenshotAvailability: Equatable {
    /// 端末にある画像として、写真ライブラリから読み出す
    case onDevice
    /// iCloud にだけある画像として扱う。iCloud から取ってよい時は、downloadSucceeds が true なら取れ、false なら取れない
    case inCloudOnly(downloadSucceeds: Bool)
    /// 読み出せない画像として扱う
    case unavailable
}

/// 見本のスクリーンショットの number 枚目の扱いを返す。3 列の一覧の 1 行目の右端 (3 番) と 2 行目の左端 (4 番) を iCloud にだけある画像にし、
/// 取れる時と取れない時を並べて見比べる。3 行目の左端 (7 番) は読み出せない画像にし、一覧から外れて 8 番が詰めて並ぶことを確かめる
nonisolated func debugSampleScreenshotAvailability(number: Int) -> DebugSampleScreenshotAvailability {
    switch number {
    case 3:
        .inCloudOnly(downloadSucceeds: true)
    case 4:
        .inCloudOnly(downloadSucceeds: false)
    case 7:
        .unavailable
    default:
        .onDevice
    }
}

/// 開発者メニューの、iCloud にだけある見本と読み出せない見本を混ぜた一覧で使う、縮小画像の読み出し。
/// 引数と返す値は loadScreenshotThumbnailImage と同じで、見本の番号 (debugSampleScreenshotAvailability) で iCloud にだけある画像と読み出せない画像を作る。
/// iCloud から取る時は、進み具合を 4 回に分けて 0.5 秒ずつ伝える (取っている間の表示を simulator で撮れる長さにするため)
func debugSampleScreenshotThumbnailImage(
    asset: PHAsset,
    isNetworkAccessAllowed: Bool,
    progressHandler: @escaping @Sendable (_ fractionCompleted: Double) -> Void
) async -> Result<UIImage, ScreenshotImageUnavailableReason> {
    // 見本の控えは 1 番から順に並ぶため、控えの中の位置 + 1 が番号になる。控えに無い写真は端末にある画像として扱う
    switch debugSavedSampleScreenshotIdentifiers().firstIndex(of: asset.localIdentifier).map({ debugSampleScreenshotAvailability(number: $0 + 1) }) {
    case .inCloudOnly(let downloadSucceeds):
        guard isNetworkAccessAllowed else {
            return .failure(.inCloudOnly)
        }
        for step in 1...4 {
            try? await Task.sleep(for: .milliseconds(500))
            progressHandler(Double(step) / 4)
        }
        guard downloadSucceeds else {
            return .failure(.failed(errorDescription: "PHPhotosErrorDomain 3164: 見本のダウンロードの失敗"))
        }
    case .unavailable:
        return .failure(.unknown)
    case .onDevice, nil:
        break
    }
    return await loadScreenshotThumbnailImage(
        asset: asset,
        isNetworkAccessAllowed: isNetworkAccessAllowed,
        progressHandler: progressHandler
    )
}

/// 開発者メニューで足した見本のスクリーンショットのうち、写真アプリがスクリーンショットの種別を付けたものの数
func debugSampleScreenshotsMarkedAsScreenshotCount() -> Int {
    debugSampleScreenshots().filter { $0.mediaSubtypes.contains(.photoScreenshot) }.count
}

/// 見本のスクリーンショットの number 枚目の PNG。番号と形を大きく書き、EXIF の UserComment に「Screenshot」を入れる。
/// PNG を書き出せなかった時は CocoaError.fileWriteUnknown を投げる (EXIF の無い PNG に切り替えると、写真アプリがスクリーンショットの種別を付けず、一覧の確かめ方が変わるため)
func debugSampleScreenshotPNGData(number: Int) throws -> Data {
    let shape = debugSampleScreenshotShape(number: number)
    let format = UIGraphicsImageRendererFormat()
    // ピクセル数を pixelSize のままにするため
    format.scale = 1
    let cgImage = UIGraphicsImageRenderer(size: shape.pixelSize, format: format).image { context in
        // 番号ごとに色を変え、一覧で隣のセルと見分けやすくする。12 色で一巡させる (3 列の一覧の 4 行分で、隣どうしと上下が同じ色にならない)。
        // 彩度 0.35・明度 0.95 は、黒い文字が読める淡い色にするため
        UIColor(hue: CGFloat(number % 12) / 12, saturation: 0.35, brightness: 0.95, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: shape.pixelSize))
        ("Sample \(number)\n\(shape)" as NSString).draw(
            // 左右 80px は文字が画像の端に付かないための余白。上下の 1/3 は、縦長の画像が枠に合わせて縦に切られても文字が真ん中に残るため
            in: CGRect(origin: .zero, size: shape.pixelSize).insetBy(dx: 80, dy: shape.pixelSize.height / 3),
            withAttributes: [
                // 一覧の縮小画像 (幅 約 118pt) でも番号が読める大きさ
                .font: UIFont.boldSystemFont(ofSize: 220),
                .foregroundColor: UIColor.black,
            ]
        )
    }.cgImage
    let exifPNGData = NSMutableData()
    guard
        let cgImage,
        let destination = CGImageDestinationCreateWithData(exifPNGData, UTType.png.identifier as CFString, 1, nil)
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(
        destination,
        cgImage,
        [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Screenshot"]] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return exifPNGData as Data
}

/// 開発者メニューで写真ライブラリに足した、見本のチャットの動画の localIdentifier を控える UserDefaults のキー
private let debugSampleChatVideoIdentifierKey = "debugSampleChatVideoIdentifier"

/// 見本のチャットの動画で、1 つのチャットの画面を映し続ける秒数。
/// 1 秒: 場面を選ぶ画面の Slider で、2 つの画面のどちらの場面も選べる長さにしつつ、書き出しを短くするため
nonisolated let debugSampleChatVideoSecondsPerChat = 1

/// 見本のチャットの画面を順に映す動画を、fileURL に MP4 で書き出す。DebugSampleChat.allCases の順に、1 つの画面を debugSampleChatVideoSecondsPerChat 秒ずつ映す
/// (場面を選ぶと、選んだ時刻の画面を読むかを確かめるため)。fileURL に既にファイルがあれば置き換える。書き出せなかった時は AVFoundation のエラーか CocoaError.fileWriteUnknown を投げる
func writeDebugSampleChatVideo(fileURL: URL) async throws {
    let images = try DebugSampleChat.allCases.map { try debugSampleChatScreenImage(sampleChat: $0) }
    // 前に書き出したファイルが無い時は消せずに失敗するが、無ければ消す必要も無いため、失敗を無視する
    try? FileManager.default.removeItem(at: fileURL)
    let pixelSize = DebugSampleScreenshotShape.portrait.pixelSize
    let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)
    let receiver = writer.inputPixelBufferReceiver(
        for: AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                // H.264: iPhone の画面収録と同じく、写真ライブラリと AVFoundation がそのまま読める形式にするため
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(pixelSize.width),
                AVVideoHeightKey: Int(pixelSize.height),
            ]
        ),
        pixelBufferAttributes: nil
    )
    try writer.start()
    writer.startSession(atSourceTime: .zero)
    for (index, image) in images.enumerated() {
        try await receiver.append(
            CVReadOnlyPixelBuffer(unsafeBuffer: try debugPixelBuffer(image: image)),
            with: CMTime(value: CMTimeValue(index * debugSampleChatVideoSecondsPerChat), timescale: 1)
        )
    }
    receiver.finish()
    writer.endSession(atSourceTime: CMTime(value: CMTimeValue(images.count * debugSampleChatVideoSecondsPerChat), timescale: 1))
    await writer.finishWriting()
    guard writer.status == .completed else {
        throw writer.error ?? CocoaError(.fileWriteUnknown)
    }
}

/// 画像 (image) を、動画に書くための同じ大きさの BGRA の pixel buffer にして返す。作れなかった時は CocoaError.fileWriteUnknown を投げる
nonisolated private func debugPixelBuffer(image: CGImage) throws -> CVPixelBuffer {
    var createdPixelBuffer: CVPixelBuffer?
    guard
        CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, nil, &createdPixelBuffer) == kCVReturnSuccess,
        let pixelBuffer = createdPixelBuffer
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    CVPixelBufferLockBaseAddress(pixelBuffer, [])
    defer {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
    }
    guard
        let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: image.width,
            height: image.height,
            // 8: BGRA の 1 色を 1 バイトで持つ形式 (kCVPixelFormatType_32BGRA) のため
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            // BGRA の並び (リトルエンディアンの 32 ビットで、アルファが先頭) に合わせる
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixelBuffer
}

/// 前に足した見本のチャットの動画のうち、写真ライブラリに残っているもの。足していない時と、写真アプリで消された時は nil
func debugSampleChatVideo() -> PHAsset? {
    UserDefaults.standard.string(forKey: debugSampleChatVideoIdentifierKey).flatMap {
        PHAsset.fetchAssets(withLocalIdentifiers: [$0], options: nil).firstObject
    }
}

/// 見本のチャットの動画 (writeDebugSampleChatVideo) を写真ライブラリに足す。前に足した動画が残っていれば何もしない。
/// 同時に 2 回呼ばない前提で、呼び出し側が足している間の再実行を止める。写真ライブラリへの書き込みの許可が要る
func addDebugSampleChatVideo() async throws {
    guard debugSampleChatVideo() == nil else {
        return
    }
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "debug-sample-chat.mp4")
    try await writeDebugSampleChatVideo(fileURL: fileURL)
    UserDefaults.standard.set(try await createDebugSampleVideoAsset(fileURL: fileURL), forKey: debugSampleChatVideoIdentifierKey)
}

/// fileURL の動画を写真ライブラリに足し、足した asset の localIdentifier を返す。
/// main actor の外に置く理由は createDebugSampleScreenshotAssets と同じ (写真ライブラリは変更のブロックを別のキューで呼ぶ)
nonisolated private func createDebugSampleVideoAsset(fileURL: URL) async throws -> String? {
    // 変更のブロックは performChanges が戻る前に 1 度だけ呼ばれ、ほかから同時に触られないため、検査の対象から外す
    nonisolated(unsafe) var createdIdentifier: String?
    try await PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .video, fileURL: fileURL, options: nil)
        createdIdentifier = request.placeholderForCreatedAsset?.localIdentifier
    }
    return createdIdentifier
}
#endif
