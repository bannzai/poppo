#if DEBUG
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

/// 見本のスクリーンショットを写真ライブラリに足す。前に足した見本がすべて残っていれば何もしない。
/// 一部が消されていた時は 1 組を足し直し、残っていた見本は控えから外れる (写真アプリで消す)。同時に 2 回呼ばない前提で、呼び出し側が足している間の再実行を止める。
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
    UserDefaults.standard.set(
        // 一覧に並べる上限の枚数まで足し、11 枚目より後の縮小画像も確かめる。
        // performChanges の変更のブロックは main actor の外で呼ばれるため、画像はその前に作って渡す
        try await createDebugSampleScreenshotAssets(
            samples: (1...recentScreenshotsLimit).map { number in
                (pngData: debugSampleScreenshotPNGData(number: number), creationDate: now.addingTimeInterval(-60 * Double(number)))
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
    }
    let exifPNGData = NSMutableData()
    guard
        let cgImage = image.cgImage,
        let destination = CGImageDestinationCreateWithData(exifPNGData, UTType.png.identifier as CFString, 1, nil)
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
    return exifPNGData as Data
}
#endif
