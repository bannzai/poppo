import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import Poppo

/// テスト用の、取り込んだ画面を読む処理の偽物。文字の読み取り・翻訳・返信の文の生成が呼ばれた回数を数え、
/// テストが決めた行・エラーを返す。画像の中身は見ない
final class FakeScreenReader {
    /// 文字の読み取りが返す行
    var lines: [RecognizedTextLine] = []
    /// 文字の読み取りが投げるエラー。nil の時は lines を返す
    var recognitionError: (any Error)?
    /// 文字の読み取りが呼ばれた時に、行を返す前に実行する処理 (読み取りの途中で起きる出来事をテストが起こすのに使う)
    var onRecognize: (() -> Void)?
    /// 翻訳が投げるエラー。nil の時は、渡された文の頭に「訳: 」を付けて返す
    var translationError: (any Error)?
    /// translationError を投げる翻訳の呼び出しの番号 (1 が最初の呼び出し)。nil の時は、どの呼び出しでも投げる。
    /// 発言の翻訳 (1 回目) は成功し、返信の文の意味を作る翻訳 (2 回目) だけが失敗する場面を作るのに使う
    var translationErrorCallNumber: Int?
    /// 翻訳が呼ばれた時に、訳文を返す前に実行する処理 (翻訳の途中で起きる出来事をテストが起こすのに使う)
    var onTranslate: (() -> Void)?
    /// 返信案を作るモデルとして選ばれているもの
    var selectedReplyModel = ReplyModel.onDevice
    /// 使えるモデル。ここに無いモデルは、返信案を作れないと答える
    var availableReplyModels = Set(ReplyModel.allCases)
    /// 返信案を作れるかを聞かれたモデル。聞かれた順に並ぶ
    private(set) var availabilityCheckedReplyModels: [ReplyModel] = []
    /// 返信の文の生成に渡されたモデル。呼ばれた順に並ぶ
    private(set) var replyGeneratedModels: [ReplyModel] = []
    /// 返信の文の生成が返す文
    var replyTexts = ["Sounds good"]
    /// 返信の文の生成が投げるエラー。nil の時は replyTexts を返す
    var replyGenerationError: (any Error)?
    /// 返信の文の生成が呼ばれた時に、文を返す前に実行する処理 (生成の途中の状態をテストが見るのに使う)
    var onGenerateReplies: (() -> Void)?
    /// 文字の読み取りが呼ばれた回数
    private(set) var recognitionCallCount = 0
    /// 翻訳が呼ばれた回数
    private(set) var translationCallCount = 0
    /// 返信の文の生成が呼ばれた回数
    private(set) var replyGenerationCallCount = 0
    /// 待つ処理が呼ばれた時に、待ち終える前に実行する処理 (待っている間に起きる出来事をテストが起こすのに使う)
    var onWait: (() -> Void)?
    /// 待つ処理に渡された秒数。呼ばれた順に並ぶ
    private(set) var waitedSeconds: [TimeInterval] = []

    /// 呼ばれた回数を数え、onRecognize を実行してから、recognitionError を投げるか lines を返す
    func recognizeTextLines() throws -> [RecognizedTextLine] {
        recognitionCallCount += 1
        onRecognize?()
        if let recognitionError {
            throw recognitionError
        }
        return lines
    }

    /// 呼ばれた回数を数え、onTranslate を実行してから、translationError を投げるか、texts のそれぞれの頭に「訳: 」を付けて返す
    func translate(texts: [String]) throws -> [String] {
        translationCallCount += 1
        onTranslate?()
        if let translationError, translationErrorCallNumber.map({ $0 == translationCallCount }) ?? true {
            throw translationError
        }
        return texts.map { "訳: " + $0 }
    }

    /// 聞かれたモデル (replyModel) を availabilityCheckedReplyModels に足し、そのモデルが availableReplyModels にあるかを返す
    func canGenerateReplies(replyModel: ReplyModel) -> Bool {
        availabilityCheckedReplyModels.append(replyModel)
        return availableReplyModels.contains(replyModel)
    }

    /// 呼ばれた回数を数え、渡されたモデル (replyModel) を replyGeneratedModels に足し、onGenerateReplies を実行してから、
    /// replyGenerationError を投げるか replyTexts を返す
    func generateReplyTexts(replyModel: ReplyModel) throws -> [String] {
        replyGenerationCallCount += 1
        replyGeneratedModels.append(replyModel)
        onGenerateReplies?()
        if let replyGenerationError {
            throw replyGenerationError
        }
        return replyTexts
    }

    /// 渡された秒数を waitedSeconds に足し、onWait を実行する。実際には待たない
    func wait(seconds: TimeInterval) {
        waitedSeconds.append(seconds)
        onWait?()
    }
}

/// 偽物の取り込みの実体 (source) と、偽物の読む処理 (reader) をつないだ controller を作って返す。clock は時計、
/// latestReadingFileURL は読み取り結果の場所、diagnosticsFileURL は診断の記録の場所
private func makeScreenReadingController(
    source: FakeScreenCaptureSource,
    reader: FakeScreenReader,
    clock: TestClock,
    latestReadingFileURL: URL?,
    diagnosticsFileURL: URL?
) -> ScreenCaptureController {
    ScreenCaptureController(
        makeSource: { source },
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: diagnosticsFileURL,
        now: { clock.now },
        recognizeTextLines: { _ in try reader.recognizeTextLines() },
        translateTexts: { try reader.translate(texts: $0) },
        selectedReplyModel: { reader.selectedReplyModel },
        canGenerateReplies: { reader.canGenerateReplies(replyModel: $0) },
        generateReplyTexts: { try reader.generateReplyTexts(replyModel: $1) },
        wait: { reader.wait(seconds: $0) }
    )
}

/// 全面を 1 つの明るさ (gray。0 が黒、1 が白) で塗った画像を返す。明るさが違えば、違う画面として扱われる
private func makeScreenImage(gray: CGFloat) throws -> CGImage {
    let context = try #require(
        CGContext(
            data: nil,
            width: 90,
            height: 195,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 90, height: 195))
    return try #require(context.makeImage())
}

/// controller が進めている読み取りと、見送った映像の扱いが、どちらも終わるまで待つ
private func waitUntilIdle(controller: ScreenCaptureController) async {
    while controller.readingTask != nil || controller.skippedFrameTask != nil {
        await controller.readingTask?.value
        await controller.skippedFrameTask?.value
    }
}

/// 取り込み中の controller に、receivedAt (基準の時刻からの秒) に受け取った映像として image を流し、
/// 始まった読み取りと、見送った映像の扱いが終わるまで待つ
private func receiveFrame(source: FakeScreenCaptureSource, controller: ScreenCaptureController, receivedAt: TimeInterval, image: CGImage) async {
    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: receivedAt)) { image }
    await waitUntilIdle(controller: controller)
}

/// 相手の発言 1 つと利用者の発言 1 つが写った画面の行
private let chatLines = [
    RecognizedTextLine(text: "Are you free today?", boundingBox: CGRect(x: 0.08, y: 0.3, width: 0.5, height: 0.02)),
    RecognizedTextLine(text: "Yes, after lunch", boundingBox: CGRect(x: 0.55, y: 0.4, width: 0.37, height: 0.02)),
]

/// chatLines とは別の発言が写った画面の行
private let otherChatLines = [
    RecognizedTextLine(text: "See you tomorrow", boundingBox: CGRect(x: 0.08, y: 0.3, width: 0.5, height: 0.02))
]

/// 取り込み中に受け取った映像から、発言の原文と訳文・返信案・映像を受け取った時刻を持つ読み取り結果を保存し、
/// 4 つの段すべての成功を、その時の時刻つきで診断の記録に残し、診断の記録をファイルにも保存すること
@Test func screenReadingSavesLatestReadingAndRecordsEveryStage() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let diagnosticsFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source, reader: reader, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1002)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.capturedAt == Date(timeIntervalSinceReferenceDate: 1001))
    #expect(latestReading.messages.map(\.originalText) == ["Are you free today?", "Yes, after lunch"])
    #expect(latestReading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
    #expect(latestReading.replySuggestions.map(\.text) == ["Sounds good"])
    #expect(latestReading.replySuggestions.map(\.meaning) == ["訳: Sounds good"])
    let succeededOnce = ScreenReadingStageDiagnostics(successCount: 1, lastSucceededAt: Date(timeIntervalSinceReferenceDate: 1002))
    #expect(
        controller.diagnostics?.reading
            == ScreenReadingDiagnostics(
                recognition: succeededOnce,
                translation: succeededOnce,
                replyGeneration: succeededOnce,
                replyGenerationModel: .onDevice,
                saving: succeededOnce
            )
    )
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL) == controller.diagnostics)
}

/// 画面の画素が前に読んだ時と同じ間は、2 秒経っていても文字の読み取りをし直さないこと
@Test func screenReadingDoesNotRecognizeAgainWhileScreenPixelsAreSame() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.2))
    await receiveFrame(source: source, controller: controller, receivedAt: 1007, image: try makeScreenImage(gray: 0.2))

    #expect(reader.recognitionCallCount == 1)
    #expect(reader.translationCallCount == 2)
}

/// 画面の画素は変わったが、写っている発言が前に翻訳を試した時と同じなら、文字は読み直すが翻訳と返信案の生成はし直さず、
/// 保存してある読み取り結果を書き換えないこと
@Test func screenReadingDoesNotTranslateAgainWhileMessagesAreSame() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(reader.recognitionCallCount == 2)
    #expect(reader.translationCallCount == 2)
    #expect(reader.replyGenerationCallCount == 1)
    #expect(controller.diagnostics?.reading.unchangedMessagesCount == 1)
    #expect(controller.diagnostics?.reading.recognition.successCount == 2)
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1001))
}

/// 写っている発言が前に翻訳を試した時と同じでも、返信案を作るモデルを選び直した後に届いた画面は読み直し、
/// 選び直したモデルで返信案を作って、保存してある読み取り結果を書き換えること。
/// 前のモデルが使えず翻訳だけを保存していた時に、使えるモデルへ選び直すと返信案が付くことで確かめる。
/// 選び直した後に同じ発言の画面がもう 1 回届いても、3 回目は読み直さない
@Test func screenReadingReadsSameMessagesAgainAfterReplyModelIsReselected() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.selectedReplyModel = .privateCloudCompute
    reader.availableReplyModels = [.onDevice]
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.replySuggestions.isEmpty == true)

    reader.selectedReplyModel = .onDevice
    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(reader.replyGeneratedModels == [.onDevice])
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.replySuggestions.map(\.text) == ["Sounds good"])
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1004))
    #expect(controller.diagnostics?.reading.replyGenerationModel == .onDevice)
    #expect(controller.diagnostics?.reading.unchangedMessagesCount == 0)

    await receiveFrame(source: source, controller: controller, receivedAt: 1007, image: try makeScreenImage(gray: 0.5))

    #expect(reader.replyGeneratedModels == [.onDevice])
    #expect(controller.diagnostics?.reading.unchangedMessagesCount == 1)
}

/// 画面の発言が変わったら読み直し、前の読み取り結果を残さず新しい内容で上書きすること
@Test func screenReadingOverwritesLatestReadingWhenMessagesChange() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = otherChatLines

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.capturedAt == Date(timeIntervalSinceReferenceDate: 1004))
    #expect(latestReading.messages.map(\.originalText) == ["See you tomorrow"])
    #expect(controller.diagnostics?.reading.saving.successCount == 2)
}

/// 前に映像を画像にしてから 2 秒経つまでに届いた映像は、届いた時には画像にせず、2 秒経つまでの残りの時間を待ってから画像にして読むこと
/// (見送った後に画面が変わらなくなると次の映像が届かないため、見送った映像を後で読む)
@Test func screenReadingReadsFrameSkippedWithinTwoSecondsAfterWaitingForRest() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = otherChatLines
    let changedImage = try makeScreenImage(gray: 0.8)
    var makeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1002.5)) {
        makeImageCallCount += 1
        return changedImage
    }
    #expect(makeImageCallCount == 0)
    #expect(reader.recognitionCallCount == 1)

    await waitUntilIdle(controller: controller)
    #expect(reader.waitedSeconds == [0.5])
    #expect(makeImageCallCount == 1)
    #expect(reader.recognitionCallCount == 2)
    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.capturedAt == Date(timeIntervalSinceReferenceDate: 1002.5))
    #expect(latestReading.messages.map(\.originalText) == ["See you tomorrow"])
}

/// 前に映像を画像にしてからちょうど 2 秒経って届いた映像は、待たずに、届いた時に画像にすること
@Test func screenReadingMakesImageImmediatelyWhenTwoSecondsHavePassed() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    let changedImage = try makeScreenImage(gray: 0.8)
    var makeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1003)) {
        makeImageCallCount += 1
        return changedImage
    }
    #expect(makeImageCallCount == 1)

    await waitUntilIdle(controller: controller)
    #expect(reader.waitedSeconds.isEmpty)
    #expect(reader.recognitionCallCount == 2)
}

/// 見送った映像が続いた時は、最後の 1 枚だけを画像にして読み、その前に見送った映像は画像にしないこと
@Test func screenReadingReadsOnlyLastOfSkippedFrames() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = otherChatLines
    let firstSkippedImage = try makeScreenImage(gray: 0.5)
    let lastSkippedImage = try makeScreenImage(gray: 0.8)
    var firstSkippedMakeImageCallCount = 0
    var lastSkippedMakeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1001.5)) {
        firstSkippedMakeImageCallCount += 1
        return firstSkippedImage
    }
    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1002)) {
        lastSkippedMakeImageCallCount += 1
        return lastSkippedImage
    }
    await waitUntilIdle(controller: controller)

    #expect(firstSkippedMakeImageCallCount == 0)
    #expect(lastSkippedMakeImageCallCount == 1)
    #expect(reader.waitedSeconds == [1.5])
    #expect(reader.recognitionCallCount == 2)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1002))
}

/// 前の読み取りが途中の間に届いた映像は、届いた時には画像にせず、その読み取りが終わってから、待たずに画像にして読むこと
@Test func screenReadingReadsFrameSkippedDuringReadingAfterReadingEnds() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    let changedImage = try makeScreenImage(gray: 0.8)
    var makeImageCallCount = 0
    var makeImageCallCountRightAfterFrameArrived: Int?
    reader.onRecognize = {
        reader.onRecognize = nil
        source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1010)) {
            makeImageCallCount += 1
            return changedImage
        }
        makeImageCallCountRightAfterFrameArrived = makeImageCallCount
    }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(makeImageCallCountRightAfterFrameArrived == 0)
    #expect(makeImageCallCount == 1)
    #expect(reader.waitedSeconds.isEmpty)
    #expect(reader.recognitionCallCount == 2)
    #expect(controller.diagnostics?.reading.saving.successCount == 1)
    #expect(controller.diagnostics?.reading.unchangedMessagesCount == 1)
}

/// 前の読み取りが長くかかった後に、見送った映像を読んだ時は、その時刻から 2 秒経つまで次の映像を画像にしないこと
/// (見送った映像を受け取った時刻ではなく、実際に画像にした時刻から数える)
@Test func screenReadingWaitsTwoSecondsAfterReadingSkippedFrameLate() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1001))
    let controller = makeScreenReadingController(
        source: source, reader: reader, clock: clock, latestReadingFileURL: temporaryFileURL(), diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    let skippedImage = try makeScreenImage(gray: 0.5)
    reader.onRecognize = {
        reader.onRecognize = nil
        source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1002)) { skippedImage }
        clock.now = Date(timeIntervalSinceReferenceDate: 1006)
    }
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    #expect(reader.recognitionCallCount == 2)
    let nextImage = try makeScreenImage(gray: 0.8)
    var makeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1007.5)) {
        makeImageCallCount += 1
        return nextImage
    }
    #expect(makeImageCallCount == 0)

    await waitUntilIdle(controller: controller)
    #expect(reader.waitedSeconds == [1, 0.5])
    #expect(makeImageCallCount == 1)
}

/// 翻訳の成功は、返信案の生成が終わるのを待たずに、発言の翻訳が終わった時点で診断の記録に残ること
/// (返信案の生成が返ってこない時に、止まった段が翻訳ではなく返信案の生成だと見分けられるようにする)
@Test func screenReadingRecordsTranslationSuccessBeforeReplyGenerationEnds() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    var readingDuringReplyGeneration: ScreenReadingDiagnostics?
    reader.onGenerateReplies = { readingDuringReplyGeneration = controller.diagnostics?.reading }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(readingDuringReplyGeneration?.translation.successCount == 1)
    #expect(readingDuringReplyGeneration?.replyGeneration == ScreenReadingStageDiagnostics())
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
    #expect(controller.diagnostics?.reading.replyGeneration.successCount == 1)
}

/// 訳文の数が発言の数と合わない時は、翻訳の成功を記録せず、翻訳の失敗だけを記録すること
@Test func screenReadingRecordsOnlyFailureWhenTranslationCountDoesNotMatch() async throws {
    let source = FakeScreenCaptureSource()
    let controller = ScreenCaptureController(
        makeSource: { source },
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil,
        now: { Date(timeIntervalSinceReferenceDate: 1000) },
        recognizeTextLines: { _ in chatLines },
        translateTexts: { _ in ["訳が 1 つだけ"] },
        selectedReplyModel: { .onDevice },
        canGenerateReplies: { _ in false },
        generateReplyTexts: { _, _ in [] },
        wait: { _ in }
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.translation.successCount == 0)
    #expect(controller.diagnostics?.reading.translation.failureCount == 1)
    #expect(controller.diagnostics?.reading.translation.lastFailureDescription == "ChatReadingError.incompleteTranslation")
}

/// 見送った映像を読むのを待っている間に取り込みが止まった時は、見送った映像を画像にせず、何も保存しないこと
@Test func screenReadingDoesNotReadSkippedFrameWhenCaptureStopsWhileWaiting() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    let changedImage = try makeScreenImage(gray: 0.8)
    var makeImageCallCount = 0
    reader.onWait = { controller.stop() }

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1002)) {
        makeImageCallCount += 1
        return changedImage
    }
    await waitUntilIdle(controller: controller)

    #expect(controller.status == .stopped)
    #expect(reader.waitedSeconds == [1])
    #expect(makeImageCallCount == 0)
    #expect(reader.recognitionCallCount == 1)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 取り込み中でない時 (始まる前) に届いた映像は、画像にしないこと
@Test func screenReadingDoesNotMakeImageBeforeCaptureStarts() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    let image = try makeScreenImage(gray: 0.2)
    var makeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1001)) {
        makeImageCallCount += 1
        return image
    }
    await waitUntilIdle(controller: controller)

    #expect(makeImageCallCount == 0)
    #expect(reader.recognitionCallCount == 0)
}

/// 取り込みを止めると、取り込み中に保存した読み取り結果が消えること
@Test func screenReadingDeletesSavedLatestReadingWhenCaptureStops() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    #expect(loadLatestReading(fileURL: latestReadingFileURL) != nil)

    controller.stop()

    #expect(controller.status == .stopped)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(!FileManager.default.fileExists(atPath: latestReadingFileURL.path))
}

/// 読み取りの途中で取り込みが止まった時は、その読み取りの結果を保存せず、診断の記録にも足さないこと
/// (止めた後に、キーボードへ出る読み取り結果を残さない)
@Test func screenReadingDoesNotSaveWhenCaptureStopsDuringReading() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    reader.onRecognize = { controller.stop() }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.status == .stopped)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(reader.translationCallCount == 0)
    #expect(controller.diagnostics?.reading == ScreenReadingDiagnostics())
}

/// 翻訳の途中で取り込みが止まった時は、その読み取りの結果を保存せず、翻訳より後の段を診断の記録に足さないこと
@Test func screenReadingDoesNotSaveWhenCaptureStopsDuringTranslation() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    reader.onTranslate = { controller.stop() }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.status == .stopped)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(!FileManager.default.fileExists(atPath: latestReadingFileURL.path))
    #expect(controller.diagnostics?.reading.recognition.successCount == 1)
    #expect(controller.diagnostics?.reading.translation == ScreenReadingStageDiagnostics())
    #expect(controller.diagnostics?.reading.replyGeneration == ScreenReadingStageDiagnostics())
    #expect(controller.diagnostics?.reading.saving == ScreenReadingStageDiagnostics())
}

/// 翻訳の途中で取り込みを止めて始め直した時は、前の取り込みの読み取りの結果を、新しい取り込みの読み取り結果として保存せず、
/// 新しい取り込みの診断の記録にも足さないこと
@Test func screenReadingDoesNotMixResultIntoRestartedCapture() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    reader.onTranslate = {
        reader.onTranslate = nil
        controller.stop()
        controller.start()
        source.onEvent?(.started)
    }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.status == .capturing)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(controller.diagnostics?.reading == ScreenReadingDiagnostics())
}

/// 翻訳の途中で利用者が取り込む対象を選び直した時 (取り込み中に、新しい対象の映像が始まったと知らされる) は、
/// 前の対象の画面の読み取りの結果を保存せず、選び直した後の画面は、前の対象と同じ画素・同じ発言でも読んで保存すること
@Test func screenReadingDiscardsResultOfPreviousTargetWhenTargetIsReselected() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    source.onEvent?(.frameReceived(Date(timeIntervalSinceReferenceDate: 1001)))
    reader.onTranslate = {
        reader.onTranslate = nil
        source.onEvent?(.started)
    }

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.status == .capturing)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
    #expect(controller.diagnostics?.reading.saving == ScreenReadingStageDiagnostics())
    #expect(controller.diagnostics?.receivedFrameCount == 1)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001.5, image: try makeScreenImage(gray: 0.2))

    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1001.5))
    #expect(controller.diagnostics?.reading.saving.successCount == 1)
}

/// 取り込みを止めて始め直した後は、前の取り込みで読んだ画面と同じ画素・同じ発言の画面でも読み直して保存すること
/// (止めた時に読み取り結果を消しているため)
@Test func screenReadingReadsSameScreenAgainAfterCaptureRestarts() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    controller.stop()
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001.5, image: try makeScreenImage(gray: 0.2))

    #expect(reader.recognitionCallCount == 2)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1001.5))
    #expect(controller.diagnostics?.reading.saving.successCount == 1)
}

/// 映像を画像にできなかった時は、文字の読み取りの失敗として、結果のコードと画素の形式つきで時刻とともに記録し、
/// 2 秒経つまでに届いた次の映像は、届いた時には画像にしないこと
@Test func screenReadingRecordsImageConversionFailureAsRecognitionFailure() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenReadingController(
        source: source, reader: reader, clock: clock, latestReadingFileURL: temporaryFileURL(), diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1002)
    let nextImage = try makeScreenImage(gray: 0.2)
    var makeImageCallCount = 0

    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1001)) {
        throw FrameImageConversionError(status: -12902, pixelFormat: 875_704_422)
    }
    source.onFrameImage?(Date(timeIntervalSinceReferenceDate: 1002.5)) {
        makeImageCallCount += 1
        return nextImage
    }

    #expect(
        controller.diagnostics?.reading.recognition
            == ScreenReadingStageDiagnostics(
                failureCount: 1,
                lastFailedAt: Date(timeIntervalSinceReferenceDate: 1002),
                lastFailureDescription: "FrameImageConversionError status=-12902 pixelFormat=875704422"
            )
    )
    #expect(makeImageCallCount == 0)
    #expect(reader.recognitionCallCount == 0)

    await waitUntilIdle(controller: controller)
    #expect(reader.waitedSeconds == [0.5])
    #expect(makeImageCallCount == 1)
}

/// 文字の読み取りが失敗した時は、読み取りの失敗をエラーの内容と時刻つきで記録し、翻訳へ進まず、何も保存しないこと
@Test func screenReadingRecordsRecognitionFailure() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.recognitionError = NSError(domain: "com.example.vision", code: 9, userInfo: [NSLocalizedDescriptionKey: "request failed"])
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source, reader: reader, clock: clock, latestReadingFileURL: latestReadingFileURL, diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1002)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(
        controller.diagnostics?.reading
            == ScreenReadingDiagnostics(
                recognition: ScreenReadingStageDiagnostics(
                    failureCount: 1,
                    lastFailedAt: Date(timeIntervalSinceReferenceDate: 1002),
                    lastFailureDescription: "com.example.vision 9: request failed"
                )
            )
    )
    #expect(reader.translationCallCount == 0)
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 文字の読み取りが失敗した画面は、次に届いた映像が同じ画素のままでも、読み直して保存すること
/// (失敗した画面を「読んだ画面」として覚えると、画面の画素が変わるまで読み直せなくなる)
@Test func screenReadingReadsSameScreenAgainAfterRecognitionFailure() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.recognitionError = NSError(domain: "com.example.vision", code: 9, userInfo: [NSLocalizedDescriptionKey: "request failed"])
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.recognitionError = nil

    await receiveFrame(source: source, controller: controller, receivedAt: 1003, image: try makeScreenImage(gray: 0.2))

    #expect(reader.recognitionCallCount == 2)
    #expect(controller.diagnostics?.reading.recognition.failureCount == 1)
    #expect(controller.diagnostics?.reading.recognition.successCount == 1)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1003))
}

/// 翻訳が失敗した時は、翻訳の失敗をエラーの内容つきで記録し、前に保存した読み取り結果を残し、
/// 同じ発言が映っている間は翻訳を繰り返さないこと
@Test func screenReadingRecordsTranslationFailureAndKeepsPreviousLatestReading() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = otherChatLines
    reader.translationError = ChatReadingError.incompleteTranslation

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))
    await receiveFrame(source: source, controller: controller, receivedAt: 1007, image: try makeScreenImage(gray: 0.5))

    #expect(controller.diagnostics?.reading.translation.failureCount == 1)
    #expect(controller.diagnostics?.reading.translation.lastFailureDescription == "ChatReadingError.incompleteTranslation")
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
    #expect(controller.diagnostics?.reading.unchangedMessagesCount == 1)
    #expect(reader.translationCallCount == 3)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.messages.map(\.originalText) == ["Are you free today?", "Yes, after lunch"])
}

/// 発言が訳せない言語 (利用者の言語で書かれている等) の時は、翻訳の失敗に数えず、訳せなかった回数に数えること
@Test func screenReadingCountsUntranslatableLanguageSeparatelyFromFailure() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.translationError = ChatReadingError.untranslatableLanguage
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.untranslatableCount == 1)
    #expect(controller.diagnostics?.reading.translation == ScreenReadingStageDiagnostics())
    #expect(loadLatestReading(fileURL: latestReadingFileURL) == nil)
}

/// 画面に発言が 1 つも無い時 (ホーム画面など) は、失敗に数えず、発言が無かった回数に数え、前に保存した読み取り結果を残すこと
@Test func screenReadingCountsScreenWithoutMessagesAndKeepsPreviousLatestReading() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = []

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(controller.diagnostics?.reading.noMessagesCount == 1)
    #expect(controller.diagnostics?.reading.recognition.successCount == 2)
    #expect(controller.diagnostics?.reading.recognition.failureCount == 0)
    #expect(controller.diagnostics?.reading.translation.failureCount == 0)
    #expect(reader.translationCallCount == 2)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.capturedAt == Date(timeIntervalSinceReferenceDate: 1001))
}

/// 選ばれているモデルが使えない時は、ほかのモデルが使えても切り替えず、返信案を空にして翻訳だけを保存し、
/// 返信案の生成の失敗として、使えなかったモデルが分かる理由と、そのモデルを記録すること。選べるモデルのそれぞれで確かめる
@Test(arguments: [
    (ReplyModel.onDevice, "返信案を作るモデル (onDevice) が使えない"),
    (ReplyModel.privateCloudCompute, "返信案を作るモデル (privateCloudCompute) が使えない"),
])
func screenReadingSavesTranslationOnlyWhenSelectedModelIsUnavailable(replyModel: ReplyModel, failureDescription: String) async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.selectedReplyModel = replyModel
    reader.availableReplyModels = Set(ReplyModel.allCases).subtracting([replyModel])
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
    #expect(latestReading.replySuggestions.isEmpty)
    #expect(reader.replyGenerationCallCount == 0)
    #expect(controller.diagnostics?.reading.replyGeneration.failureCount == 1)
    #expect(controller.diagnostics?.reading.replyGeneration.lastFailureDescription == failureDescription)
    #expect(controller.diagnostics?.reading.replyGenerationModel == replyModel)
    #expect(reader.availabilityCheckedReplyModels == [replyModel])
    #expect(controller.diagnostics?.reading.saving.successCount == 1)
}

/// 取り込んだ画面を読むたびに、その時に選ばれているモデルで使えるかを判定して返信案を作り、そのモデルを診断の記録に残すこと。
/// 取り込みの途中で選び直した後に読んだ画面は、選び直したモデルで作る
@Test func screenReadingGeneratesRepliesWithModelSelectedAtEachReading() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.selectedReplyModel = .privateCloudCompute
    let diagnosticsFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: diagnosticsFileURL
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(reader.availabilityCheckedReplyModels == [.privateCloudCompute])
    #expect(reader.replyGeneratedModels == [.privateCloudCompute])
    #expect(controller.diagnostics?.reading.replyGenerationModel == .privateCloudCompute)
    #expect(loadScreenCaptureDiagnostics(fileURL: diagnosticsFileURL)?.reading.replyGenerationModel == .privateCloudCompute)

    reader.selectedReplyModel = .onDevice
    reader.lines = otherChatLines
    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(reader.availabilityCheckedReplyModels == [.privateCloudCompute, .onDevice])
    #expect(reader.replyGeneratedModels == [.privateCloudCompute, .onDevice])
    #expect(controller.diagnostics?.reading.replyGenerationModel == .onDevice)
    #expect(controller.diagnostics?.reading.replyGeneration.successCount == 2)
}

/// 1 回の読み取りの途中 (発言の翻訳の間・返信の文の生成の間) で選び直しても、その読み取りは始めた時のモデルで、
/// 使えるかの判定・生成・診断の記録を済ませること。選び直す時点のそれぞれで確かめる
@Test(arguments: [true, false]) func screenReadingKeepsModelSelectedAtStartOfReading(reselectsDuringTranslation: Bool) async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.selectedReplyModel = .privateCloudCompute
    if reselectsDuringTranslation {
        reader.onTranslate = { reader.selectedReplyModel = .onDevice }
    } else {
        reader.onGenerateReplies = { reader.selectedReplyModel = .onDevice }
    }
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(reader.selectedReplyModel == .onDevice)
    #expect(reader.availabilityCheckedReplyModels == [.privateCloudCompute])
    #expect(reader.replyGeneratedModels == [.privateCloudCompute])
    #expect(controller.diagnostics?.reading.replyGenerationModel == .privateCloudCompute)
    #expect(controller.diagnostics?.reading.replyGeneration.successCount == 1)
}

/// 返信案の生成の段まで進まなかった読み取り (発言が無い画面) では、返信案を作るモデルを診断の記録に残さないこと
@Test func screenReadingDoesNotRecordReplyModelWhenReplyGenerationIsNotReached() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = []
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.noMessagesCount == 1)
    #expect(controller.diagnostics?.reading.replyGenerationModel == nil)
}

/// 返信案を作るモデルの項目 (replyGenerationModel) を足す前の版が保存した診断の記録を、その項目が無い記録として読めること
/// (アプリを新しくした後も、前回の取り込みの記録を開発者メニューで見られるようにする)
@Test func screenCaptureDiagnosticsLoadsRecordSavedWithoutReplyGenerationModel() throws {
    let fileURL = temporaryFileURL()
    let diagnostics = ScreenCaptureDiagnostics(
        startedAt: Date(timeIntervalSinceReferenceDate: 500),
        stoppedAt: nil,
        stopReason: nil,
        lastFrameReceivedAt: nil,
        receivedFrameCount: 3,
        reading: ScreenReadingDiagnostics(
            replyGeneration: ScreenReadingStageDiagnostics(successCount: 2, lastSucceededAt: Date(timeIntervalSinceReferenceDate: 510))
        )
    )
    try save(screenCaptureDiagnostics: diagnostics, fileURL: fileURL)
    #expect(try String(contentsOf: fileURL, encoding: .utf8).contains("replyGenerationModel") == false)

    #expect(loadScreenCaptureDiagnostics(fileURL: fileURL) == diagnostics)
}

/// 返信の文の生成が失敗した時は、翻訳だけを保存し、返信案の生成の失敗としてエラーの内容を記録すること
@Test func screenReadingSavesTranslationOnlyAndRecordsErrorWhenReplyGenerationFails() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.replyGenerationError = NSError(domain: "com.example.model", code: 4, userInfo: [NSLocalizedDescriptionKey: "model busy"])
    reader.selectedReplyModel = .privateCloudCompute
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.replySuggestions.isEmpty == true)
    #expect(loadLatestReading(fileURL: latestReadingFileURL)?.messages.count == 2)
    #expect(controller.diagnostics?.reading.replyGeneration.failureCount == 1)
    #expect(controller.diagnostics?.reading.replyGeneration.lastFailureDescription == "com.example.model 4: model busy")
    #expect(controller.diagnostics?.reading.replyGenerationModel == .privateCloudCompute)
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
}

/// 発言の翻訳は成功し、返信の文の意味を作る翻訳だけが失敗した時は、翻訳だけを保存し、
/// 翻訳の失敗ではなく返信案の生成の失敗として、その翻訳のエラーの内容を記録すること
@Test func screenReadingRecordsReplyGenerationFailureWhenReplyMeaningTranslationFails() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.translationError = ChatReadingError.incompleteTranslation
    reader.translationErrorCallNumber = 2
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.messages.map(\.translatedText) == ["訳: Are you free today?", "訳: Yes, after lunch"])
    #expect(latestReading.replySuggestions.isEmpty)
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
    #expect(controller.diagnostics?.reading.translation.failureCount == 0)
    #expect(controller.diagnostics?.reading.replyGeneration.failureCount == 1)
    #expect(controller.diagnostics?.reading.replyGeneration.lastFailureDescription == "ChatReadingError.incompleteTranslation")
}

/// 読み取りの記録 (reading) を足す前の版が保存した診断の記録を、読み取りの記録が空の記録として読めること
/// (アプリを新しくした後も、前回の取り込みの記録を開発者メニューで見られるようにする)
@Test func screenCaptureDiagnosticsLoadsRecordSavedWithoutReading() throws {
    let fileURL = temporaryFileURL()
    try save(
        screenCaptureDiagnostics: ScreenCaptureDiagnostics(
            startedAt: Date(timeIntervalSinceReferenceDate: 500),
            stoppedAt: nil,
            stopReason: nil,
            lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 620),
            receivedFrameCount: 42
        ),
        fileURL: fileURL
    )
    var savedObject = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any])
    #expect(savedObject.removeValue(forKey: "reading") != nil)
    try JSONSerialization.data(withJSONObject: savedObject).write(to: fileURL)

    #expect(
        loadScreenCaptureDiagnostics(fileURL: fileURL)
            == ScreenCaptureDiagnostics(
                startedAt: Date(timeIntervalSinceReferenceDate: 500),
                stoppedAt: nil,
                stopReason: nil,
                lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 620),
                receivedFrameCount: 42
            )
    )
}

/// 読み取りの記録を持つ診断の記録を保存して読み出すと、段ごとの回数・時刻・エラーの内容が同じまま戻ること
@Test func screenCaptureDiagnosticsRoundTripsReading() throws {
    let fileURL = temporaryFileURL()
    let diagnostics = ScreenCaptureDiagnostics(
        startedAt: Date(timeIntervalSinceReferenceDate: 500),
        stoppedAt: nil,
        stopReason: nil,
        lastFrameReceivedAt: nil,
        receivedFrameCount: 3,
        reading: ScreenReadingDiagnostics(
            translation: ScreenReadingStageDiagnostics(
                successCount: 2,
                lastSucceededAt: Date(timeIntervalSinceReferenceDate: 510),
                failureCount: 1,
                lastFailedAt: Date(timeIntervalSinceReferenceDate: 520),
                lastFailureDescription: "ChatReadingError.incompleteTranslation"
            ),
            shownLatestReadingCount: 4
        )
    )

    try save(screenCaptureDiagnostics: diagnostics, fileURL: fileURL)

    #expect(loadScreenCaptureDiagnostics(fileURL: fileURL) == diagnostics)
}

/// 返信の文が 1 つも作られなかった時 (エラーは無い) は、返信案の生成の失敗として、その旨を記録すること
@Test func screenReadingRecordsReplyGenerationFailureWhenNoReplyIsGenerated() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    reader.replyTexts = []
    reader.selectedReplyModel = .privateCloudCompute
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: temporaryFileURL(),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.replyGeneration.failureCount == 1)
    #expect(controller.diagnostics?.reading.replyGeneration.lastFailureDescription == "返信案が 1 つも作られなかった")
    #expect(controller.diagnostics?.reading.replyGenerationModel == .privateCloudCompute)
}

/// 読み取り結果を置く場所が無い時 (App Group を使えない) は、保存の失敗として記録すること
@Test func screenReadingRecordsSavingFailureWhenAppGroupIsUnavailable() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: nil,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.saving.failureCount == 1)
    #expect(controller.diagnostics?.reading.saving.lastFailureDescription == "App Group の共有コンテナを使えない")
    #expect(controller.diagnostics?.reading.translation.successCount == 1)
}

/// 読み取り結果を書き込めない時 (置く場所のディレクトリが無い) は、保存の失敗として時刻つきで記録し、成功には数えないこと
@Test func screenReadingRecordsSavingFailureWhenFileCannotBeWritten() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let clock = TestClock(now: Date(timeIntervalSinceReferenceDate: 1000))
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: clock,
        latestReadingFileURL: FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)/latest-reading.json"),
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    clock.now = Date(timeIntervalSinceReferenceDate: 1002)

    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))

    #expect(controller.diagnostics?.reading.saving.failureCount == 1)
    #expect(controller.diagnostics?.reading.saving.lastFailedAt == Date(timeIntervalSinceReferenceDate: 1002))
    #expect(controller.diagnostics?.reading.saving.lastFailureDescription?.isEmpty == false)
    #expect(controller.diagnostics?.reading.saving.successCount == 0)
}

/// 画面に、保存してある読み取り結果の訳文と返信案の意味 (Poppo のキーボードが出している文) が映っている時は、
/// 発言として読み直さず、保存してある読み取り結果を書き換えないこと
@Test func screenReadingDoesNotReadScreenShowingLatestReading() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = chatLines + screenLines(texts: ["訳: Are you free today?", "訳: Sounds good"])

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(controller.diagnostics?.reading.shownLatestReadingCount == 1)
    #expect(reader.translationCallCount == 2)
    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.capturedAt == Date(timeIntervalSinceReferenceDate: 1001))
    #expect(latestReading.messages.count == 2)
}

/// チャットに届いた発言が、保存してある訳文の 1 つと同じ文だった時 (訳文が 1 つだけ映っている画面) は、
/// キーボードの表示とはみなさず、読み直して読み取り結果を新しい内容で上書きすること
@Test func screenReadingReadsScreenWhereOnlyOneTranslatedTextAppears() async throws {
    let source = FakeScreenCaptureSource()
    let reader = FakeScreenReader()
    reader.lines = chatLines
    let latestReadingFileURL = temporaryFileURL()
    let controller = makeScreenReadingController(
        source: source,
        reader: reader,
        clock: TestClock(now: Date(timeIntervalSinceReferenceDate: 1000)),
        latestReadingFileURL: latestReadingFileURL,
        diagnosticsFileURL: nil
    )
    controller.start()
    source.onEvent?(.started)
    await receiveFrame(source: source, controller: controller, receivedAt: 1001, image: try makeScreenImage(gray: 0.2))
    reader.lines = chatLines + screenLines(texts: ["訳: Are you free today?"])

    await receiveFrame(source: source, controller: controller, receivedAt: 1004, image: try makeScreenImage(gray: 0.8))

    #expect(controller.diagnostics?.reading.shownLatestReadingCount == 0)
    let latestReading = try #require(loadLatestReading(fileURL: latestReadingFileURL))
    #expect(latestReading.capturedAt == Date(timeIntervalSinceReferenceDate: 1004))
    #expect(latestReading.messages.map(\.originalText) == ["Are you free today?", "Yes, after lunch", "訳: Are you free today?"])
}

/// 画面の行と比べる読み取り結果。原文と違う訳文の発言・原文のままの発言・訳しても変わらない語 (GitHub) を含む発言・返信案を 1 つずつ持つ。
/// Poppo が作って出す文 (原文と違う訳文と、返信案の意味) は 3 つ
private let shownLatestReading = LatestReading(
    capturedAt: Date(timeIntervalSinceReferenceDate: 1000),
    messages: [
        TranslatedMessage(originalText: "Are you free this afternoon?", translatedText: "今日の午後は空いていますか？"),
        TranslatedMessage(originalText: "了解です、あとで連絡します", translatedText: "了解です、あとで連絡します"),
        TranslatedMessage(originalText: "Please check GitHub first", translatedText: "先に GitHub を確認してください"),
    ],
    replySuggestions: [ReplySuggestion(text: "Sure, after 3 pm works", meaning: "はい、15 時以降なら大丈夫です")]
)

/// texts のそれぞれが 1 行ずつ、上から順に写った画面の行を返す
private func screenLines(texts: [String]) -> [RecognizedTextLine] {
    texts.enumerated().map { index, text in
        RecognizedTextLine(text: text, boundingBox: CGRect(x: 0.05, y: 0.6 + 0.04 * Double(index), width: 0.6, height: 0.02))
    }
}

/// 訳文の行と返信案の意味の行の 2 つが映っている画面は、読み取り結果が映っていると判定すること
@Test func showsLatestReadingIsTrueWhenTranslatedTextAndReplyMeaningAppear() {
    #expect(
        showsLatestReading(lines: screenLines(texts: ["今日の午後は空いていますか？", "はい、15 時以降なら大丈夫です"]), latestReading: shownLatestReading)
    )
}

/// 訳文が 1 つだけ映っている画面と、返信案の意味が 1 つだけ映っている画面は、読み取り結果が映っているとは判定しないこと
/// (チャットに届いた発言が、たまたま訳文の 1 つと同じ文だった時に、読み直しを止めない)
@Test func showsLatestReadingIsFalseWhenOnlyOneShownTextAppears() {
    #expect(!showsLatestReading(lines: screenLines(texts: ["今日の午後は空いていますか？"]), latestReading: shownLatestReading))
    #expect(!showsLatestReading(lines: screenLines(texts: ["はい、15 時以降なら大丈夫です"]), latestReading: shownLatestReading))
}

/// 同じ訳文の一部になっている行が 2 つ映っているだけの画面 (1 つの訳文が 2 行に折り返されている) は、映っている文は 1 つと数え、
/// 読み取り結果が映っているとは判定しないこと
@Test func showsLatestReadingCountsTwoLinesOfSameShownTextAsOne() {
    #expect(!showsLatestReading(lines: screenLines(texts: ["今日の午後は", "空いていますか？"]), latestReading: shownLatestReading))
}

/// Poppo が作って出す文が 1 つしか無い読み取り結果では、その 1 つが映っていれば、読み取り結果が映っていると判定すること
@Test func showsLatestReadingIsTrueForOnlyShownTextOfLatestReading() {
    let latestReading = LatestReading(
        capturedAt: Date(timeIntervalSinceReferenceDate: 1000),
        messages: [TranslatedMessage(originalText: "Are you free this afternoon?", translatedText: "今日の午後は空いていますか？")],
        replySuggestions: []
    )

    #expect(showsLatestReading(lines: screenLines(texts: ["今日の午後は空いていますか？"]), latestReading: latestReading))
    #expect(!showsLatestReading(lines: screenLines(texts: ["Are you free this afternoon?"]), latestReading: latestReading))
}

/// Poppo が作って出す文が 1 つも無い読み取り結果 (訳さずに原文のまま持っている発言だけ) では、その発言が映っていても、
/// 読み取り結果が映っているとは判定しないこと
@Test func showsLatestReadingIsFalseWhenLatestReadingHasNoShownText() {
    #expect(
        !showsLatestReading(
            lines: screenLines(texts: ["了解です、あとで連絡します"]),
            latestReading: LatestReading(
                capturedAt: Date(timeIntervalSinceReferenceDate: 1000),
                messages: [TranslatedMessage(originalText: "了解です、あとで連絡します", translatedText: "了解です、あとで連絡します")],
                replySuggestions: []
            )
        )
    )
}

/// 折り返されて訳文の一部だけになった行と、文字の間に空白が入って読まれた行でも、その文が映っていると数えること
@Test func showsLatestReadingCountsWrappedOrSpacedPartOfShownText() {
    #expect(showsLatestReading(lines: screenLines(texts: ["空いていますか？", "15 時以降なら"]), latestReading: shownLatestReading))
    #expect(showsLatestReading(lines: screenLines(texts: ["今日の 午後は 空いて", "はい、15 時以降なら大丈夫です"]), latestReading: shownLatestReading))
}

/// 訳文の一部と一致する行は、4 文字なら映っていると数え、3 文字なら数えないこと (短い行の偶然の一致で読み直しを止めない)
@Test func showsLatestReadingNeedsLineOfFourCharactersOrMore() {
    #expect(showsLatestReading(lines: screenLines(texts: ["今日の午", "はい、15 時以降なら大丈夫です"]), latestReading: shownLatestReading))
    #expect(!showsLatestReading(lines: screenLines(texts: ["今日の", "はい、15 時以降なら大丈夫です"]), latestReading: shownLatestReading))
}

/// 発言の原文の行は、映っている文に数えないこと (チャットの画面そのものを、キーボードの表示とみなさない)
@Test func showsLatestReadingDoesNotCountOriginalText() {
    #expect(
        !showsLatestReading(
            lines: screenLines(texts: ["Are you free this afternoon?", "Please check GitHub first", "はい、15 時以降なら大丈夫です"]),
            latestReading: shownLatestReading
        )
    )
}

/// 返信案の文 (利用者が送った後にチャットに載る文) の行は、映っている文に数えないこと
/// (送った後の画面を読み直せなくならないようにする)
@Test func showsLatestReadingDoesNotCountReplyText() {
    #expect(
        !showsLatestReading(lines: screenLines(texts: ["Sure, after 3 pm works", "今日の午後は空いていますか？"]), latestReading: shownLatestReading)
    )
}

/// 訳さずに原文のまま持っている発言 (利用者の言語の発言) の行は、映っている文に数えないこと
@Test func showsLatestReadingDoesNotCountMessageKeptInOriginalText() {
    #expect(
        !showsLatestReading(lines: screenLines(texts: ["了解です、あとで連絡します", "今日の午後は空いていますか？"]), latestReading: shownLatestReading)
    )
}

/// 訳しても変わらない語だけの行 (原文にも訳文にも入っている) は、映っている文に数えないこと
@Test func showsLatestReadingDoesNotCountLineThatIsAlsoInOriginalText() {
    #expect(!showsLatestReading(lines: screenLines(texts: ["GitHub", "今日の午後は空いていますか？"]), latestReading: shownLatestReading))
}

/// 読み取り結果のどの文とも一致しない行だけの画面と、行が 1 つも無い画面は、読み取り結果が映っているとは判定しないこと
@Test func showsLatestReadingIsFalseForUnrelatedOrNoLines() {
    #expect(!showsLatestReading(lines: screenLines(texts: ["明日の会議は中止です", "お疲れさまでした"]), latestReading: shownLatestReading))
    #expect(!showsLatestReading(lines: [], latestReading: shownLatestReading))
}

/// 同じ画素の画像からは同じ画素の並びを、違う明るさの画像からは違う画素の並びを返し、並びの長さは 90 × 195 であること
@Test func screenFingerprintIsSameForSamePixelsAndDifferentForDifferentPixels() throws {
    let fingerprint = try #require(screenFingerprint(image: try makeScreenImage(gray: 0.2)))

    #expect(fingerprint.count == 90 * 195)
    #expect(fingerprint == screenFingerprint(image: try makeScreenImage(gray: 0.2)))
    #expect(fingerprint != screenFingerprint(image: try makeScreenImage(gray: 0.8)))
}

/// 画面の一部 (下 4 分の 1) だけが変わった画像からは、違う画素の並びを返すこと
@Test func screenFingerprintDiffersWhenPartOfScreenChanges() throws {
    let context = try #require(
        CGContext(
            data: nil,
            width: 90,
            height: 195,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    )
    context.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 90, height: 195))
    context.setFillColor(CGColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 90, height: 48))

    #expect(screenFingerprint(image: try #require(context.makeImage())) != screenFingerprint(image: try makeScreenImage(gray: 0.2)))
}

/// 取り込んだ映像と同じ形 (BGRA の pixelBuffer) から、同じ幅と高さの画像を作れること
@Test func makeCGImageConvertsBGRAPixelBuffer() throws {
    var pixelBuffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 4, 6, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess)

    let image = try makeCGImage(pixelBuffer: try #require(pixelBuffer))

    #expect(image.width == 4)
    #expect(image.height == 6)
}

/// 読み取りの段のエラーを診断の記録に残す文が、このアプリのエラーではエラーの名前と値、ほかのエラーではドメイン・コード・説明になること
@Test func screenReadingFailureDescriptionNamesErrorAndValues() {
    #expect(screenReadingFailureDescription(error: ChatReadingError.incompleteTranslation) == "ChatReadingError.incompleteTranslation")
    #expect(
        screenReadingFailureDescription(error: FrameImageConversionError(status: -12902, pixelFormat: 875_704_422))
            == "FrameImageConversionError status=-12902 pixelFormat=875704422"
    )
    #expect(
        screenReadingFailureDescription(
            error: NSError(domain: "com.example.capture", code: -3824, userInfo: [NSLocalizedDescriptionKey: "missing background mode"])
        ) == "com.example.capture -3824: missing background mode"
    )
}

/// 段の記録が、成功と失敗の回数を別々に数え、最後の時刻と最後のエラーの内容を新しいもので置き換えること
@Test func screenReadingStageDiagnosticsCountsSuccessAndFailureSeparately() {
    var stage = ScreenReadingStageDiagnostics()

    stage.recordSuccess(date: Date(timeIntervalSinceReferenceDate: 1))
    stage.recordFailure(date: Date(timeIntervalSinceReferenceDate: 2), failureDescription: "first")
    stage.recordFailure(date: Date(timeIntervalSinceReferenceDate: 3), failureDescription: "second")
    stage.recordSuccess(date: Date(timeIntervalSinceReferenceDate: 4))

    #expect(
        stage
            == ScreenReadingStageDiagnostics(
                successCount: 2,
                lastSucceededAt: Date(timeIntervalSinceReferenceDate: 4),
                failureCount: 2,
                lastFailedAt: Date(timeIntervalSinceReferenceDate: 3),
                lastFailureDescription: "second"
            )
    )
}
