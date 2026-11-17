import CoreGraphics
import Foundation

/// 読み取った文字から抜き出した 1 つの発言
nonisolated struct ExtractedMessage: Sendable {
    /// 発言の文。複数の行にわたる発言は改行でつなぐ
    let text: String
    /// 利用者自身の発言か。右に寄った吹き出しの発言を利用者のものとして扱う
    let isFromUser: Bool
}

/// 画像から読んだ行を、チャットの発言にまとめる。画面の上から下の順に、発言ごとに 1 つ返す。
/// 上下のバーと入力欄にあたる帯の行と、時刻だけの行は発言に含めない。
/// 利用者自身の発言は左右の位置で見分けるため、全員の発言が左に並ぶ画面 (Slack・Discord) では、すべて相手の発言として返す
nonisolated func extractMessages(lines: [RecognizedTextLine]) -> [ExtractedMessage] {
    lines
        .filter { isInsideChatArea(line: $0) && !isTimeOnly(text: $0.text) }
        .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        .reduce(into: [[RecognizedTextLine]]()) { messageLines, line in
            if let previousLine = messageLines.last?.last, continuesMessage(previousLine: previousLine, line: line) {
                messageLines[messageLines.count - 1].append(line)
            } else {
                messageLines.append([line])
            }
        }
        .map { ExtractedMessage(text: $0.map(\.text).joined(separator: "\n"), isFromUser: isShiftedRight(lines: $0)) }
}

/// 行が、発言の並ぶ範囲 (上のバーと下の入力欄を除いた範囲) に収まっているか
private nonisolated func isInsideChatArea(line: RecognizedTextLine) -> Bool {
    // 上の 0.12: ステータスバーとナビゲーションバー (相手やチャンネルの名前) を発言に混ぜないため。
    // 下の 0.9: 入力欄の文言 (「メッセージを入力」等) を最後の発言として読まないため。
    // どちらも iPhone の画面の高さ (約 870pt) に対するバーの高さ (上は約 100pt、下は約 85pt) からの見積もりで、
    // 実際のスクリーンショットでは測っていない
    line.boundingBox.minY >= 0.12 && line.boundingBox.maxY <= 0.9
}

/// 文字が時刻だけ (例: 「10:42」「10:42 AM」「午後3:41」) か。発言の横や下に出る送信時刻を発言に含めないために使う
private nonisolated func isTimeOnly(text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/((午前|午後)\s?)?\d{1,2}:\d{2}(\s?[AaPp][Mm])?/#) != nil
}

/// 上下に続く 2 行が、同じ発言の続きか
private nonisolated func continuesMessage(previousLine: RecognizedTextLine, line: RecognizedTextLine) -> Bool {
    // 0.75: 同じ発言の中の行間は行の高さより十分小さく、発言の間は吹き出しの余白ぶん (行の高さと同じくらい) 空くため、その間の値で分ける。
    // 0.04: 同じ発言の行は左端がそろうため、文字認識の枠のぶれとして画面の幅の 4% までを同じ左端とみなす。
    // どちらも見積もりで、実際のスクリーンショットでは測っていない
    line.boundingBox.minY - previousLine.boundingBox.maxY <= 0.75 * min(previousLine.boundingBox.height, line.boundingBox.height)
        && abs(line.boundingBox.minX - previousLine.boundingBox.minX) <= 0.04
}

/// 1 つの発言の行が、画面の右に寄っているか。吹き出しで並ぶチャットでは、利用者自身の発言が右に寄る
private nonisolated func isShiftedRight(lines: [RecognizedTextLine]) -> Bool {
    guard let minX = lines.map(\.boundingBox.minX).min(), let maxX = lines.map(\.boundingBox.maxX).max() else {
        return false
    }
    // 0.2: 右に寄った吹き出しは左に画面の幅の 2 割以上の余白を持つ。アイコンの右から始まる左寄せの発言 (左の余白は約 15%) と分けるための値。
    // 0.1: 左右の余白が同じくらいの中央の行 (日付の区切り等) を利用者の発言にしないため、左の余白が右より 1 割以上大きいことも求める。
    // どちらも見積もりで、実際のスクリーンショットでは測っていない
    return minX >= 0.2 && minX - (1 - maxX) >= 0.1
}
