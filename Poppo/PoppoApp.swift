import SwiftUI

/// 本体アプリの入口。ホーム画面から開いた時の最初の画面を出す
@main
struct PoppoApp: App {
    /// 取り込みの状態。どの画面へ進んでも取り込み中の表示と停止の操作を出せるよう、アプリの入口で 1 つだけ持つ
    @State private var screenCaptureController = ScreenCaptureController(
        makeSource: makeScreenCaptureSource,
        latestReadingFileURL: latestReadingFileURL(),
        diagnosticsFileURL: screenCaptureDiagnosticsFileURL(),
        now: { Date() }
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(screenCaptureController)
        }
    }
}

/// 診断の記録を置くファイルの場所を返す。診断の記録は DEBUG ビルドでだけ保存するため、それ以外のビルドでは nil を返す
func screenCaptureDiagnosticsFileURL() -> URL? {
    #if DEBUG
    return URL.applicationSupportDirectory.appending(path: "screen-capture-diagnostics.json")
    #else
    return nil
    #endif
}
