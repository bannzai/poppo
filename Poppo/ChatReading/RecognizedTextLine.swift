import CoreGraphics

/// 画像から読んだ 1 行の文字と、その位置。
/// Vision の観測 (RecognizedTextObservation) はテストから作れないため、発言の抜き出しが使う値だけをこの型で受け渡す
nonisolated struct RecognizedTextLine: Sendable {
    /// 読んだ文字
    let text: String
    /// 画像の中での位置。画像の幅と高さをそれぞれ 1 とし、左上を原点にした枠
    let boundingBox: CGRect
}
