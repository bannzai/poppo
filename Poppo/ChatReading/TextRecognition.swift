import CoreGraphics
import Vision

/// 画像に写った文字を、端末内の Vision で行ごとに読む。読めた行を、文字と画像の中での位置の組で返す
@concurrent nonisolated func recognizeTextLines(image: CGImage) async throws -> [RecognizedTextLine] {
    var request = RecognizeTextRequest()
    // チャットの言語は読む前には分からないため、Vision に言語を判定させる
    request.automaticallyDetectsLanguage = true
    return try await request.perform(on: image).compactMap { observation in
        observation.topCandidates(1).first.map { candidate in
            RecognizedTextLine(
                text: candidate.string,
                boundingBox: topLeftOriginRect(lowerLeftOriginRect: observation.boundingBox.cgRect)
            )
        }
    }
}

/// 左下を原点にした枠を、左上を原点にした枠に直す。幅と高さを 1 とした座標で受け取り、同じ座標で返す。
/// Vision の NormalizedRect は左下が原点 (SDK の宣言で `toImageCoordinates(_:origin:)` の origin の既定値が `.lowerLeft`) で、
/// 発言の抜き出しは画面の上から下の順に読むため、向きをそろえる
nonisolated func topLeftOriginRect(lowerLeftOriginRect: CGRect) -> CGRect {
    CGRect(
        x: lowerLeftOriginRect.minX,
        y: 1 - lowerLeftOriginRect.maxY,
        width: lowerLeftOriginRect.width,
        height: lowerLeftOriginRect.height
    )
}
