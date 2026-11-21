import Foundation

/// 取り込みが止まった理由
enum ScreenCaptureStopReason: Codable, Equatable {
    /// 利用者が本体アプリの停止の操作で止めた
    case stoppedInApp
    /// 利用者が、このアプリの外 (システムの操作) で止めた
    case stoppedOutsideApp
    /// エラーで始められなかった、または止まった。値はエラーの種類 (ドメインとコード) と説明
    case error(String)
}

/// 取り込んだ画面の読み取りの、1 つの段 (文字の読み取り・翻訳・返信案の生成・保存) の記録。
/// その段が何回成功し、何回失敗し、最後にいつ・どんなエラーで失敗したかを残す
struct ScreenReadingStageDiagnostics: Codable, Equatable {
    /// 成功した回数
    var successCount = 0
    /// 最後に成功した時刻。一度も成功していない時は nil
    var lastSucceededAt: Date?
    /// 失敗した回数
    var failureCount = 0
    /// 最後に失敗した時刻。一度も失敗していない時は nil
    var lastFailedAt: Date?
    /// 最後の失敗のエラーの内容 (エラーの種類と説明)。一度も失敗していない時は nil。
    /// システムのエラーの説明をそのまま持つため、そこに画面から読んだ文字が含まれないかは確かめていない (DEBUG ビルドだけが端末内に保存する)
    var lastFailureDescription: String?

    /// この段が date に成功したことを記録する
    mutating func recordSuccess(date: Date) {
        successCount += 1
        lastSucceededAt = date
    }

    /// この段が date に失敗したことを、エラーの内容 (failureDescription) つきで記録する
    mutating func recordFailure(date: Date, failureDescription: String) {
        failureCount += 1
        lastFailedAt = date
        lastFailureDescription = failureDescription
    }
}

/// 取り込んだ画面の読み取りの記録。直近の 1 回の取り込みの間に、各段が成功・失敗した回数と、読まずに済ませた回数を残す。
/// 実機で「本体アプリが背面にいる間に、読み取り・翻訳・返信案の生成・保存が動くか」を確かめるために使う。
/// 読み取った発言・翻訳・返信案を持つ項目は無い (エラーの内容については ScreenReadingStageDiagnostics.lastFailureDescription)
struct ScreenReadingDiagnostics: Codable, Equatable {
    /// 文字の読み取りの段 (映像を画像にして、画像の文字を読む)
    var recognition = ScreenReadingStageDiagnostics()
    /// 翻訳の段 (読んだ発言を利用者の言語に訳す)
    var translation = ScreenReadingStageDiagnostics()
    /// 返信案の生成の段 (返信の文を作り、その意味を訳す)。選ばれているモデルが使えない時は失敗として数える
    var replyGeneration = ScreenReadingStageDiagnostics()
    /// 最後に返信案の生成の段の結果 (成功か失敗) を記録した時に、返信案を作るモデルとして選ばれていたモデル。
    /// まだ 1 回も記録していない時と、この項目を足す前の版が保存した記録では nil。
    /// 取り込みの途中でモデルを選び直すと、replyGeneration の回数には選び直す前のモデルの分も入る
    var replyGenerationModel: ReplyModel?
    /// 保存の段 (読み取り結果をキーボードが読む場所に書く)
    var saving = ScreenReadingStageDiagnostics()
    /// 画面の文字は読めたが、発言が 1 つも無かった回数 (ホーム画面など)。失敗には数えない
    var noMessagesCount = 0
    /// 発言が前に読んだ時と同じだったため、翻訳と返信案の生成をしなかった回数。失敗には数えない
    var unchangedMessagesCount = 0
    /// 発言が利用者の言語で書かれている等で、訳す必要が無いか訳せなかった回数。失敗には数えない
    var untranslatableCount = 0
    /// 画面に Poppo のキーボードが出している読み取り結果が映っていたため、読み直さなかった回数。失敗には数えない
    var shownLatestReadingCount = 0
}

/// 取り込みの診断の記録。直近の 1 回の取り込みについて、いつ始まり、いつ・なぜ止まり、映像をいくつ受け取り、
/// 取り込んだ画面の読み取りがどう進んだかを残す。
/// 実機で「他のアプリへ切り替えた後も取り込みと読み取りが続くか」を確かめるために使う。映像そのものは含まない
struct ScreenCaptureDiagnostics: Codable, Equatable {
    /// 映像の受け取りが始まった時刻。始まる前にエラーになった時は nil
    var startedAt: Date?
    /// 取り込みが止まった時刻。止まっていない間は nil。
    /// 始めた時刻があるのにこれが nil のまま残っている記録は、止まる前にアプリが終了したことを表す
    var stoppedAt: Date?
    /// 止まった理由。止まっていない間は nil
    var stopReason: ScreenCaptureStopReason?
    /// 最後に映像を受け取った時刻。1 枚も受け取っていない時は nil
    var lastFrameReceivedAt: Date?
    /// 受け取った映像の数
    var receivedFrameCount: Int
    /// 取り込んだ画面の読み取りの記録
    var reading = ScreenReadingDiagnostics()
}

extension ScreenCaptureDiagnostics {
    /// 保存してある記録 (decoder) から作る。読み取りの記録 (reading) が無い記録は、読み取りの記録を空として読む。
    /// 自動で作られる読み出しは初期値のある項目もキーを必須にし、読み取りの記録を足す前の版が保存した記録を読めなくなるため、手で書いている
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            startedAt: try container.decodeIfPresent(Date.self, forKey: .startedAt),
            stoppedAt: try container.decodeIfPresent(Date.self, forKey: .stoppedAt),
            stopReason: try container.decodeIfPresent(ScreenCaptureStopReason.self, forKey: .stopReason),
            lastFrameReceivedAt: try container.decodeIfPresent(Date.self, forKey: .lastFrameReceivedAt),
            receivedFrameCount: try container.decode(Int.self, forKey: .receivedFrameCount),
            // 読み取りの記録を足す前の版の記録は、読み取りを 1 回もしていない取り込みの記録のため、空 (すべて 0 回) として読む
            reading: try container.decodeIfPresent(ScreenReadingDiagnostics.self, forKey: .reading) ?? ScreenReadingDiagnostics()
        )
    }
}

/// 診断の記録を fileURL に保存する。前に保存した記録は上書きされる。
/// 置く場所のディレクトリが無ければ作る。書き込めない時はエラーを投げる
func save(screenCaptureDiagnostics: ScreenCaptureDiagnostics, fileURL: URL) throws {
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(screenCaptureDiagnostics).write(to: fileURL, options: .atomic)
}

/// fileURL に保存してある診断の記録を返す。保存していない時と、診断の記録として読めない中身の時は nil を返す
func loadScreenCaptureDiagnostics(fileURL: URL) -> ScreenCaptureDiagnostics? {
    (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(ScreenCaptureDiagnostics.self, from: $0) }
}
