import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

/// 取り込んだ映像の 1 枚を画像にできなかったことを表すエラー
nonisolated struct FrameImageConversionError: Error, Equatable {
    /// 変換の関数 (VTCreateCGImageFromCVPixelBuffer) が返した結果のコード
    let status: OSStatus
    /// 変換しようとした映像の画素の形式 (kCVPixelFormatType_32BGRA など)
    let pixelFormat: OSType
}

/// 取り込んだ映像の 1 枚 (pixelBuffer) を、文字の読み取りに渡す画像にして返す。
/// 画像にできない時は、結果のコードと画素の形式を持った FrameImageConversionError を投げる。
/// 返した画像が使われている間、pixelBuffer は手放されないことがある (SDK の VTUtilities.h:
/// 「The source CVPixelBuffer may be retained for the lifetime of the CGImage.」)
nonisolated func makeCGImage(pixelBuffer: CVPixelBuffer) throws -> CGImage {
    var image: CGImage?
    let status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
    guard status == noErr, let image else {
        throw FrameImageConversionError(status: status, pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer))
    }
    return image
}

/// 画面の画像を、前に読んだ画面と同じかを比べるための小さな画素の並び (明るさだけ) にして返す。
/// 同じ画素の画像からは同じ並びが返る。画像を縮められなかった時は nil を返す
nonisolated func screenFingerprint(image: CGImage) -> [UInt8]? {
    // 90 × 195: iPhone の画面の縦横の比 (約 9 : 19.5) のまま、1 行の文字 (画面の高さの約 2%) が 3〜4 個の升にまたがる細かさ。
    // 発言が 1 つ増えた・スクロールした、という変化を拾える細かさとして置いた見積もりで、実際の画面では測っていない
    let width = 90
    let height = 195
    var pixels = [UInt8](repeating: 0, count: width * height)
    guard
        pixels.withUnsafeMutableBytes({ buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        })
    else {
        return nil
    }
    return pixels
}

/// 画面から読んだ行に、Poppo のキーボードが出している読み取り結果 (latestReading) の文が映っているか。
/// 映っている画面を読み直すと、キーボードに出ている訳文と返信案を発言として読み、読み取り結果を上書きしてしまうため、
/// 読み直さない判断に使う。画面全体の取り込みにキーボードが映ることは実機で確かめていない仮説
/// (documents/DIRECTION.md「決めたこと」)。
/// 見るのは、Poppo が作って利用者の言語で出す文 (訳文と、返信案の意味) で、その文の一部になっている行が画面にあれば、その文が映っているとみなす。
/// チャットに元からある文 (原文と、利用者が送った後にチャットに載る返信案の文) の一部でもある行は数えない
/// (訳しても変わらない語 (製品の名前・URL 等) や、訳さずに並べた利用者の言語の発言で、チャットの画面を読み直せなくならないようにする)。
/// 映っていると判定するのは、そういう文が 2 つ以上映っている時 (見る文が 1 つしか無い読み取り結果では、その 1 つが映っている時)。
/// チャットに届いた利用者の言語の発言が、たまたま訳文の 1 つと同じ言い回し (「ありがとうございます」等) だった時に、
/// その発言が画面にある間ずっと読み直せなくならないようにするため
func showsLatestReading(lines: [RecognizedTextLine], latestReading: LatestReading) -> Bool {
    let chatTexts = (latestReading.messages.map(\.originalText) + latestReading.replySuggestions.map(\.text))
        .map { removingWhitespaces(text: $0) }
    let shownTexts = Set(
        (latestReading.messages.map(\.translatedText) + latestReading.replySuggestions.map(\.meaning)).map { removingWhitespaces(text: $0) }
    ).subtracting(chatTexts)
    let lineTexts = lines.map { removingWhitespaces(text: $0.text) }.filter { lineText in
        // 4 文字: キーボードは長い文を折り返して出すため、行は文の一部として探す。短い行 (「はい」等) が
        // たまたま文の一部に一致して読み直しを止めないよう、4 文字以上の行だけを見る。見積もりで、実機では測っていない
        lineText.count >= 4 && !chatTexts.contains { $0.contains(lineText) }
    }
    // 2 つ: キーボードは開いた時に、返信案 3 つと直前の発言の翻訳が同時に見える高さにしてある (PoppoKeyboard/KeyboardView.swift) ため、
    // キーボードが映っていれば 2 つ以上の文が映る。1 つだけの一致は、チャットの発言との偶然の一致として扱う
    return !shownTexts.isEmpty
        && shownTexts.filter { shownText in lineTexts.contains { shownText.contains($0) } }.count >= min(2, shownTexts.count)
}

/// 文から空白と改行を取り除いて返す。文字の読み取りは、行の折り返しや文字の間に空白を入れることがあるため、比べる前にそろえる
private func removingWhitespaces(text: String) -> String {
    text.filter { !$0.isWhitespace }
}

/// 読み取りの段のエラーを、診断の記録に残す文にして返す。この関数は、画面から読んだ文字を文に足さない
/// (システムのエラーの説明はそのまま使う。そこに画面の文字が含まれないかは確かめていない)。
/// このアプリが定義したエラー (ChatReadingError・FrameImageConversionError) は、エラーの名前と値 (言語・結果のコード・画素の形式)、
/// ほかのエラーは、エラーのドメイン・コード・説明にする
nonisolated func screenReadingFailureDescription(error: any Error) -> String {
    switch error {
    case let chatReadingError as ChatReadingError:
        "ChatReadingError.\(chatReadingError)"
    case let conversionError as FrameImageConversionError:
        "FrameImageConversionError status=\(conversionError.status) pixelFormat=\(conversionError.pixelFormat)"
    default:
        screenCaptureFailureDescription(error: error)
    }
}
