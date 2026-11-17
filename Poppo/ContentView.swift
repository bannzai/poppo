import SwiftUI

/// 立ち上げ時点の仮の最初の画面。画面の取り込みと翻訳の実装が入るまで、アプリが起動することだけを示す
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text(verbatim: "Poppo")
                .font(.largeTitle.bold())
            // ja: チャットの翻訳と返信案をキーボードに届けます
            Text("Translations and reply suggestions for your chats right on your keyboard")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
