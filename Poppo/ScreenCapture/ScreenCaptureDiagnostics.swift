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

/// 取り込みの診断の記録。直近の 1 回の取り込みについて、いつ始まり、いつ・なぜ止まり、映像をいくつ受け取ったかを残す。
/// 実機で「他のアプリへ切り替えた後も取り込みが続くか」を確かめるために使う。映像そのものは含まない
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
