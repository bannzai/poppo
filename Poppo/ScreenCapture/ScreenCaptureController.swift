import Foundation
import Observation

/// 取り込みの状態
enum ScreenCaptureStatus: Equatable {
    /// 始めていない
    case notStarted
    /// 取り込み中
    case capturing
    /// 利用者が止めた
    case stopped
    /// エラーで始められなかった、または止まった
    case failed
}

/// 取り込みの状態と診断の記録を持ち、取り込みの実体 (ScreenCaptureSource) の出来事で状態を移す。
/// 画面はこの状態を見て、同意の画面・取り込み中の表示・停止の操作を出す
@Observable
final class ScreenCaptureController {
    /// 今の取り込みの状態
    private(set) var status = ScreenCaptureStatus.notStarted
    /// 直近の 1 回の取り込みの診断の記録。一度も始めていない時は nil
    private(set) var diagnostics: ScreenCaptureDiagnostics?
    /// 取り込みが終わった時に、読み取り結果を削除できなかったか。削除できた時と、まだ終わっていない時は false
    private(set) var failedToDeleteLatestReading = false

    /// 取り込みの実体を作る処理。利用者が取り込みを始める操作をするまで呼ばない
    private let makeSource: @MainActor () -> any ScreenCaptureSource
    /// 読み取り結果を置くファイルの場所。取り込みが終わった時に削除する。App Group を使えない時は nil
    private let latestReadingFileURL: URL?
    /// 診断の記録を置くファイルの場所。nil の時は保存しない
    private let diagnosticsFileURL: URL?
    /// 今の時刻を返す処理
    private let now: () -> Date
    /// makeSource が作った取り込みの実体。始める操作をするまでは nil
    private var source: (any ScreenCaptureSource)?
    /// 診断の記録を最後に保存した時の、最後に映像を受け取った時刻。映像を受け取るたびに保存しないための目印
    private var savedLastFrameReceivedAt: Date?

    /// makeSource は取り込みの実体を作る処理、latestReadingFileURL は取り込みが終わった時に削除する読み取り結果の場所、
    /// diagnosticsFileURL は診断の記録を置く場所 (nil なら保存しない)、now は今の時刻を返す処理。
    /// diagnosticsFileURL に前回の記録があれば、それを diagnostics として読み込む (アプリが終了した後でも前回の記録を見られるようにするため)
    init(
        makeSource: @escaping @MainActor () -> any ScreenCaptureSource,
        latestReadingFileURL: URL?,
        diagnosticsFileURL: URL?,
        now: @escaping () -> Date
    ) {
        self.makeSource = makeSource
        self.latestReadingFileURL = latestReadingFileURL
        self.diagnosticsFileURL = diagnosticsFileURL
        self.now = now
        diagnostics = diagnosticsFileURL.flatMap { loadScreenCaptureDiagnostics(fileURL: $0) }
    }

    /// 利用者が同意した後に呼ぶ。取り込む対象を選ぶシステムの画面を出す。取り込み中の時は何もしない
    func start() {
        guard status != .capturing else {
            return
        }
        if source == nil {
            source = makeSource()
            source?.onEvent = { [weak self] in self?.handle(event: $0) }
        }
        source?.start()
    }

    /// 取り込みを止め、読み取り結果を削除する。取り込み中でない時は何もしない
    func stop() {
        guard status == .capturing else {
            return
        }
        source?.stop()
        finishCapturing(status: .stopped, stopReason: .stoppedInApp)
    }

    /// 取り込みの実体が知らせた出来事で、状態と診断の記録を移す
    private func handle(event: ScreenCaptureEvent) {
        switch event {
        case .started:
            guard status != .capturing else {
                return
            }
            status = .capturing
            failedToDeleteLatestReading = false
            diagnostics = ScreenCaptureDiagnostics(
                startedAt: now(),
                stoppedAt: nil,
                stopReason: nil,
                lastFrameReceivedAt: nil,
                receivedFrameCount: 0
            )
            saveDiagnostics()
        case .frameReceived(let receivedAt):
            guard status == .capturing else {
                return
            }
            diagnostics?.lastFrameReceivedAt = receivedAt
            diagnostics?.receivedFrameCount += 1
            // 1 秒: 映像は 1 秒に何十枚も届くため、そのたびにファイルへ書かない。
            // アプリが止まる前に終了した時に、最後に映像を受け取った時刻が 1 秒より古くならない間隔として置いた値
            if savedLastFrameReceivedAt.map({ receivedAt.timeIntervalSince($0) >= 1 }) ?? true {
                saveDiagnostics()
            }
        case .selectionCancelled:
            break
        case .stoppedByUser:
            guard status == .capturing else {
                return
            }
            finishCapturing(status: .stopped, stopReason: .stoppedOutsideApp)
        case .failed(let failureDescription):
            if status == .capturing {
                finishCapturing(status: .failed, stopReason: .error(failureDescription))
            } else {
                status = .failed
                diagnostics = ScreenCaptureDiagnostics(
                    startedAt: nil,
                    stoppedAt: now(),
                    stopReason: .error(failureDescription),
                    lastFrameReceivedAt: nil,
                    receivedFrameCount: 0
                )
                saveDiagnostics()
            }
        }
    }

    /// 取り込み中の状態を終わらせる。状態を status に移し、診断の記録に止まった時刻と理由を残し、読み取り結果を削除する。
    /// 止まった後は画面を読んでいないため、取り込み中に読んだ内容をキーボードに出し続けない
    private func finishCapturing(status: ScreenCaptureStatus, stopReason: ScreenCaptureStopReason) {
        self.status = status
        diagnostics?.stoppedAt = now()
        diagnostics?.stopReason = stopReason
        saveDiagnostics()
        if let latestReadingFileURL {
            do {
                try deleteLatestReading(fileURL: latestReadingFileURL)
            } catch {
                failedToDeleteLatestReading = true
            }
        }
    }

    /// 今の診断の記録を diagnosticsFileURL に保存する。diagnosticsFileURL が nil の時と、記録が無い時は何もしない
    private func saveDiagnostics() {
        guard let diagnostics, let diagnosticsFileURL else {
            return
        }
        // 診断の記録は確認のための補助なので、保存に失敗しても取り込みは続ける。画面には保存前の値 (diagnostics) が出る
        try? save(screenCaptureDiagnostics: diagnostics, fileURL: diagnosticsFileURL)
        savedLastFrameReceivedAt = diagnostics.lastFrameReceivedAt
    }
}
