import CoreGraphics
import Foundation

/// 取り込みの実体が知らせる出来事
enum ScreenCaptureEvent: Equatable {
    /// 利用者がシステムの画面で取り込む対象を選び、映像の受け取りが始まった
    case started
    /// 映像を 1 枚受け取った。値は受け取った時刻
    case frameReceived(Date)
    /// 利用者が取り込む対象を選ばずにシステムの画面を閉じた
    case selectionCancelled
    /// 利用者が、このアプリの外 (システムの操作) で取り込みを止めた
    case stoppedByUser
    /// 本体アプリの止める操作 (stop()) で、映像の受け取りが止まった
    case stoppedByApp
    /// 本体アプリの止める操作 (stop()) が失敗した。映像の受け取りが続いているかもしれない。値はエラーの種類 (ドメインとコード) と説明
    case stopFailed(String)
    /// エラーで取り込みを始められなかった、または止まった。値はエラーの種類 (ドメインとコード) と説明
    case failed(String)
}

/// 取り込みの実体。ScreenCaptureKit を使う本物 (SystemScreenCaptureSource) と、テストで使う偽物を差し替えるための境界
protocol ScreenCaptureSource: AnyObject {
    /// 出来事を渡して呼ぶ処理。start() を呼ぶ前に設定する
    var onEvent: ((ScreenCaptureEvent) -> Void)? { get set }

    /// 映像を 1 枚受け取るたびに、frameReceived の出来事の後に呼ぶ処理。start() を呼ぶ前に設定する。
    /// receivedAt は受け取った時刻。makeImage は、その映像を画像にして返す処理で、呼ばれた時にだけ画像を作る
    /// (映像は 1 秒に何十枚も届くため、読まない映像は画像にしない)。映像に画面の絵が入っていない時は nil を返し、
    /// 画像にできない時はエラーを投げる。makeImage は、この処理が呼ばれている間だけ使える
    var onFrameImage: ((_ receivedAt: Date, _ makeImage: () throws -> CGImage?) -> Void)? { get set }

    /// 利用者に取り込む対象を選ばせ、選ばれたら映像の受け取りを始める。結果は onEvent に届く。
    /// 取り込み中でない時は、何度呼んでも対象を選ぶ画面を出し直すだけ
    func start()

    /// 映像の受け取りを止める。結果は onEvent に届く (止まれば stoppedByApp、止められなければ stopFailed)。
    /// 取り込み中でない時は何も知らせない
    func stop()
}

/// error を、診断の記録に残す文 (エラーのドメイン・コード・説明) にして返す
nonisolated func screenCaptureFailureDescription(error: any Error) -> String {
    "\((error as NSError).domain) \((error as NSError).code): \(error.localizedDescription)"
}

/// 本体アプリが使う取り込みの実体を作って返す。
/// ScreenCaptureKit がある環境 (実機) では SystemScreenCaptureSource、無い環境 (iOS Simulator) では UnavailableScreenCaptureSource
func makeScreenCaptureSource() -> any ScreenCaptureSource {
    #if canImport(ScreenCaptureKit)
    return SystemScreenCaptureSource()
    #else
    return UnavailableScreenCaptureSource()
    #endif
}

#if !canImport(ScreenCaptureKit)
/// ScreenCaptureKit が無い環境 (iOS Simulator) で使う取り込みの実体。画面は取り込まず、始める操作にエラーを返す
final class UnavailableScreenCaptureSource: ScreenCaptureSource {
    /// 出来事を渡して呼ぶ処理
    var onEvent: ((ScreenCaptureEvent) -> Void)?
    /// 映像を受け取った時に呼ぶ処理。この実体は映像を受け取らないため、呼ばない
    var onFrameImage: ((_ receivedAt: Date, _ makeImage: () throws -> CGImage?) -> Void)?

    /// 取り込めないことを、エラーとして onEvent に知らせる。何度呼んでも同じ結果になる
    func start() {
        onEvent?(.failed("ScreenCaptureKit is not available in this environment (iOS Simulator)"))
    }

    /// 取り込みを始められないため、何もしない
    func stop() {}
}
#endif
