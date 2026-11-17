import SwiftUI

/// キーボードに表示する画面。本体アプリが保存した読み取り結果 (発言ごとの翻訳と返信案) を出し、返信案をタップで入力させる
struct KeyboardView: View {
    /// システムが「次のキーボードへ切り替えるキー」の表示をキーボード側に求めているか
    let needsInputModeSwitchKey: Bool
    /// 切り替えるキーを押した時に呼ぶ処理。次のキーボードへ切り替える
    let onSwitchKeyboard: () -> Void
    /// 読み取り結果を置くファイルの場所。App Group を使えない時は nil
    let latestReadingFileURL: URL?
    /// 返信案をタップした時に、入力欄へ入れる文を渡して呼ぶ
    let onInsertText: (String) -> Void

    var body: some View {
        // 1 秒ごと: キーボードを開いている間に本体アプリが読み取り結果を上書き・削除した時に、開き直さなくても追従させるため。
        // 「何分前の内容か」の表示もこの間隔で進む
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            KeyboardContentView(
                latestReading: latestReadingFileURL.flatMap { loadLatestReading(fileURL: $0) },
                now: timeline.date,
                needsInputModeSwitchKey: needsInputModeSwitchKey,
                onSwitchKeyboard: onSwitchKeyboard,
                onInsertText: onInsertText
            )
        }
        // 280: 上段 (切り替えるキーと、何分前の内容か) を除いた残りに、返信案 2 つと直前の発言の翻訳が同時に見える高さとして置いた値。
        // 立ち上げ時の 216 では返信案 1 つぶんしか残らない。実機での見え方を確かめて決め直す (documents/DIRECTION.md「決めたこと」)
        .frame(height: 280)
    }
}

/// キーボードの中身。読み取り結果がある時はその翻訳と返信案を、無い時は本体アプリで読み取りを始めるよう促す文を出す
struct KeyboardContentView: View {
    /// 表示する読み取り結果。保存されていない時は nil
    let latestReading: LatestReading?
    /// 今の時刻。「何分前の内容か」と、読み取り結果が古いかの判定に使う
    let now: Date
    /// システムが「次のキーボードへ切り替えるキー」の表示をキーボード側に求めているか
    let needsInputModeSwitchKey: Bool
    /// 切り替えるキーを押した時に呼ぶ処理
    let onSwitchKeyboard: () -> Void
    /// 返信案をタップした時に、入力欄へ入れる文を渡して呼ぶ
    let onInsertText: (String) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                if needsInputModeSwitchKey {
                    Button(action: onSwitchKeyboard) {
                        Image(systemName: "globe")
                            .frame(width: 44, height: 32)
                            .background(Color(uiColor: .systemGray3), in: .rect(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    // ja: 次のキーボード
                    .accessibilityLabel("Next keyboard")
                    .accessibilityIdentifier("keyboard_switch")
                }
                Spacer()
                if let latestReading {
                    // 古い読み取り結果は、今の画面と違う内容かもしれないと分かるように色と印を変える。
                    // capturedAt が now より後 (端末の時計を戻した時) でも「これから」と出さないよう、now で頭打ちにする
                    Label {
                        Text(min(latestReading.capturedAt, now), format: .relative(presentation: .named))
                    } icon: {
                        if isStale(capturedAt: latestReading.capturedAt, now: now) {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(isStale(capturedAt: latestReading.capturedAt, now: now) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .accessibilityIdentifier("keyboard_reading_age")
                }
            }
            if let latestReading {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(latestReading.messages.indices, id: \.self) { index in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: latestReading.messages[index].translatedText)
                                        .font(.subheadline)
                                    Text(verbatim: latestReading.messages[index].originalText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 10))
                        if latestReading.replySuggestions.isEmpty {
                            // ja: 今この端末では返信案を作れません
                            Text("Reply suggestions aren't available on this device right now")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(latestReading.replySuggestions.indices, id: \.self) { index in
                                Button {
                                    onInsertText(latestReading.replySuggestions[index].text)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: latestReading.replySuggestions[index].text)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.tint)
                                        Text(verbatim: latestReading.replySuggestions[index].meaning)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(uiColor: .systemBackground), in: .rect(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("keyboard_reply_\(index)")
                            }
                        }
                    }
                }
                // 返信案と、返信案が答える直前の発言が下にあるため、開いた時に下の端を見せる
                .defaultScrollAnchor(.bottom)
            } else {
                Spacer()
                // ja: Poppo を開いてチャットの読み取りを始めると翻訳と返信案がここに出ます
                Text("Open Poppo and start reading a chat to see translations and reply suggestions here")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("keyboard_no_reading")
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
