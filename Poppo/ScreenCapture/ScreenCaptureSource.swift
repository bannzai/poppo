import Foundation

/// 取り込みの実体が知らせる出来事
enum ScreenCaptureEvent {
    /// 利用者がシステムの画面で取り込む対象を選び、映像の受け取りが始まった
    case started
    /// 映像を 1 枚受け取った。値は受け取った時刻
    case frameReceived(Date)
    /// 利用者が取り込む対象を選ばずにシステムの画面を閉じた
    case selectionCancelled
    /// 利用者が、このアプリの外 (システムの操作) で取り込みを止めた
    case stoppedByUser
    /// エラーで取り込みを始められなかった、または止まった。値はエラーの種類 (ドメインとコード) と説明
    case failed(String)
}

/// 取り込みの実体。ScreenCaptureKit を使う本物 (SystemScreenCaptureSource) と、テストで使う偽物を差し替えるための境界
protocol ScreenCaptureSource: AnyObject {
    /// 出来事を渡して呼ぶ処理。start() を呼ぶ前に設定する
    var onEvent: ((ScreenCaptureEvent) -> Void)? { get set }

    /// 利用者に取り込む対象を選ばせ、選ばれたら映像の受け取りを始める。結果は onEvent に届く。
    /// 取り込み中でない時は、何度呼んでも対象を選ぶ画面を出し直すだけ
    func start()

    /// 映像の受け取りを止める。呼んだ後は onEvent に出来事が届かない。取り込み中でない時は何もしない
    func stop()
}
