#if DEBUG
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import Poppo

/// 見本の 2 枚目は横長、5 枚目は正方形にすること (3 列の一覧で、左端の 1 枚目と 4 枚目の右隣がこの形になり、タップが右隣に渡るかを確かめるため)
@Test func debugSampleScreenshotShapeIsLandscapeAndSquareNextToLeftCells() {
    #expect(debugSampleScreenshotShape(number: 2) == .landscape)
    #expect(debugSampleScreenshotShape(number: 5) == .square)
}

/// 横長と正方形の隣の番号と、最初と最後の番号は縦長にすること (7 枚目の右隣の 8 枚目が縦長で、縦長どうしの比べる行になるため)
@Test func debugSampleScreenshotShapeIsPortraitForOtherNumbers() {
    for number in [1, 3, 4, 6, 8, recentScreenshotsLimit] {
        #expect(debugSampleScreenshotShape(number: number) == .portrait, "number: \(number)")
    }
}

/// 読んでいる 1 枚の撮影日時が無い時は「撮影日時なし」と出すこと
@Test func debugReadingScreenshotTextWithoutCreationDate() {
    #expect(debugReadingScreenshotText(creationDate: nil) == "読んでいる画像: 撮影日時なし")
}

/// 読んでいる 1 枚の撮影日時がある時は、その日時を分まで出し、「撮影日時なし」と出さないこと (一覧のセルの撮影日時と見比べて、タップした 1 枚が渡されたかを確かめるため)
@Test func debugReadingScreenshotTextWithCreationDate() {
    let creationDate = Date(timeIntervalSince1970: 1_795_700_000)

    let text = debugReadingScreenshotText(creationDate: creationDate)

    #expect(text == "読んでいる画像: \(creationDate.formatted(date: .abbreviated, time: .shortened))")
    #expect(!text.contains("撮影日時なし"))
}

/// 縮小画像を読み出せなかった理由ごとに、開発者メニューのあるビルドで枠に出す文を分けること。エラーの時は写真ライブラリの説明をそのまま出す
@Test func debugTextForEachScreenshotImageUnavailableReason() {
    #expect(debugText(screenshotImageUnavailableReason: .inCloudOnly) == "iCloud にだけある")
    #expect(debugText(screenshotImageUnavailableReason: .cancelled) == "取り消された")
    #expect(debugText(screenshotImageUnavailableReason: .failed(errorDescription: "PHPhotosErrorDomain 3164: network")) == "PHPhotosErrorDomain 3164: network")
    #expect(debugText(screenshotImageUnavailableReason: .unknown) == "理由なし")
}

/// 見本の PNG は形ごとのピクセル数で書き出し、EXIF の UserComment に「Screenshot」を入れること (写真アプリがスクリーンショットの種別を付ける手がかり)。
/// number は見本の番号、width・height はその番号の形で期待するピクセル数
@MainActor @Test(arguments: [(1, 1206, 2622), (2, 2622, 1206), (5, 1600, 1600)]) func debugSampleScreenshotPNGDataHasShapeSizeAndScreenshotComment(number: Int, width: Int, height: Int) throws {
    let source = try #require(CGImageSourceCreateWithData(try debugSampleScreenshotPNGData(number: number) as CFData, nil))
    let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    let exif = try #require(properties[kCGImagePropertyExifDictionary] as? [CFString: Any])

    #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
    #expect(properties[kCGImagePropertyPixelWidth] as? Int == width)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == height)
    #expect(exif[kCGImagePropertyExifUserComment] as? String == "Screenshot")
}

/// タップからの時間を測った時はミリ秒を、測っていない時 (開発者メニューから開いた時等) は「なし」と出すこと
@Test func debugTapToAppearTextShowsMillisecondsOrNone() {
    #expect(debugTapToAppearText(milliseconds: 0) == "タップから表示まで: 0 ms")
    #expect(debugTapToAppearText(milliseconds: 181) == "タップから表示まで: 181 ms")
    #expect(debugTapToAppearText(milliseconds: nil) == "タップから表示まで: なし")
}
#endif
