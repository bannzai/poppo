import SwiftUI

/// 本体アプリの最初の画面。直近のスクリーンショットを選ぶ画面を出し、選んだ 1 枚の読み取りの画面へ進む。
/// 下端に取り込みを始める入口を出し、取り込み中はどの画面へ進んでも取り込み中の表示と停止の操作を出す
struct ContentView: View {
    /// 取り込みの状態
    @Environment(ScreenCaptureController.self) private var screenCaptureController
    /// 同意の画面を開いているか。入口を押した時に true にし、取り込みが始まった時に false にして閉じる
    @State private var isScreenCaptureConsentPresented = false

    var body: some View {
        NavigationStack {
            RecentScreenshotsView()
                .poppoScreenBackground()
                .navigationTitle(Text(verbatim: "Poppo"))
                .safeAreaInset(edge: .bottom) {
                    if screenCaptureController.status != .capturing {
                        ScreenCaptureEntryView(
                            status: screenCaptureController.status,
                            failedToDeleteLatestReading: screenCaptureController.failedToDeleteLatestReading,
                            openConsent: { isScreenCaptureConsentPresented = true }
                        )
                    }
                }
                // 同意の画面を開くかどうかを、入口 (取り込み中は画面から消える) ではなく、常に画面にあるこの view が持つ。
                // 入口の中のリンクで開くと、取り込みが始まって入口が消えた時に、開いた画面へ状態が届くかが入口の有無に左右される
                .navigationDestination(isPresented: $isScreenCaptureConsentPresented) {
                    ScreenCaptureConsentView(status: screenCaptureController.status, start: { screenCaptureController.start() })
                }
                .onChange(of: screenCaptureController.status) {
                    if screenCaptureController.status == .capturing {
                        isScreenCaptureConsentPresented = false
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
                ScreenCaptureCapturingBar(
                    failedToStop: screenCaptureController.stopFailureDescription != nil,
                    stop: { screenCaptureController.stop() }
                )
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(makeOnDeviceScreenCaptureController(latestReadingFileURL: nil, diagnosticsFileURL: nil))
}
