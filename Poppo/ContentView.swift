import SwiftUI

/// 本体アプリの最初の画面。直近のスクリーンショットを選ぶ画面を出し、選んだ 1 枚の読み取りの画面へ進む。
/// 下端に取り込みを始める入口を出し、取り込み中はどの画面へ進んでも取り込み中の表示と停止の操作を出す
struct ContentView: View {
    /// 取り込みの状態
    @Environment(ScreenCaptureController.self) private var screenCaptureController

    var body: some View {
        NavigationStack {
            RecentScreenshotsView()
                .navigationTitle(Text(verbatim: "Poppo"))
                .safeAreaInset(edge: .bottom) {
                    if screenCaptureController.status != .capturing {
                        ScreenCaptureEntryView(
                            status: screenCaptureController.status,
                            failedToDeleteLatestReading: screenCaptureController.failedToDeleteLatestReading,
                            start: { screenCaptureController.start() }
                        )
                    }
                }
                #if DEBUG
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            DebugMenuView()
                        } label: {
                            Image(systemName: "ladybug")
                        }
                        .accessibilityIdentifier("debug_menu_button")
                    }
                }
                #endif
        }
        .safeAreaInset(edge: .bottom) {
            if screenCaptureController.status == .capturing {
                ScreenCaptureCapturingBar(stop: { screenCaptureController.stop() })
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(
            ScreenCaptureController(
                makeSource: { SystemScreenCaptureSource() },
                latestReadingFileURL: nil,
                diagnosticsFileURL: nil,
                now: { Date() }
            )
        )
}
