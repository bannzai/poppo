import SwiftUI

/// 本体アプリの最初の画面。直近のスクリーンショットを選ぶ画面を出し、選んだ 1 枚の読み取りの画面へ進む
struct ContentView: View {
    var body: some View {
        NavigationStack {
            RecentScreenshotsView()
                .navigationTitle(Text(verbatim: "Poppo"))
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
    }
}

#Preview {
    ContentView()
}
