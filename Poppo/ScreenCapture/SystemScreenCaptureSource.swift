// ScreenCaptureKit は iOS Simulator の SDK に入っていない (Xcode 27.1 の iPhoneSimulator.sdk に ScreenCaptureKit.framework が無く、
// simulator 向けビルドは「Unable to resolve module dependency: 'ScreenCaptureKit'」で失敗する)。
// このファイルは実機向けの SDK でだけコンパイルし、simulator では UnavailableScreenCaptureSource を使う
#if canImport(ScreenCaptureKit)
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit を使う取り込みの実体。システムの画面で利用者に取り込む対象を選ばせ、選ばれた対象の映像を受け取る。
/// 受け取った映像は、受け取った時刻と、文字の読み取りに使う画像を作る処理を知らせるだけで、保存も送信もしない
final class SystemScreenCaptureSource: NSObject, ScreenCaptureSource {
    /// 出来事を渡して呼ぶ処理。MainActor で呼ぶ
    var onEvent: ((ScreenCaptureEvent) -> Void)?
    /// 画面の絵が入った映像を 1 枚受け取るたびに、受け取った時刻と、その映像を画像にする処理を渡して呼ぶ処理。MainActor で呼ぶ
    var onFrameImage: ((_ receivedAt: Date, _ makeImage: @escaping () throws -> CGImage) -> Void)?
    /// 映像を受け取っている stream。取り込みを始めていない間と、止めた後は nil
    private var stream: SCStream?
    /// 本体アプリの操作 (止める操作・対象の選び直し) で stream を止めている途中か。
    /// 途中の間は、止まったかどうかを stopCapture の結果で決めるため、システムからの「止まった」知らせを受けない
    private var isStoppingStream = false
    /// 対象の選び直しで前の stream が止まるのを待っている間の、利用者が最後に選んだ対象。待っていない時は nil。
    /// 待っている間にもう一度選び直された時は、後から選んだ対象で置き換える
    private var filterAwaitingReplacement: SCContentFilter?

    /// 取り込む対象を選ぶシステムの画面を出す。利用者が対象を選ぶと映像の受け取りを始める。
    /// 何度呼んでも、システムの画面からの知らせを受ける登録は 1 つだけになる
    func start() {
        var configuration = SCContentSharingPickerConfiguration()
        // マイクの音は使わないため、システムの画面にマイクの切り替えを出さない
        configuration.showsMicrophoneControl = false
        SCContentSharingPicker.shared.defaultConfiguration = configuration
        // 何度呼んでも登録が 1 つになるよう、外してから足す
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.add(self)
        SCContentSharingPicker.shared.isActive = true
        SCContentSharingPicker.shared.present()
    }

    /// 映像の受け取りを止める。止まったら stream を手放して stoppedByApp を、止められなかったら stream を持ったまま stopFailed を onEvent に知らせる
    /// (止められなかった stream は映像を受け取り続けているかもしれないため、手放さずにもう一度止められるようにする)。
    /// 取り込み中でない時と、止めている途中の時は、システムの画面からの知らせを受けるのをやめるだけ
    func stop() {
        // 止める操作の後に届いた対象の選択で取り込みを始め直さないよう、先にシステムの画面からの知らせを受けるのをやめる
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
        guard let stream, !isStoppingStream else {
            return
        }
        isStoppingStream = true
        stopCapture(stream: stream) { failureDescription in
            self.isStoppingStream = false
            if let failureDescription {
                self.onEvent?(.stopFailed(failureDescription))
            } else {
                self.releaseStream()
                self.onEvent?(.stoppedByApp)
            }
        }
    }

    /// stream の映像の受け取りを止め、結果を MainActor で completion に渡す。
    /// 止まった時 (既に止まっていた時を含む) は nil、止められなかった時はエラーを診断の記録に残す文を渡す
    private func stopCapture(stream: SCStream, completion: @escaping @MainActor (String?) -> Void) {
        // @Sendable: このクロージャはどのスレッドで呼ばれるか分からないため、MainActor のクロージャとして扱わせない
        stream.stopCapture { @Sendable error in
            Task { @MainActor in
                completion(error.flatMap { isAlreadyStopped(error: $0) ? nil : screenCaptureFailureDescription(error: $0) })
            }
        }
    }

    /// stream を手放し、システムの画面からの知らせを受けるのをやめる。以後、手放した stream の出来事は onEvent に届かない。
    /// 既に手放している時は何もしないのと同じ結果になる
    private func releaseStream() {
        stream = nil
        filterAwaitingReplacement = nil
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }

    /// 利用者が選んだ対象 (filter) の映像の受け取りを始める。結果は onEvent に届く。
    /// 既に映像を受け取っている時 (取り込み中に利用者が対象を選び直した時) は、前の対象の stream が止まってから、選び直した対象で始め直す。
    /// 前の対象の stream を止められなかった時は、始め直さずに stopFailed を知らせる (前の対象の映像を受け取ったままになる)。
    /// 前の対象の stream が止まるのを待っている間にもう一度呼ばれた時は、始め直す対象を後から選んだ対象に置き換える
    private func startStream(filter: SCContentFilter) {
        guard let replacedStream = stream else {
            beginStream(filter: filter)
            return
        }
        filterAwaitingReplacement = filter
        guard !isStoppingStream else {
            return
        }
        // iOS の SCStream は対象を差し替えられない (updateContentFilter は iOS で使えない) ため、stream を作り直す。
        // Apple のサンプルと同じ扱い: 「When the picker returns a filter, the sample tears down any prior stream and builds a fresh SCStream」
        // ( https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios )
        isStoppingStream = true
        stopCapture(stream: replacedStream) { failureDescription in
            self.isStoppingStream = false
            if let failureDescription {
                self.filterAwaitingReplacement = nil
                self.onEvent?(.stopFailed(failureDescription))
            } else if SCContentSharingPicker.shared.isActive, let filterAwaitingReplacement = self.filterAwaitingReplacement {
                self.stream = nil
                self.filterAwaitingReplacement = nil
                self.beginStream(filter: filterAwaitingReplacement)
            } else {
                // 前の対象の stream を止めている途中に止める操作 (stop()) があった。選び直した対象では始めない
                self.releaseStream()
                self.onEvent?(.stoppedByApp)
            }
        }
    }

    /// 対象 (filter) の stream を新しく作り、映像の受け取りを始める。結果は onEvent に届く。
    /// stream を持っていない時に呼ぶ
    private func beginStream(filter: SCContentFilter) {
        let newStream = SCStream(filter: filter, configuration: SCStreamConfiguration(), delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        } catch {
            releaseStream()
            onEvent?(.failed(screenCaptureFailureDescription(error: error)))
            return
        }
        stream = newStream
        // nonisolated(unsafe): SCStream は Sendable でないが、下のクロージャの中では MainActor でだけ使う
        nonisolated(unsafe) let startingStream = newStream
        // @Sendable: このクロージャはどのスレッドで呼ばれるか分からないため、MainActor のクロージャとして扱わせない
        newStream.startCapture { @Sendable error in
            Task { @MainActor in
                guard self.stream === startingStream else {
                    // 始まるのを待っている間に手放された stream (対象の選び直しで、まだ始まっていない stream を「既に止まっている」として手放した時)。
                    // 手放した後に始まっていたら止める。持ち主がいないまま画面を取り込み続けさせない。
                    // 止められなかった時は、取り込みが続いているかもしれないことを stopFailed で知らせる
                    if error == nil {
                        self.stopCapture(stream: startingStream) { failureDescription in
                            if let failureDescription {
                                self.onEvent?(.stopFailed(failureDescription))
                            }
                        }
                    }
                    return
                }
                if let error {
                    self.releaseStream()
                    self.onEvent?(.failed(screenCaptureFailureDescription(error: error)))
                } else {
                    self.onEvent?(.started)
                }
            }
        }
    }
}

extension SystemScreenCaptureSource: SCContentSharingPickerObserver {
    /// 利用者が対象を選ばずにシステムの画面を閉じた時に、システムが呼ぶ。そのことを onEvent に知らせる
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            // 取り込み中に対象を選び直す画面を閉じただけの時は、受け取っている映像を止めない
            if self.stream == nil {
                self.releaseStream()
            }
            self.onEvent?(.selectionCancelled)
        }
    }

    /// 利用者がシステムの画面で取り込む対象 (filter) を選んだ時に、システムが呼ぶ。その対象の映像の受け取りを始める
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        // nonisolated(unsafe): SCContentFilter は Sendable でないが、この関数は filter を MainActor に渡した後は触らないため、同時に使われない
        nonisolated(unsafe) let selectedFilter = filter
        Task { @MainActor in
            // 止める操作 (stop() が isActive を false にする) の後に届いた選択では、取り込みを始めない。
            // 止めた後に取り込みが始まり直ると、利用者が止めたつもりの画面を読み続ける。
            // 対象の選び直しで前の stream を止めている途中 (isActive は true のまま) に届いた選択は、startStream が受けて、始め直す対象にする
            guard SCContentSharingPicker.shared.isActive else {
                return
            }
            self.startStream(filter: selectedFilter)
        }
    }

    /// 取り込む対象を選ぶシステムの画面を出せなかった時に、システムが呼ぶ。エラーを onEvent に知らせる
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in
            self.releaseStream()
            self.onEvent?(.failed(screenCaptureFailureDescription(error: error)))
        }
    }
}

extension SystemScreenCaptureSource: SCStreamOutput {
    /// stream が映像を 1 枚出すたびに、システムが呼ぶ。受け取った時刻を onEvent に知らせ、
    /// 映像に画面の絵が入っている時は、その絵を画像にする処理を onFrameImage に知らせる。
    /// 映像のうち、この呼び出しの外へ持ち出すのは画面の絵 (pixelBuffer) だけで、onFrameImage の受け手が持つ間だけ手放されない
    /// (受け手の ScreenCaptureController は、見送った映像の最後の 1 枚だけを持つ)
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }
        // addStreamOutput の sampleHandlerQueue に .main を渡しているため、この関数は main queue (MainActor) で呼ばれる。
        // nonisolated(unsafe): 画面の絵は、MainActor で動く下のクロージャと、その中で作る MainActor のクロージャからだけ使うため、同時に使われない
        nonisolated(unsafe) let framePixelBuffer = sampleBuffer.imageBuffer
        let outputStreamID = ObjectIdentifier(stream)
        MainActor.assumeIsolated {
            guard self.stream.map(ObjectIdentifier.init) == outputStreamID else {
                return
            }
            let receivedAt = Date()
            self.onEvent?(.frameReceived(receivedAt))
            guard let framePixelBuffer else {
                return
            }
            self.onFrameImage?(receivedAt) {
                try makeCGImage(pixelBuffer: framePixelBuffer)
            }
        }
    }
}

extension SystemScreenCaptureSource: SCStreamDelegate {
    /// stream が止まった時に、システムが呼ぶ。利用者がアプリの外で止めたのか、エラーで止まったのかを onEvent に知らせる
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [stoppedStreamID = ObjectIdentifier(stream)] in
            // 本体アプリの操作で止めている途中は、止まったかどうかを stopCapture の結果で決める
            guard self.stream.map(ObjectIdentifier.init) == stoppedStreamID, !self.isStoppingStream else {
                return
            }
            self.releaseStream()
            self.onEvent?(
                isUserStopped(error: error) ? .stoppedByUser : .failed(screenCaptureFailureDescription(error: error))
            )
        }
    }
}

/// error が「利用者がこのアプリの外 (システムの操作) で取り込みを止めた」ことを表すか (SCStreamError.Code.userStopped)
nonisolated func isUserStopped(error: any Error) -> Bool {
    (error as? SCStreamError)?.code == .userStopped
}

/// error が「止めようとした stream は、既に映像を受け取っていなかった」ことを表すか (SCStreamError.Code.attemptToStopStreamState)。
/// 止める操作にとっては、止まっているのと同じ結果
nonisolated func isAlreadyStopped(error: any Error) -> Bool {
    (error as? SCStreamError)?.code == .attemptToStopStreamState
}
#endif
