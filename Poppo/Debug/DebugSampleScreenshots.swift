#if DEBUG
import ImageIO
import Photos
import UIKit
import UniformTypeIdentifiers

/// 一覧でスクリーンショットをタップした時刻 (端末の起動からの秒数)。読み取りの画面が出た時に、タップから表示までの時間を出すために読み、読んだら nil に戻す。
/// 開発者メニューのあるビルドでだけ控える
@MainActor var debugLastScreenshotTapUptime: TimeInterval?

/// 開発者メニューで写真ライブラリに足した、見本のスクリーンショットの localIdentifier を控える UserDefaults のキー
private let debugSampleScreenshotIdentifiersKey = "debugSampleScreenshotIdentifiers"

/// 前に足した見本のスクリーンショットの localIdentifier。足していない時は空
private func debugSavedSampleScreenshotIdentifiers() -> [String] {
    UserDefaults.standard.stringArray(forKey: debugSampleScreenshotIdentifiersKey) ?? []
}

/// 見本のスクリーンショット 1 枚の形。一覧の縮小画像の枠 (9:19.5) より横長の画像が隣のセルのタップを受けるかを確かめるため、縦長のほかに横長と正方形を混ぜる
nonisolated enum DebugSampleScreenshotShape: Equatable {
    /// ホームボタンの無い iPhone の画面と同じ縦長 (1206 x 2622。iPhone 17 Pro の画面のピクセル数)
    case portrait
    /// 横向きの iPhone の画面 (2622 x 1206)
    case landscape
    /// 正方形 (1600 x 1600。切り抜いた画像の代わり)
    case square

    /// 画像のピクセル数
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
/// 2 枚目は横長、5 枚目は正方形、ほかは縦長。1 枚目の右隣が横長、4 枚目の右隣が正方形、7 枚目の右隣が縦長の並びになり、
/// どの形の右隣で 1 枚目のタップが右隣に渡るかを 1 回の一覧で見比べられる
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

/// 見本のスクリーンショットの枚数。並べる上限 (30 枚。RecentScreenshotsView の loadScreenshots) まで並べ、11 枚目より後の縮小画像も確かめるため
private let debugSampleScreenshotCount = 30

/// 見本のスクリーンショットを写真ライブラリに足す。前に足した見本がすべて残っていれば何もしない (何度実行しても見本は 1 組だけ)。
/// number 枚目の撮影日時は今から number 分前にする。一覧のセルの撮影日時の表示 (分まで) で、どの 1 枚かを見分けるため。
/// EXIF の UserComment に「Screenshot」を入れる。写真アプリがスクリーンショットの種別を付けるかは simulator で確かめる (付かない時は debugSampleScreenshots() の一覧で確かめる)。
/// 写真ライブラリへの書き込みの許可が要る
func addDebugSampleScreenshots() async throws {
    let savedIdentifiers = debugSavedSampleScreenshotIdentifiers()
    if !savedIdentifiers.isEmpty,
        PHAsset.fetchAssets(withLocalIdentifiers: savedIdentifiers, options: nil).count == savedIdentifiers.count
    {
        return
    }
    let now = Date()
    // performChanges の変更のブロックは main actor の外で呼ばれるため、画像はその前に作って渡す
    let samples = (1...debugSampleScreenshotCount).map { number in
        (pngData: debugSampleScreenshotPNGData(number: number), creationDate: now.addingTimeInterval(-60 * Double(number)))
    }
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
    UserDefaults.standard.set(createdIdentifiers, forKey: debugSampleScreenshotIdentifiersKey)
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

/// 開発者メニューで足した見本のスクリーンショットのうち、写真アプリがスクリーンショットの種別を付けたものの数
func debugSampleScreenshotsMarkedAsScreenshotCount() -> Int {
    debugSampleScreenshots().filter { $0.mediaSubtypes.contains(.photoScreenshot) }.count
}

/// 見本のスクリーンショットの number 枚目の PNG。番号と形を大きく書き、EXIF の UserComment に「Screenshot」を入れる
private func debugSampleScreenshotPNGData(number: Int) -> Data {
    let shape = debugSampleScreenshotShape(number: number)
    let format = UIGraphicsImageRendererFormat()
    // ピクセル数を pixelSize のままにするため
    format.scale = 1
    let image = UIGraphicsImageRenderer(size: shape.pixelSize, format: format).image { context in
        // 番号ごとに色を変え、一覧で隣のセルと見分けやすくする。12 色で一巡させる
        UIColor(hue: CGFloat(number % 12) / 12, saturation: 0.35, brightness: 0.95, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: shape.pixelSize))
        ("Sample \(number)\n\(shape)" as NSString).draw(
            in: CGRect(origin: .zero, size: shape.pixelSize).insetBy(dx: 80, dy: shape.pixelSize.height / 3),
            withAttributes: [
                // 一覧の縮小画像 (幅 約 118pt) でも番号が読める大きさ
                .font: UIFont.boldSystemFont(ofSize: 220),
                .foregroundColor: UIColor.black,
            ]
        )
    }
    let data = NSMutableData()
    guard
        let cgImage = image.cgImage,
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else {
        return image.pngData() ?? Data()
    }
    CGImageDestinationAddImage(
        destination,
        cgImage,
        [kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Screenshot"]] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
        return image.pngData() ?? Data()
    }
    return data as Data
}
#endif
