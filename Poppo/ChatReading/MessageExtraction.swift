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
/// 上下のバーと入力欄にあたる帯の行、時刻だけの行、「既読」、スレッドの返信の数、画面の中央に 1 行だけある行 (日付の区切り等) は発言に含めない。
/// 同じ段に横に並ぶ行 (名前と、その右の時刻) は 1 行につなぎ、下に続く本文と 1 つの発言にする。
/// 利用者自身の発言は左右の位置で見分けるため、全員の発言が左に並ぶ画面 (Slack・Discord) では、すべて相手の発言として返す
nonisolated func extractMessages(lines: [RecognizedTextLine]) -> [ExtractedMessage] {
    linesJoinedInSameRow(
        lines: lines.filter {
            isInsideChatArea(line: $0) && !isTimeOnly(text: $0.text) && !isReadReceipt(text: $0.text)
                && !isThreadReplyCount(text: $0.text)
        }
    )
    .sorted { $0.boundingBox.minY < $1.boundingBox.minY }
    .reduce(into: [[RecognizedTextLine]]()) { messageLines, line in
        if let previousLine = messageLines.last?.last, continuesMessage(previousLine: previousLine, line: line) {
            messageLines[messageLines.count - 1].append(line)
        } else {
            messageLines.append([line])
        }
    }
    // 中央にあるかは、段をつなぎ発言にまとめた後で見る: 名前の右の時刻や、右に寄った吹き出しの短い 2 行目は、
    // その行だけを見ると中央に来ることがあるため (見本の「hoy a las 18:15」の中心のずれは 0.3% 以内だった。CI の実測は isCentered(line:) のコメント)
    .filter { !($0.count == 1 && isCentered(line: $0[0])) }
    .map { ExtractedMessage(text: $0.map(\.text).joined(separator: "\n"), isFromUser: isShiftedRight(lines: $0)) }
}

/// 発言の並ぶ範囲の上端 (画像の高さを 1 とした位置)。これより上はステータスバーとナビゲーションバー (相手やチャンネルの名前) の段
// 0.12: ステータスバーとナビゲーションバーを発言に混ぜないため。iPhone の画面の高さ (約 870pt) に対する
// 上のバーの高さ (約 100pt) からの見積もりで、実際のスクリーンショットでは測っていない
nonisolated let chatAreaTopEdge: CGFloat = 0.12

/// 行が、発言の並ぶ範囲 (上のバーと下の入力欄を除いた範囲) に収まっているか
private nonisolated func isInsideChatArea(line: RecognizedTextLine) -> Bool {
    // 下の 0.9: 入力欄の文言 (「メッセージを入力」等) を最後の発言として読まないため。
    // iPhone の画面の高さ (約 870pt) に対する入力欄の高さ (約 85pt) からの見積もりで、実際のスクリーンショットでは測っていない
    line.boundingBox.minY >= chatAreaTopEdge && line.boundingBox.maxY <= 0.9
}

/// 文字が時刻だけ (例: 「10:42」「10:42 AM」「午後3:41」) か。発言の横や下に出る送信時刻を発言に含めないために使う
nonisolated func isTimeOnly(text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/((午前|午後)\s?)?\d{1,2}:\d{2}(\s?[AaPp][Mm])?/#) != nil
}

/// 文字が「既読」だけ (例: 「既読」「既読 2」) か。利用者の吹き出しの横に出る既読の印を発言に含めないために使う。
/// 位置では見分けない: 吹き出しの横の印は、吹き出しの幅によって左右の位置が変わるため
private nonisolated func isReadReceipt(text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/既読(\s?\d+)?/#) != nil
}

/// 文字がスレッドの返信の数だけ (例: 「3 replies」「1 reply」「3件の返信」) か。発言の下に出る返信の数を発言の最後の行にしないために使う。
/// 位置では見分けない: 返信の数は本文と左端がそろい、行間も本文の行と変わらないため
private nonisolated func isThreadReplyCount(text: String) -> Bool {
    text.trimmingCharacters(in: .whitespaces).wholeMatch(of: #/\d+\s?(repl(y|ies)|件の返信)/#.ignoresCase()) != nil
}

/// 行が、画面の左右の中央にあるか。日付の区切り (「Today」「今日」) のように、発言の並びの外に置かれる行を発言に含めないために使う
private nonisolated func isCentered(line: RecognizedTextLine) -> Bool {
    // 0.02: 中央に置かれた行の枠の中心は画面の中央に来るため、文字認識の枠のぶれとして画面の幅の 2% までを中央とみなす。
    // 0.25: 発言は左 (アイコンの右。左の余白は約 15%) か右 (右端の近くまで届く) から始まり、左の余白が 25% 以上で中心が中央に来ることは無いため。
    // 画面の幅いっぱいに近い発言の行 (左の余白が小さく、中心がたまたま中央に近い) を除かないための値。
    // どちらも見本の画像の元の HTML (documents/design/chat-screen-samples/) の配置からの見積もり。
    // 見本の画像を Vision で読んだ実測では、日付の区切り 2 つの中心のずれは 0.3% 以内、1 行だけの発言で左の余白が 25% 以上のものの中心のずれは 12% 以上だった
    // (CI の実測: https://github.com/bannzai/poppo/actions/runs/45587820896 )
    abs(line.boundingBox.midX - 0.5) <= 0.02 && line.boundingBox.minX >= 0.25
}

/// 同じ段に横に並ぶ行を、左から順に空白でつないだ 1 行にまとめて返す。ほかの行はそのまま返す。
/// 名前の右に時刻が小さく出る画面 (Discord) で、Vision が名前と時刻を別の行として返しても、見出しの 1 行として扱うために使う
private nonisolated func linesJoinedInSameRow(lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
    lines
        .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        .reduce(into: [RecognizedTextLine]()) { joinedLines, line in
            if let index = joinedLines.firstIndex(where: { continuesRow(leftLine: $0, line: line) }) {
                joinedLines[index] = RecognizedTextLine(
                    text: joinedLines[index].text + " " + line.text,
                    boundingBox: joinedLines[index].boundingBox.union(line.boundingBox)
                )
            } else {
                joinedLines.append(line)
            }
        }
}

/// 行が、左にある行と同じ段の続き (すぐ右に並ぶ) か
private nonisolated func continuesRow(leftLine: RecognizedTextLine, line: RecognizedTextLine) -> Bool {
    // 0.5: 名前と時刻は文字の大きさが違っても同じ段に並び、枠の上下の中心が近い。次の段の行は中心が行の高さ以上ずれるため、
    // 低い方の行の高さの半分までを同じ段とみなす。
    // 0.06: 名前と時刻の間は空白 1〜2 文字ぶん (見本の HTML では 8px の余白と空白 1 文字で約 12px、画面の幅の約 3%)。枠のぶれを見て 2 倍までを続きとみなす。
    // 左右に分かれた吹き出しのように、離れて並ぶ行をつながないための値。
    // -0.02: 枠のぶれで隣の行と少し重なっても続きとみなす。大きく重なる行 (別の段の行) はつながない。
    // どれも見本の画像の元の HTML (documents/design/chat-screen-samples/) の配置からの見積もり。
    // 見本の画像を Vision で読んだ実測では、名前と時刻の 4 組の間は -0.5%〜2.3%、上下の中心のずれは低い方の行の高さの 15% 以内だった
    // (CI の実測: https://github.com/bannzai/poppo/actions/runs/45587820896 )
    abs(line.boundingBox.midY - leftLine.boundingBox.midY) <= 0.5 * min(leftLine.boundingBox.height, line.boundingBox.height)
        && (-0.02...0.06).contains(line.boundingBox.minX - leftLine.boundingBox.maxX)
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
    // 0.1: 左右の余白が同じくらいの行 (中央から少しずれて、中央の行として除かれなかった行) を利用者の発言にしないため、左の余白が右より 1 割以上大きいことも求める。
    // どちらも見積もりで、実際のスクリーンショットでは測っていない
    return minX >= 0.2 && minX - (1 - maxX) >= 0.1
}
