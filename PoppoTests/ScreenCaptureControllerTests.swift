import Foundation
import Testing
@testable import Poppo

/// テスト用の取り込みの実体。start と stop が呼ばれた回数を数えるだけで、画面は取り込まない。
/// テストは onEvent を直接呼んで、取り込みの実体が知らせる出来事を流す
final class FakeScreenCaptureSource: ScreenCaptureSource {
    /// 出来事を渡して呼ぶ処理。controller が設定し、テストが呼ぶ
    var onEvent: ((ScreenCaptureEvent) -> Void)?
    /// start が呼ばれた回数
    private(set) var startCallCount = 0
    /// stop が呼ばれた回数
    private(set) var stopCallCount = 0

    /// 呼ばれた回数を数えるだけで、出来事は知らせない
    func start() {
        startCallCount += 1
    }

    /// 呼ばれた回数を数えるだけで、出来事は知らせない
    func stop() {
        stopCallCount += 1
    }
}

/// テストで使う時計。now を書き換えて、取り込みの途中で時刻を進める
final class TestClock {
    /// 今の時刻として返す値
    var now: Date

    // 最初の時刻を渡して作るため。class は memberwise initializer が作られない
    init(now: Date) {
        self.now = now
    }
}

/// 偽物の取り込みの実体をつないだ controller を作って返す。source は偽物、clock は時計、
/// latestReadingFileURL は取り込みが終わった時に削除する読み取り結果の場所、diagnosticsFileURL は診断の記録の場所
func makeScreenCaptureController(
    source: FakeScreenCaptureSource,
    clock: TestClock,
    latestReadingFileURL: URL?,
    diagnosticsFileURL: URL?
) -> ScreenCaptureController {
    ScreenCaptureController(
        makeSource: { source },
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: diagnosticsFileURL,
        now: { clock.now }
    )
}

/// 作った直後は「始めていない」で、診断の記録が無く、取り込みの実体を作っていないこと。
/// アプリの起動だけで ScreenCaptureKit に触らないようにするため
@Test func screenCaptureStartsAsNotStartedWithoutCreatingSource() {
    var makeSourceCallCount = 0
    let controller = ScreenCaptureController(
        makeSource: {
            makeSourceCallCount += 1
            return FakeScreenCaptureSource()
        },
        latestReadingFileURL: nil,
        diagnosticsFileURL: temporaryFileURL(),
        now: { Date(timeIntervalSinceReferenceDate: 1000) }
    )

    #expect(controller.status == .notStarted)
    #expect(controller.diagnostics == nil)
    #expect(makeSourceCallCount == 0)
}

/// 始める操作で取り込みの実体の start が 1 回呼ばれ、対象が選ばれるまでは「始めていない」のままであること
@Test func screenCaptureStartAsksSourceAndWaitsForSelection() {
    let source = FakeScreenCaptureSource()
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )

    controller.start()

    #expect(source.startCallCount == 1)
    #expect(controller.status == .notStarted)
    #expect(controller.diagnostics == nil)
}

/// 映像の受け取りが始まると「取り込み中」になり、始めた時刻だけを入れた診断の記録が、すぐにファイルへ保存されること
@Test func screenCaptureBecomesCapturingAndSavesStartedAt() {
    let source = FakeScreenCaptureSource()
    let diagnosticsFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: nil,
        diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()

    source.onEvent?(.started)

    #expect(controller.status == .capturing)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL) == controller.diagnostics)
}

/// 取り込み中に始める操作をしても、取り込みの実体の start をもう一度呼ばないこと
@Test func screenCaptureStartDoesNothingWhileCapturing() {
    let source = FakeScreenCaptureSource()
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    controller.start()

    #expect(source.startCallCount == 1)
    #expect(controller.status == .capturing)
}

/// 映像を受け取るたびに、受け取った数と最後に受け取った時刻が進むこと。
/// ファイルへの保存は、前に保存した映像から 1 秒経つまで行わないこと
@Test func screenCaptureCountsFramesAndSavesAtMostOncePerSecond() {
    let source = FakeScreenCaptureSource()
    let diagnosticsFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: nil,
        diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)

    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1000.5)))
    #expect(controller.diagnostics?.receivedFrameCount == 1)
    #expect(controller.diagnostics?.lastFrameReceivedAt == Date(timeIntervalSinceReferenceDate: 1000.5))
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL)?.receivedFrameCount == 1)

    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001.4)))
    #expect(controller.diagnostics?.receivedFrameCount == 2)
    #expect(controller.diagnostics?.lastFrameReceivedAt == Date(timeIntervalSinceReferenceDate: 1001.4))
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL)?.receivedFrameCount == 1)

    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001.5)))
    #expect(controller.diagnostics?.receivedFrameCount == 3)
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL)?.receivedFrameCount == 3)
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL)?.lastFrameReceivedAt == Date(timeIntervalSinceReferenceDate: 1001.5))
}

/// 取り込み中でない時に届いた映像は数えないこと
@Test func screenCaptureIgnoresFramesWhenNotCapturing() {
    let source = FakeScreenCaptureSource()
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()

    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1000.5)))

    #expect(controller.status == .notStarted)
    #expect(controller.diagnostics == nil)
}

/// 停止の操作で「止めた」になり、取り込みの実体の stop が呼ばれ、止めた時刻と理由が保存され、読み取り結果が削除されること
@Test func screenCaptureStopRecordsReasonAndDeletesLatestReading() throws {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let diagnosticsFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    let controller = makeScreenCaptureController(
        source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    clock.now = Date(timeIntervalSinceReferenceDate: 1060)

    controller.stop()

    #expect(controller.status == .stopped)
    #expect(source.stopCallCount == 1)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stoppedAt: Date(timeIntervalSinceReferenceDate: 1060),
            stopReason: .stoppedInApp,
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 1001),
            receivedFrameCount: 1
        )
    )
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL) == controller.diagnostics)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(!controller.failedToDeleteLatestReading)
}

/// 取り込み中でない時の停止の操作は何もしないこと (取り込みの実体の stop を呼ばず、読み取り結果も消さない)
@Test func screenCaptureStopDoesNothingWhenNotCapturing() throws {
    let source = FakeScreenCaptureSource()
    let latestReadingFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()

    controller.stop()

    #expect(controller.status == .notStarted)
    #expect(source.stopCallCount == 0)
    #expect(controller.diagnostics == nil)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 利用者がアプリの外で止めた時は「止めた」になり、理由が「アプリの外での停止」で残り、読み取り結果が削除されること
@Test func screenCaptureStoppedOutsideAppRecordsReasonAndDeletesLatestReading() throws {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1030)

    source.onEvent?(.stoppedByUser)

    #expect(controller.status == .stopped)
    #expect(controller.diagnostics?.stoppedAt == Date(timeIntervalSinceReferenceDate: 1030))
    #expect(controller.diagnostics?.stopReason == .stoppedOutsideApp)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 取り込み中にエラーで止まった時は「エラーで止まった」になり、エラーの種類が残り、読み取り結果が削除されること
@Test func screenCaptureFailureWhileCapturingRecordsErrorAndDeletesLatestReading() throws {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let diagnosticsFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    let controller = makeScreenCaptureController(
        source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1045)

    source.onEvent?(.failed("com.apple.ScreenCaptureKit.SCStreamErrorDomain -3824: missing background mode"))

    #expect(controller.status == .failed)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stoppedAt: Date(timeIntervalSinceReferenceDate: 1045),
            stopReason: .error("com.apple.ScreenCaptureKit.SCStreamErrorDomain -3824: missing background mode"),
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL) == controller.diagnostics)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 映像の受け取りが始まる前にエラーになった時は「エラーで止まった」になり、始めた時刻が無い記録が残ること。
/// 取り込みは始まっていないため、読み取り結果は消さない
@Test func screenCaptureFailureBeforeStartRecordsErrorAndKeepsLatestReading() throws {
    let source = FakeScreenCaptureSource()
    let latestReadingFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()

    source.onEvent?(.failed("picker failed"))

    #expect(controller.status == .failed)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: nil,
            stoppedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stopReason: .error("picker failed"),
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 利用者が取り込む対象を選ばずに閉じた時は、状態も診断の記録も変わらないこと
@Test func screenCaptureSelectionCancelKeepsNotStarted() {
    let source = FakeScreenCaptureSource()
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()

    source.onEvent?(.selectionCancelled)

    #expect(controller.status == .notStarted)
    #expect(controller.diagnostics == nil)
}

/// 止めた後にもう一度始めると「取り込み中」に戻り、診断の記録が新しい 1 回のものに置き換わること
@Test func screenCaptureRestartReplacesDiagnostics() {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: nil, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    controller.stop()
    clock.now = Date(timeIntervalSinceReferenceDate: 2000)

    controller.start()
    source.onEvent?(.started)

    #expect(source.startCallCount == 2)
    #expect(controller.status == .capturing)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 2000),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
}

/// 前回の診断の記録がファイルにある時は、作った直後からその記録を見られること (止まる前にアプリが終了した後の確認のため)。
/// 状態は「始めていない」のままであること
@Test func screenCaptureLoadsSavedDiagnosticsOnInit() throws {
    let diagnosticsFileURL = temporaryFileURL()
    try save(
        screenCaptureDiagnostics: ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 620),
            receivedFrameCount: 42
        ),
        fileURL: diagnosticsFileURL
    )

    let controller = makeScreenCaptureController(
        source: FakeScreenCaptureSource(),
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: nil,
        diagnosticsFileURL: diagnosticsFileURL
    )

    #expect(controller.status == .notStarted)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 620),
            receivedFrameCount: 42
        )
    )
}

/// 取り込みが終わった時に読み取り結果を削除できなかったら、そのことが controller に残ること (画面に出すため)
@Test func screenCaptureRemembersFailureToDeleteLatestReading() throws {
    let source = FakeScreenCaptureSource()
    // 書き込めないディレクトリの中のファイルは削除できない
    let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let latestReadingFileURL = directoryURL.appending(path: "latest-reading.json")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryURL.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
    }
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    controller.stop()

    #expect(controller.status == .stopped)
    #expect(controller.failedToDeleteLatestReading)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}
