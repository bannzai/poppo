#if DEBUG
import Testing

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

/// タップからの時間を測った時はミリ秒を、測っていない時 (開発者メニューから開いた時等) は「なし」と出すこと
@Test func debugTapToAppearTextShowsMillisecondsOrNone() {
    #expect(debugTapToAppearText(milliseconds: 0) == "タップから表示まで: 0 ms")
    #expect(debugTapToAppearText(milliseconds: 181) == "タップから表示まで: 181 ms")
    #expect(debugTapToAppearText(milliseconds: nil) == "タップから表示まで: なし")
}
#endif
