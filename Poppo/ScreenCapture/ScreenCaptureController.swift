import CoreGraphics
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
    /// 直前の止める操作で取り込みを止められなかった時の、エラーの種類 (ドメインとコード) と説明。
    /// 止められた時・止める操作をやり直した時・取り込みが終わった時は nil。nil でない間は、画面を取り込み続けているかもしれない
    private(set) var stopFailureDescription: String?

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
    /// 画像の文字を読む処理
    private let recognizeTextLines: @MainActor (CGImage) async throws -> [RecognizedTextLine]
    /// 文を利用者の言語に訳す処理
    private let translateTexts: @MainActor ([String]) async throws -> [String]
    /// 返信案を作れるか (端末内のモデルが使えるか) を返す処理
    private let canGenerateReplies: @MainActor () -> Bool
    /// 発言から返信の文を作る処理
    private let generateReplyTexts: @MainActor ([ExtractedMessage]) async throws -> [String]
    /// 進んでいる途中の、取り込んだ画面の読み取り。読み取っていない間は nil。
    /// 途中の間は次の読み取りを始めない。テストは、この値を待って読み取りが終わったことを知る
    @ObservationIgnored private(set) var readingTask: Task<Void, Never>?
    /// 何回目の取り込みか。映像の受け取りが始まるたびに 1 増える。
    /// 読み取りの途中で取り込みが終わった (止めた後に始め直した時を含む) ことを見分けるのに使う
    private var captureCount = 0
    /// 今の取り込みで、最後に映像を画像にした時の、その映像を受け取った時刻。まだ画像にしていない時は nil
    private var lastImageMadeAt: Date?
    /// 今の取り込みで、最後に画像にした画面の、比べるための画素の並び (screenFingerprint)。まだ画像にしていない時は nil
    private var lastScreenFingerprint: [UInt8]?
    /// 今の取り込みで、最後に翻訳を試した発言の原文。成功したか失敗したかを問わない。まだ試していない時は nil
    private var lastTriedMessageTexts: [String]?

    /// makeSource は取り込みの実体を作る処理、latestReadingFileURL は読み取り結果を保存し、取り込みが終わった時に削除する場所、
    /// diagnosticsFileURL は診断の記録を置く場所 (nil なら保存しない)、now は今の時刻を返す処理。
    /// recognizeTextLines・translateTexts・canGenerateReplies・generateReplyTexts は、取り込んだ画面を読む時に使う処理
    /// (simulator では翻訳と生成が動かないため、テストで差し替える)。
    /// diagnosticsFileURL に前回の記録があれば、それを diagnostics として読み込む (アプリが終了した後でも前回の記録を見られるようにするため)。
    /// latestReadingFileURL に読み取り結果が残っていれば削除する。作った時点では取り込んでいないため、残っているのは
    /// 取り込み中にアプリが終了した時に消せなかったもので、画面を読んでいない間はキーボードに出し続けない
    init(
        makeSource: @escaping @MainActor () -> any ScreenCaptureSource,
        latestReadingFileURL: URL?,
        diagnosticsFileURL: URL?,
        now: @escaping () -> Date,
        recognizeTextLines: @escaping @MainActor (CGImage) async throws -> [RecognizedTextLine],
        translateTexts: @escaping @MainActor ([String]) async throws -> [String],
        canGenerateReplies: @escaping @MainActor () -> Bool,
        generateReplyTexts: @escaping @MainActor ([ExtractedMessage]) async throws -> [String]
    ) {
        self.makeSource = makeSource
        self.latestReadingFileURL = latestReadingFileURL
        self.diagnosticsFileURL = diagnosticsFileURL
        self.now = now
        self.recognizeTextLines = recognizeTextLines
        self.translateTexts = translateTexts
        self.canGenerateReplies = canGenerateReplies
        self.generateReplyTexts = generateReplyTexts
        diagnostics = diagnosticsFileURL.flatMap { loadScreenCaptureDiagnostics(fileURL: $0) }
        deleteLatestReadingWhileNotCapturing()
    }

    /// 利用者が同意した後に呼ぶ。取り込む対象を選ぶシステムの画面を出す。取り込み中の時は何もしない
    func start() {
        guard status != .capturing else {
            return
        }
        if source == nil {
            source = makeSource()
            source?.onEvent = { [weak self] in self?.handle(event: $0) }
            source?.onFrameImage = { [weak self] receivedAt, makeImage in
                guard let self else {
                    return
                }
                self.readScreenIfNeeded(receivedAt: receivedAt, makeImage: makeImage)
            }
        }
        source?.start()
    }

    /// 取り込みを止める操作をする。取り込み中でない時は何もしない。
    /// 状態が「止めた」になり読み取り結果を削除するのは、取り込みの実体が止まったと知らせた時。
    /// 止められなかった時は「取り込み中」のまま stopFailureDescription にエラーが入る (止まっていないのに止めたと出さない)
    func stop() {
        guard status == .capturing else {
            return
        }
        stopFailureDescription = nil
        source?.stop()
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
            captureCount += 1
            lastImageMadeAt = nil
            lastScreenFingerprint = nil
            lastTriedMessageTexts = nil
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
        case .stoppedByApp:
            guard status == .capturing else {
                return
            }
            finishCapturing(status: .stopped, stopReason: .stoppedInApp)
        case .stopFailed(let failureDescription):
            guard status == .capturing else {
                return
            }
            stopFailureDescription = failureDescription
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

    /// 取り込み中に映像を 1 枚受け取るたびに呼ぶ。その映像の画面を読むかを決め、読む時は読み取り (readingTask) を始める。
    /// receivedAt は映像を受け取った時刻、makeImage はその映像を画像にする処理 (ScreenCaptureSource.onFrameImage と同じ)。
    /// 電池と発熱を抑えるため、次の時は読まない: 取り込み中でない、前の読み取りが途中、前に画像にしてから 2 秒経っていない、
    /// 映像に画面の絵が無い、画面が前に画像にした時と同じ。
    /// 映像を画像にできなかった時は、文字の読み取りの失敗として診断の記録に残す
    private func readScreenIfNeeded(receivedAt: Date, makeImage: () throws -> CGImage?) {
        guard status == .capturing, readingTask == nil else {
            return
        }
        // 2 秒: 映像は 1 秒に何十枚も届くため、そのたびに画像にして比べない。
        // 新しい発言が届いてからキーボードを開くまでの間 (アプリの切り替えや入力欄を押す操作に数秒かかる) に読み終える間隔として置いた見積もりで、
        // 実機の電池と発熱では測っていない (documents/DIRECTION.md「決めたこと」)
        if let lastImageMadeAt, receivedAt.timeIntervalSince(lastImageMadeAt) < 2 {
            return
        }
        let image: CGImage
        do {
            guard let madeImage = try makeImage() else {
                return
            }
            image = madeImage
        } catch {
            lastImageMadeAt = receivedAt
            diagnostics?.reading.recognition.recordFailure(date: now(), failureDescription: screenReadingFailureDescription(error: error))
            saveDiagnostics()
            return
        }
        lastImageMadeAt = receivedAt
        let fingerprint = screenFingerprint(image: image)
        // 画素の並びを作れなかった画面 (nil) は、変わったかを比べられないため読む
        if let fingerprint, fingerprint == lastScreenFingerprint {
            return
        }
        lastScreenFingerprint = fingerprint
        readingTask = Task { [captureCount] in
            await self.readScreen(image: image, capturedAt: receivedAt, captureCount: captureCount)
            self.readingTask = nil
        }
    }

    /// 取り込んだ画面の画像 (image) から読み取り結果を作り、latestReadingFileURL に保存する。前の読み取り結果は上書きされる。
    /// capturedAt は画面を受け取った時刻、captureCount は読み取りを始めた時の取り込みの回。
    /// 各段 (文字の読み取り・翻訳・返信案の生成・保存) の成功と失敗を診断の記録に残す。
    /// 次の時は翻訳へ進まず、保存してある読み取り結果をそのまま残す: 画面に Poppo のキーボードが出している読み取り結果が映っている、
    /// 発言が 1 つも無い、発言が前に翻訳を試した時と同じ。
    /// 読み取りの途中で取り込みが終わっていた時は、保存も記録もしない (止めた後に読み取り結果を残さない)
    private func readScreen(image: CGImage, capturedAt: Date, captureCount: Int) async {
        let lines: [RecognizedTextLine]
        do {
            lines = try await recognizeTextLines(image)
        } catch {
            recordReading(captureCount: captureCount) {
                $0.recognition.recordFailure(date: now(), failureDescription: screenReadingFailureDescription(error: error))
            }
            return
        }
        guard isCapturing(captureCount: captureCount) else {
            return
        }
        if let savedLatestReading = latestReadingFileURL.flatMap({ loadLatestReading(fileURL: $0) }),
            showsLatestReading(lines: lines, latestReading: savedLatestReading)
        {
            recordReading(captureCount: captureCount) {
                $0.recognition.recordSuccess(date: now())
                $0.shownLatestReadingCount += 1
            }
            return
        }
        let extractedMessages = extractMessages(lines: lines)
        guard !extractedMessages.isEmpty else {
            recordReading(captureCount: captureCount) {
                $0.recognition.recordSuccess(date: now())
                $0.noMessagesCount += 1
            }
            return
        }
        guard extractedMessages.map(\.text) != lastTriedMessageTexts else {
            recordReading(captureCount: captureCount) {
                $0.recognition.recordSuccess(date: now())
                $0.unchangedMessagesCount += 1
            }
            return
        }
        // 翻訳に失敗した発言も「試した」として覚える。同じ画面が映っている間、失敗する翻訳を 2 秒ごとに繰り返さないため
        lastTriedMessageTexts = extractedMessages.map(\.text)
        recordReading(captureCount: captureCount) { $0.recognition.recordSuccess(date: now()) }

        // readChat は返信案を作れなかった理由を返さない (翻訳だけを返す) ため、渡す処理の中で理由を覚える
        var didTranslateMessages = false
        var replyGenerationFailureDescription: String?
        let isReplyGenerationAvailable = self.canGenerateReplies()
        let reading: (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
        do {
            reading = try await readChat(
                image: image,
                recognizeTextLines: { _ in lines },
                translateTexts: { texts in
                    guard didTranslateMessages else {
                        didTranslateMessages = true
                        return try await self.translateTexts(texts)
                    }
                    // readChat の 2 回目の翻訳は、返信の文の意味を作る翻訳で、返信案の生成の段に入る
                    do {
                        return try await self.translateTexts(texts)
                    } catch {
                        replyGenerationFailureDescription = screenReadingFailureDescription(error: error)
                        throw error
                    }
                },
                canGenerateReplies: isReplyGenerationAvailable,
                generateReplyTexts: { messages in
                    do {
                        return try await self.generateReplyTexts(messages)
                    } catch {
                        replyGenerationFailureDescription = screenReadingFailureDescription(error: error)
                        throw error
                    }
                }
            )
        } catch ChatReadingError.untranslatableLanguage {
            recordReading(captureCount: captureCount) { $0.untranslatableCount += 1 }
            return
        } catch {
            recordReading(captureCount: captureCount) {
                $0.translation.recordFailure(date: now(), failureDescription: screenReadingFailureDescription(error: error))
            }
            return
        }
        guard isCapturing(captureCount: captureCount) else {
            return
        }
        recordReading(captureCount: captureCount) {
            $0.translation.recordSuccess(date: now())
            if reading.replySuggestions.isEmpty {
                $0.replyGeneration.recordFailure(
                    date: now(),
                    failureDescription: replyGenerationFailureDescription
                        ?? (isReplyGenerationAvailable ? "返信案が 1 つも作られなかった" : "端末内のモデルが使えない")
                )
            } else {
                $0.replyGeneration.recordSuccess(date: now())
            }
        }
        guard let latestReadingFileURL else {
            recordReading(captureCount: captureCount) {
                $0.saving.recordFailure(date: now(), failureDescription: "App Group の共有コンテナを使えない")
            }
            return
        }
        do {
            try save(
                latestReading: LatestReading(capturedAt: capturedAt, messages: reading.messages, replySuggestions: reading.replySuggestions),
                fileURL: latestReadingFileURL
            )
            recordReading(captureCount: captureCount) { $0.saving.recordSuccess(date: now()) }
        } catch {
            recordReading(captureCount: captureCount) {
                $0.saving.recordFailure(date: now(), failureDescription: screenReadingFailureDescription(error: error))
            }
        }
    }

    /// captureCount 回目の取り込みが、今も続いているか
    private func isCapturing(captureCount: Int) -> Bool {
        status == .capturing && self.captureCount == captureCount
    }

    /// captureCount 回目の取り込みが今も続いている時だけ、診断の記録の読み取りの記録を update で書き換えて保存する。
    /// 取り込みが終わっていた時は何もしない (終わった取り込みや、次の取り込みの記録に、前の読み取りの結果を混ぜない)
    private func recordReading(captureCount: Int, update: (inout ScreenReadingDiagnostics) -> Void) {
        guard isCapturing(captureCount: captureCount), var updatedDiagnostics = diagnostics else {
            return
        }
        update(&updatedDiagnostics.reading)
        diagnostics = updatedDiagnostics
        saveDiagnostics()
    }

    /// 取り込み中の状態を終わらせる。状態を status に移し、診断の記録に止まった時刻と理由を残し、読み取り結果を削除する。
    /// 止まった後は画面を読んでいないため、取り込み中に読んだ内容をキーボードに出し続けない
    private func finishCapturing(status: ScreenCaptureStatus, stopReason: ScreenCaptureStopReason) {
        self.status = status
        stopFailureDescription = nil
        diagnostics?.stoppedAt = now()
        diagnostics?.stopReason = stopReason
        saveDiagnostics()
        deleteLatestReadingWhileNotCapturing()
    }

    /// 取り込んでいない時に呼び、latestReadingFileURL の読み取り結果を削除する。削除できなかった時は failedToDeleteLatestReading を true にする。
    /// latestReadingFileURL が nil の時と、読み取り結果が無い時は何もしない
    private func deleteLatestReadingWhileNotCapturing() {
        guard let latestReadingFileURL else {
            return
        }
        do {
            try deleteLatestReading(fileURL: latestReadingFileURL)
        } catch {
            failedToDeleteLatestReading = true
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
