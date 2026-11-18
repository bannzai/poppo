import SwiftUI

/// 読み取りの結果 (発言ごとの翻訳と、返信案) を出す画面。返信案はコピーできる
struct ChatReadingResultView: View {
    /// 画面の上から下の順の発言と、その翻訳
    let messages: [TranslatedMessage]
    /// 返信案。作れなかった時は空
    let replySuggestions: [ReplySuggestion]
    /// 直前にコピーした返信案の、replySuggestions の中の位置。コピーするまでは nil
    @State private var copiedReplySuggestionIndex: Int?

    var body: some View {
        List {
            Section {
                ForEach(messages.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: messages[index].translatedText)
                        Text(verbatim: messages[index].originalText)
                            .font(.footnote)
                            .foregroundStyle(.poppoSecondaryText)
                    }
                }
                .listRowBackground(Color.poppoSurface)
            } header: {
                // ja: 翻訳
                Text("Translation")
            }
            Section {
                if replySuggestions.isEmpty {
                    // ja: 今この端末では返信案を作れません
                    Text("Reply suggestions aren't available on this device right now")
                        .foregroundStyle(.poppoSecondaryText)
                        .listRowBackground(Color.poppoSurface)
                } else {
                    ForEach(replySuggestions.indices, id: \.self) { index in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: replySuggestions[index].text)
                                Text(verbatim: replySuggestions[index].meaning)
                                    .font(.footnote)
                                    .foregroundStyle(.poppoSecondaryText)
                            }
                            Spacer()
                            Button {
                                copy(replySuggestion: replySuggestions[index], pasteboard: .general)
                                copiedReplySuggestionIndex = index
                            } label: {
                                if copiedReplySuggestionIndex == index {
                                    // ja: コピーしました
                                    Label("Copied", systemImage: "checkmark")
                                } else {
                                    // ja: コピー
                                    Label("Copy", systemImage: "doc.on.doc")
                                }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("reply_copy_button_\(index)")
                        }
                    }
                    .listRowBackground(Color.poppoSurface)
                }
            } header: {
                // ja: 返信案
                Text("Reply suggestions")
            }
        }
        .poppoScreenBackground()
    }
}
