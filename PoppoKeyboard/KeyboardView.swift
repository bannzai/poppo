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
        // 340: 開いた時に、返信案 3 つと直前の発言の翻訳が同時に見える高さとして置いた値。
        // simulator (iPhone 17) で見本の読み取り結果を出して測った: 返信案 3 つ (うち 1 つは 2 行) が約 200pt を使い、
        // 280 では直前の発言が 30pt ほどしか見えなかった。実機での見え方を確かめて決め直す (documents/DIRECTION.md「決めたこと」)
        .frame(height: 340)
        .poppoThemed()
        // 地は角を丸めた板にして、左右を少し空ける。システムが敷くキーボードの地は上の角が丸く、
        // 四角い地を端まで敷くと角からはみ出して帯に見えた (simulator の画面で確かめた)。
        // 24: 中のカードの角 (poppoCardCornerRadius) に、カードまでの余白のぶんを足して、内と外の丸みをそろえる
        .background(.poppoBackground, in: .rect(cornerRadius: 24))
        .padding(.horizontal, 4)
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
                            .background(.poppoSurface, in: .rect(cornerRadius: poppoSmallCornerRadius))
                    }
                    .buttonStyle(.plain)
                    // ja: 次のキーボード
                    .accessibilityLabel("Next keyboard")
                    .accessibilityIdentifier("keyboard_switch")
                }
                Spacer()
                if let latestReading {
                    // 古い読み取り結果は、今の画面と違う内容かもしれないと分かるように色と印を変える
                    Label {
                        Text(capturedAtNotAfterNow(capturedAt: latestReading.capturedAt, now: now), format: .relative(presentation: .named))
                    } icon: {
                        if isStale(capturedAt: latestReading.capturedAt, now: now) {
                            Image(systemName: "exclamationmark.triangle")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(isStale(capturedAt: latestReading.capturedAt, now: now) ? Color.poppoStale : Color.poppoSecondaryText)
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
                                        .foregroundStyle(.poppoSecondaryText)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .poppoCard()
                        if latestReading.replySuggestions.isEmpty {
                            // ja: 今この端末では返信案を作れません
                            Text("Reply suggestions aren't available on this device right now")
                                .font(.caption)
                                .foregroundStyle(.poppoSecondaryText)
                        } else {
                            ForEach(latestReading.replySuggestions.indices, id: \.self) { index in
                                Button {
                                    onInsertText(latestReading.replySuggestions[index].text)
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(verbatim: latestReading.replySuggestions[index].text)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.poppoAccent)
                                        Text(verbatim: latestReading.replySuggestions[index].meaning)
                                            .font(.caption)
                                            .foregroundStyle(.poppoSecondaryText)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .poppoCard()
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("keyboard_reply_\(index)")
                            }
                        }
                    }
                }
                // 返信案と、返信案が答える直前の発言が下にあるため、開いた時に下の端を見せる
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                // 中身が高さより短い時 (返信案が無い時など) は上に寄せる。役割を分けずに下の端を指定すると、短い中身も下に寄り、
                // 上に大きな空きができる (simulator で、返信案なしの見本が下に寄るのを確かめた)
                .defaultScrollAnchor(.top, for: .alignment)
                // スクロールの端のぼかしを出さない。上の端にかかった発言の翻訳がぼけて読めなくなるため
                // (simulator で、上の端の 1 行がぼけるのを確かめた)
                .scrollEdgeEffectHidden()
            } else {
                Spacer()
                // ja: 「Poppo」を開いてチャットの読み取りを始めると翻訳と返信案がここに出ます
                Text("Open '\(Text("Poppo"))' and start reading a chat to see translations and reply suggestions here")
                    .font(.footnote)
                    .foregroundStyle(.poppoSecondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("keyboard_no_reading")
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
