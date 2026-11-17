import CoreGraphics
import Foundation
import Testing
@testable import Poppo

/// テスト用の取り込みの実体。start と stop が呼ばれた回数を数えるだけで、画面は取り込まない。
/// テストは onEvent と onFrameImage を直接呼んで、取り込みの実体が知らせる出来事と映像を流す
final class FakeScreenCaptureSource: ScreenCaptureSource {
    /// 出来事を渡して呼ぶ処理。controller が設定し、テストが呼ぶ
    var onEvent: ((ScreenCaptureEvent) -> Void)?
    /// 映像を受け取った時に呼ぶ処理。controller が設定し、テストが呼ぶ
    var onFrameImage: ((_ receivedAt: Date, _ makeImage: () throws -> CGImage?) -> Void)?
    /// start が呼ばれた回数
    private(set) var startCallCount = 0
    /// stop が呼ばれた回数
    private(set) var stopCallCount = 0
    /// stop が呼ばれた時に知らせる出来事。nil の時は何も知らせない (止める操作の結果がまだ届いていない間を表す)。
    /// 既定は、本物の実体が止められた時と同じ stoppedByApp
    var eventOnStop: ScreenCaptureEvent? = .stoppedByApp

    /// 呼ばれた回数を数えるだけで、出来事は知らせない
    func start() {
        startCallCount += 1
    }

    /// 呼ばれた回数を数え、eventOnStop の出来事を知らせる
    func stop() {
        stopCallCount += 1
        if let eventOnStop {
            onEvent?(eventOnStop)
        }
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
/// latestReadingFileURL は取り込みが終わった時に削除する読み取り結果の場所、diagnosticsFileURL は診断の記録の場所。
/// 取り込んだ画面を読む処理には、何も読めない偽物を渡す (画面の読み取りは ScreenReadingTests.swift が確かめる)
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
        now: { clock.now },
        recognizeTextLines: { _ in [] },
        translateTexts: { $0 },
        canGenerateReplies: { false },
        generateReplyTexts: { _ in [] }
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
        now: { Date(timeIntervalSinceReferenceDate: 1000) },
        recognizeTextLines: { _ in [] },
        translateTexts: { $0 },
        canGenerateReplies: { false },
        generateReplyTexts: { _ in [] }
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

/// 取り込みを止めた後に届いた映像は数えないこと (止めた後の記録が、止めた時点のまま残る)
@Test func screenCaptureIgnoresFramesAfterStop() {
    let source = FakeScreenCaptureSource()
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1000.5)))
    controller.stop()

    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1002)))

    #expect(controller.status == .stopped)
    #expect(controller.diagnostics?.receivedFrameCount == 1)
    #expect(controller.diagnostics?.lastFrameReceivedAt == Date(timeIntervalSinceReferenceDate: 1000.5))
}

/// 停止の操作で「止めた」になり、取り込みの実体の stop が呼ばれ、止めた時刻と理由が保存され、読み取り結果が削除されること
@Test func screenCaptureStopRecordsReasonAndDeletesLatestReading() throws {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let diagnosticsFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
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
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)

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
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
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
    let controller = makeScreenCaptureController(
        source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
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
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)

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
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryURL.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
    }

    controller.stop()

    #expect(controller.status == .stopped)
    #expect(controller.failedToDeleteLatestReading)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 削除できなかった後に取り込みを始め直すと、削除できなかった印が消えること (新しい取り込みの間は、前の失敗を出し続けない)
@Test func screenCaptureClearsDeleteFailureWhenCaptureStartsAgain() throws {
    let source = FakeScreenCaptureSource()
    let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let latestReadingFileURL = directoryURL.appending(path: "latest-reading.json")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryURL.path)
    controller.stop()
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
    #expect(controller.failedToDeleteLatestReading)

    controller.start()
    source.onEvent?(.started)

    #expect(controller.status == .capturing)
    #expect(!controller.failedToDeleteLatestReading)
}

/// 作った時に読み取り結果が残っていたら削除すること。作った時点では取り込んでいないため、残っているのは
/// 取り込み中にアプリが終了した時に消せなかった読み取り結果で、キーボードに出し続けない
@Test func screenCaptureDeletesLatestReadingLeftOnInit() throws {
    let latestReadingFileURL = temporaryFileURL()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)

    let controller = makeScreenCaptureController(
        source: FakeScreenCaptureSource(),
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )

    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(controller.status == .notStarted)
    #expect(!controller.failedToDeleteLatestReading)
}

/// 作った時に残っていた読み取り結果を削除できなかったら、そのことが controller に残ること (画面に出すため)
@Test func screenCaptureRemembersFailureToDeleteLatestReadingOnInit() throws {
    let directoryURL = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let latestReadingFileURL = directoryURL.appending(path: "latest-reading.json")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directoryURL.path)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directoryURL.path)
    }

    #expect(
        makeScreenCaptureController(
            source: FakeScreenCaptureSource(),
            clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
            latestReadingFileURL: latestReadingFileURL,
            diagnosticsFileURL: nil
        ).failedToDeleteLatestReading
    )
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 取り込み中に、映像の受け取りが始まった知らせが重ねて届いても、診断の記録を作り直さないこと (始めた時刻と受け取った数が残る)
@Test func screenCaptureIgnoresDuplicateStartedWhileCapturing() {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: nil, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    clock.now = Date(timeIntervalSinceReferenceDate: 1500)

    source.onEvent?(.started)

    #expect(controller.status == .capturing)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 1001),
            receivedFrameCount: 1
        )
    )
}

/// 取り込み中でない時に「アプリの外で止めた」知らせが届いても、状態・診断の記録・読み取り結果を変えないこと
@Test func screenCaptureIgnoresStoppedByUserWhenNotCapturing() throws {
    let source = FakeScreenCaptureSource()
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)

    source.onEvent?(.stoppedByUser)

    #expect(controller.status == .notStarted)
    #expect(controller.diagnostics == nil)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 止めた後に始め直してエラーになった時は「エラーで止まった」になり、診断の記録が、そのエラーの記録に置き換わること
@Test func screenCaptureFailureAfterStopReplacesDiagnosticsWithError() {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: nil, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    controller.stop()
    clock.now = Date(timeIntervalSinceReferenceDate: 2000)
    controller.start()

    source.onEvent?(.failed("picker failed"))

    #expect(controller.status == .failed)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: nil,
            stoppedAt: Date(timeIntervalSinceReferenceDate: 2000),
            stopReason: .error("picker failed"),
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
}

/// エラーで止まった後に始め直して映像の受け取りが始まると「取り込み中」に戻り、診断の記録が新しい 1 回のものに置き換わること
@Test func screenCaptureRecoversFromFailureWhenCaptureStarts() {
    let source = FakeScreenCaptureSource()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: nil, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.failed("picker failed"))
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

/// 診断の記録として読めない中身のファイルは、読み出しが nil を返すこと
@Test func screenCaptureDiagnosticsIsNilWhenFileIsNotDiagnostics() throws {
    let fileURL = temporaryFileURL()
    try Data("{\"startedAt\": \"yesterday\"}".utf8).write(to: fileURL)

    #expect(loadScreenCaptureDiagnostics(fileURL: fileURL) == nil)
}

/// 診断の記録を保存していない時は、読み出しが nil を返すこと
@Test func screenCaptureDiagnosticsIsNilWhenNothingIsSaved() {
    #expect(loadScreenCaptureDiagnostics(fileURL: temporaryFileURL()) == nil)
}

/// 診断の記録は、置く場所のディレクトリがまだ無くても保存でき、読み出すと同じ値が返ること
@Test func screenCaptureDiagnosticsSaveCreatesDirectory() throws {
    let fileURL = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString)
        .appending(path: "screen-capture-diagnostics.json")

    try save(
        screenCaptureDiagnostics: ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            stoppedAt: Date(timeIntervalSinceReferenceDate: 560),
            stopReason: .error("stream failed"),
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 559),
            receivedFrameCount: 7
        ),
        fileURL: fileURL
    )

    #expect(
        loadScreenCaptureDiagnostics(fileURL: fileURL) == ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            stoppedAt: Date(timeIntervalSinceReferenceDate: 560),
            stopReason: .error("stream failed"),
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 559),
            receivedFrameCount: 7
        )
    )
}

/// 止める操作の結果がまだ届いていない間は「取り込み中」のままで、読み取り結果も消さないこと (止まったと分かる前に、止めたと出さない)
@Test func screenCaptureStaysCapturingUntilSourceReportsStopped() throws {
    let source = FakeScreenCaptureSource()
    source.eventOnStop = nil
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)

    controller.stop()

    #expect(source.stopCallCount == 1)
    #expect(controller.status == .capturing)
    #expect(controller.diagnostics?.stoppedAt == nil)
    #expect(controller.diagnostics?.stopReason == nil)
    #expect(controller.stopFailureDescription == nil)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)

    source.onEvent?(.stoppedByApp)

    #expect(controller.status == .stopped)
    #expect(controller.diagnostics?.stopReason == .stoppedInApp)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 止める操作が失敗した時は「取り込み中」のままで、エラーが残り、読み取り結果も診断の記録の止めた時刻も変えないこと
/// (画面を取り込み続けているかもしれないのに、止めたと出さない)。もう一度止めて止まると「止めた」になり、エラーが消えること
@Test func screenCaptureStopFailureKeepsCapturingAndAllowsRetry() throws {
    let source = FakeScreenCaptureSource()
    source.eventOnStop = .stopFailed("com.apple.ScreenCaptureKit.SCStreamErrorDomain -3802: failed to stop")
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(source: source, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: nil)
    controller.start()
    source.onEvent?(.started)
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 1001), label: "first"), fileURL: latestReadingFileURL)
    clock.now = Date(timeIntervalSinceReferenceDate: 1060)

    controller.stop()

    #expect(controller.status == .capturing)
    #expect(controller.stopFailureDescription == "com.apple.ScreenCaptureKit.SCStreamErrorDomain -3802: failed to stop")
    #expect(controller.diagnostics?.stoppedAt == nil)
    #expect(controller.diagnostics?.stopReason == nil)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)

    source.eventOnStop = .stoppedByApp
    clock.now = Date(timeIntervalSinceReferenceDate: 1090)
    controller.stop()

    #expect(source.stopCallCount == 2)
    #expect(controller.status == .stopped)
    #expect(controller.stopFailureDescription == nil)
    #expect(controller.diagnostics?.stoppedAt == Date(timeIntervalSinceReferenceDate: 1090))
    #expect(controller.diagnostics?.stopReason == .stoppedInApp)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 止める操作が失敗した後、やり直した止める操作の結果が届くまでの間は、前の失敗のエラーを出さないこと
@Test func screenCaptureClearsStopFailureWhenStopIsRetried() {
    let source = FakeScreenCaptureSource()
    source.eventOnStop = .stopFailed("failed to stop")
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    controller.stop()
    #expect(controller.stopFailureDescription == "failed to stop")

    source.eventOnStop = nil
    controller.stop()

    #expect(controller.status == .capturing)
    #expect(controller.stopFailureDescription == nil)
}

/// 止める操作が失敗した後に、取り込みがアプリの外で止まると、「止めた」になってエラーが消えること
@Test func screenCaptureClearsStopFailureWhenCaptureEnds() {
    let source = FakeScreenCaptureSource()
    source.eventOnStop = .stopFailed("failed to stop")
    let controller = makeScreenCaptureController(
        source: source, clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)), latestReadingFileURL: nil, diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    controller.stop()

    source.onEvent?(.stoppedByUser)

    #expect(controller.status == .stopped)
    #expect(controller.stopFailureDescription == nil)
    #expect(controller.diagnostics?.stopReason == .stoppedOutsideApp)
}

/// 取り込み中でない時に、止める操作の結果 (止まった・止められなかった) が届いても、状態・エラー・診断の記録・読み取り結果を変えないこと
@Test func screenCaptureIgnoresStopResultsWhenNotCapturing() throws {
    let source = FakeScreenCaptureSource()
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenCaptureController(
        source: source,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    try save(latestReading: sampleLatestReading(capturedAt: Date(timeIntervalSinceReferenceDate: 900), label: "first"), fileURL: latestReadingFileURL)

    source.onEvent?(.stoppedByApp)
    source.onEvent?(.stopFailed("failed to stop"))

    #expect(controller.status == .notStarted)
    #expect(controller.stopFailureDescription == nil)
    #expect(controller.diagnostics == nil)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)
}

/// 診断の記録をファイルに保存するのは DEBUG ビルドだけであること (DEBUG ビルドには置き場所があり、それ以外のビルドには無い)。
/// テストを走らせた構成の側だけを確かめる
@Test func screenCaptureDiagnosticsFileIsUsedOnlyInDebugBuild() {
    #if DEBUG
    #expect(screenCaptureDiagnosticsFileURL()?.lastPathComponent == "screen-capture-diagnostics.json")
    #else
    #expect(screenCaptureDiagnosticsFileURL() == nil)
    #endif
}

// ScreenCaptureKit が無い環境 (iOS Simulator) でだけコンパイルされる取り込みの実体のテスト。テストは simulator で走る
#if !canImport(ScreenCaptureKit)
/// ScreenCaptureKit が無い環境の取り込みの実体は、始める操作のたびに、取り込めないことをエラーとして 1 回知らせること
@Test func unavailableScreenCaptureSourceReportsFailureOnEachStart() {
    let source = UnavailableScreenCaptureSource()
    var events: [ScreenCaptureEvent] = []
    source.onEvent = { events.append($0) }

    source.start()
    #expect(events == [.failed("ScreenCaptureKit is not available in this environment (iOS Simulator)")])

    source.start()
    #expect(
        events == [
            .failed("ScreenCaptureKit is not available in this environment (iOS Simulator)"),
            .failed("ScreenCaptureKit is not available in this environment (iOS Simulator)"),
        ]
    )
}

/// ScreenCaptureKit が無い環境の取り込みの実体は、止める操作で何も知らせないこと
@Test func unavailableScreenCaptureSourceReportsNothingOnStop() {
    let source = UnavailableScreenCaptureSource()
    var events: [ScreenCaptureEvent] = []
    source.onEvent = { events.append($0) }

    source.stop()

    #expect(events.isEmpty)
}

/// ScreenCaptureKit が無い環境では、本体アプリが使う取り込みの実体で始める操作をすると「エラーで止まった」になり、
/// 取り込めない理由が診断の記録に残ること (simulator で「同意して始める」を押した時の動き)
@Test func screenCaptureFailsOnStartWhenScreenCaptureKitIsUnavailable() {
    let controller = ScreenCaptureController(
        makeSource: makeScreenCaptureSource,
        latestReadingFileURL: nil,
        diagnosticsFileURL: nil,
        now: { Date(timeIntervalSinceReferenceDate: 1000) },
        recognizeTextLines: { _ in [] },
        translateTexts: { $0 },
        canGenerateReplies: { false },
        generateReplyTexts: { _ in [] }
    )

    controller.start()

    #expect(controller.status == .failed)
    #expect(
        controller.diagnostics == ScreenCaptureDiagnostics(
            startedAt: nil,
            stoppedAt: Date(timeIntervalSinceReferenceDate: 1000),
            stopReason: .error("ScreenCaptureKit is not available in this environment (iOS Simulator)"),
            lastFrameReceivedAt: nil,
            receivedFrameCount: 0
        )
    )
}
#endif

/// エラーを診断の記録に残す文が、エラーのドメイン・コード・説明を「ドメイン コード: 説明」の形で含むこと
@Test func screenCaptureFailureDescriptionContainsDomainCodeAndMessage() {
    #expect(
        screenCaptureFailureDescription(
            error: NSError(domain: "com.example.capture", code: -3824, userInfo: [NSLocalizedDescriptionKey: "missing background mode"])
        ) == "com.example.capture -3824: missing background mode"
    )
}
