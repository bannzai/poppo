import SwiftUI

/// キーボードに表示する画面。立ち上げ時点の仮の表示
struct KeyboardView: View {
    /// システムが「次のキーボードへ切り替えるキー」の表示をキーボード側に求めているか
    let needsInputModeSwitchKey: Bool
    /// 切り替えるキーを押した時に呼ぶ処理。次のキーボードへ切り替える
    let onSwitchKeyboard: () -> Void

    var body: some View {
        HStack {
            if needsInputModeSwitchKey {
                Button(action: onSwitchKeyboard) {
                    Image(systemName: "globe")
                }
                .accessibilityIdentifier("keyboard_switch")
            }
            // ja: 翻訳と返信案はここに表示されます
            Text("Translations and reply suggestions will appear here")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        // 立ち上げ時点の仮の高さ。翻訳と返信案を数行並べられる広さとして置いた値で、
        // 表示する内容が決まる時 (https://github.com/bannzai/poppo/issues/4 ) に決め直す
        .frame(height: 216)
    }
}
