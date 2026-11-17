// ScreenCaptureKit は iOS Simulator の SDK に入っていない (Xcode 27.1 の iPhoneSimulator.sdk に ScreenCaptureKit.framework が無く、
// simulator 向けビルドは「Unable to resolve module dependency: 'ScreenCaptureKit'」で失敗する)。
// このファイルは実機向けの SDK でだけコンパイルし、simulator では UnavailableScreenCaptureSource を使う
#if canImport(ScreenCaptureKit)
import CoreMedia
import Foundation
import ScreenCaptureKit

/// ScreenCaptureKit を使う取り込みの実体。システムの画面で利用者に取り込む対象を選ばせ、選ばれた対象の映像を受け取る。
/// 受け取った映像は、受け取った時刻を知らせるだけで、保存も送信もしない
final class SystemScreenCaptureSource: NSObject, ScreenCaptureSource {
    /// 出来事を渡して呼ぶ処理。MainActor で呼ぶ
    var onEvent: ((ScreenCaptureEvent) -> Void)?
    /// 映像を受け取っている stream。取り込みを始めていない間と、止めた後は nil
    private var stream: SCStream?

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

    /// 映像の受け取りを止め、stream を手放す。取り込み中でない時は、システムの画面からの知らせを受けるのをやめるだけ
    func stop() {
        stream?.stopCapture(completionHandler: nil)
        releaseStream()
    }

    /// stream を手放し、システムの画面からの知らせを受けるのをやめる。以後、手放した stream の出来事は onEvent に届かない。
    /// 既に手放している時は何もしないのと同じ結果になる
    private func releaseStream() {
        stream = nil
        SCContentSharingPicker.shared.remove(self)
        SCContentSharingPicker.shared.isActive = false
    }

    /// 利用者が選んだ対象 (filter) の映像の受け取りを始める。結果は onEvent に届く。
    /// 既に映像を受け取っている時は何もしない
    private func startStream(filter: SCContentFilter) {
        guard stream == nil else {
            return
        }
        let newStream = SCStream(filter: filter, configuration: SCStreamConfiguration(), delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        } catch {
            releaseStream()
            onEvent?(.failed(screenCaptureFailureDescription(error: error)))
            return
        }
        stream = newStream
        // @Sendable: このクロージャはどのスレッドで呼ばれるか分からないため、MainActor のクロージャとして扱わせない
        newStream.startCapture { @Sendable [startedStreamID = ObjectIdentifier(newStream)] error in
            Task { @MainActor in
                guard self.stream.map(ObjectIdentifier.init) == startedStreamID else {
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
    /// stream が映像を 1 枚出すたびに、システムが呼ぶ。受け取った時刻を onEvent に知らせる。映像の中身は使わない
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }
        // 映像 (sampleBuffer) は MainActor に渡さず、受け取った時刻だけを渡す
        Task { @MainActor [receivedAt = Date(), outputStreamID = ObjectIdentifier(stream)] in
            guard self.stream.map(ObjectIdentifier.init) == outputStreamID else {
                return
            }
            self.onEvent?(.frameReceived(receivedAt))
        }
    }
}

extension SystemScreenCaptureSource: SCStreamDelegate {
    /// stream が止まった時に、システムが呼ぶ。利用者がアプリの外で止めたのか、エラーで止まったのかを onEvent に知らせる
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor [stoppedStreamID = ObjectIdentifier(stream)] in
            guard self.stream.map(ObjectIdentifier.init) == stoppedStreamID else {
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

/// error を、診断の記録に残す文 (エラーのドメイン・コード・説明) にして返す
nonisolated func screenCaptureFailureDescription(error: any Error) -> String {
    "\((error as NSError).domain) \((error as NSError).code): \(error.localizedDescription)"
}
#endif
