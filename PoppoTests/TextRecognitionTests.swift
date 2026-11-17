import CoreGraphics
import Testing
import UIKit
@testable import Poppo

/// 左下が原点の枠を左上が原点の枠に直すと、上下の位置だけが入れ替わり、左右の位置と大きさは変わらないこと
/// (下から 0.5 の高さに下端がある高さ 0.25 の枠は、上から 0.25 の位置に上端が来る)
@Test func topLeftOriginRectFlipsOnlyVerticalPosition() {
    #expect(
        topLeftOriginRect(lowerLeftOriginRect: CGRect(x: 0.125, y: 0.5, width: 0.5, height: 0.25))
            == CGRect(x: 0.125, y: 0.25, width: 0.5, height: 0.25)
    )
}

/// 画像の上のほうに描いた文字は上半分の位置で、下のほうに描いた文字は下半分の位置で読み取ること。
/// Vision の実物を通し、枠の上下の向きの扱いが合っていることを確かめる。
/// simulator で Vision が固まった時に CI の制限時間まで待たないよう、1 分で打ち切る
@Test(.timeLimit(.minutes(1))) func recognizeTextLinesReadsTextAtItsVerticalPosition() async throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let lines = try await recognizeTextLines(
        image: try #require(
            UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1200), format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
                for (text, y) in [("Hello world", 150.0), ("Goodbye", 950.0)] {
                    (text as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.black]
                    )
                }
            }.cgImage
        )
    )

    #expect(try #require(lines.first { $0.text.contains("Hello") }).boundingBox.midY < 0.5)
    #expect(try #require(lines.first { $0.text.contains("Goodbye") }).boundingBox.midY > 0.5)
}
