#if DEBUG
import SwiftUI

/// 開発者メニュー。simulator では動かない処理 (翻訳・返信案の生成・言語のダウンロード・画面の取り込み) を通さずに、その先の画面を確かめるための入口。
/// DEBUG ビルドにだけ入る。書き換えるデータは、キーボードに渡す読み取り結果 (見本の保存と削除) だけ
struct DebugMenuView: View {
    /// 取り込みの状態。診断の記録を出すのに使う
    @Environment(ScreenCaptureController.self) private var screenCaptureController
    /// 今保存してある読み取り結果。保存していない時は nil。この画面の操作の後と、画面を開いた時に読み直す
    @State private var savedLatestReading: LatestReading?
    /// 直前の読み取り結果の保存・削除が失敗した時のエラーの説明。成功した時と、まだ操作していない時は nil
    @State private var latestReadingOperationError: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ChatReadingResultView(messages: debugSampleMessages, replySuggestions: debugSampleReplySuggestions)
                } label: {
                    Text(verbatim: "見本の読み取り結果を開く")
                }
                .accessibilityIdentifier("debug_open_sample_result")
                NavigationLink {
                    ChatReadingResultView(messages: debugSampleMessages, replySuggestions: [])
                } label: {
                    Text(verbatim: "見本の読み取り結果を開く (返信案なし)")
                }
                .accessibilityIdentifier("debug_open_sample_result_without_replies")
                NavigationLink {
                    ChatReadingPhaseView(
                        phase: .needsLanguageDownload(
                            source: Locale.Language(identifier: "en"),
                            target: Locale.Language(identifier: "ja")
                        ),
                        downloadLanguage: { _, _ in },
                        retry: {}
                    )
                } label: {
                    Text(verbatim: "言語のダウンロードを促す画面を開く")
                }
                .accessibilityIdentifier("debug_open_language_download")
            } header: {
                Text(verbatim: "スクリーンショットからの読み取り")
            }
            Section {
                Button {
                    saveSampleLatestReading(capturedAt: Date(), replySuggestions: debugSampleReplySuggestions)
                } label: {
                    Text(verbatim: "見本の読み取り結果を保存 (今読んだ)")
                }
                .accessibilityIdentifier("debug_save_sample_reading")
                Button {
                    // 10 分前: 古い読み取り結果の表示 (5 分以上前) を確かめるため
                    saveSampleLatestReading(capturedAt: Date().addingTimeInterval(-600), replySuggestions: debugSampleReplySuggestions)
                } label: {
                    Text(verbatim: "見本の読み取り結果を保存 (10 分前に読んだ)")
                }
                .accessibilityIdentifier("debug_save_stale_sample_reading")
                Button {
                    saveSampleLatestReading(capturedAt: Date(), replySuggestions: [])
                } label: {
                    Text(verbatim: "見本の読み取り結果を保存 (返信案なし)")
                }
                .accessibilityIdentifier("debug_save_sample_reading_without_replies")
                Button(role: .destructive) {
                    deleteSavedLatestReading()
                } label: {
                    Text(verbatim: "読み取り結果を削除")
                }
                .accessibilityIdentifier("debug_delete_reading")
                LabeledContent {
                    Text(verbatim: savedLatestReading.map { "あり (\($0.capturedAt.formatted(date: .omitted, time: .standard)) に読んだ)" } ?? "なし")
                } label: {
                    Text(verbatim: "保存してある読み取り結果")
                }
                .accessibilityIdentifier("debug_reading_state")
                if let latestReadingOperationError {
                    Text(verbatim: latestReadingOperationError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("debug_reading_error")
                }
            } header: {
                Text(verbatim: "キーボードに渡す読み取り結果")
            } footer: {
                Text(verbatim: "保存した後に、入力欄でキーボードを Poppo に切り替えると表示を確かめられる。取り込みが止まった時と、アプリを終了して開き直した時に、保存した見本も削除される")
            }
            Section {
                NavigationLink {
                    ScreenCaptureConsentView(status: .notStarted, start: {})
                } label: {
                    Text(verbatim: "同意の画面を開く")
                }
                .accessibilityIdentifier("debug_open_capture_consent")
                NavigationLink {
                    ScreenCaptureConsentView(status: .failed, start: {})
                } label: {
                    Text(verbatim: "同意の画面を開く (エラーで止まった後)")
                }
                .accessibilityIdentifier("debug_open_capture_consent_failed")
                NavigationLink {
                    Color.clear
                        .safeAreaInset(edge: .bottom) {
                            ScreenCaptureCapturingBar(stop: {})
                        }
                } label: {
                    Text(verbatim: "取り込み中の表示を開く")
                }
                .accessibilityIdentifier("debug_open_capture_capturing")
            } header: {
                Text(verbatim: "画面の取り込みの画面")
            }
            Section {
                if let diagnostics = screenCaptureController.diagnostics {
                    LabeledContent {
                        Text(verbatim: debugDiagnosticsText(date: diagnostics.startedAt))
                    } label: {
                        Text(verbatim: "始めた時刻")
                    }
                    .accessibilityIdentifier("debug_capture_started_at")
                    LabeledContent {
                        Text(verbatim: debugDiagnosticsText(date: diagnostics.stoppedAt))
                    } label: {
                        Text(verbatim: "止めた時刻")
                    }
                    .accessibilityIdentifier("debug_capture_stopped_at")
                    LabeledContent {
                        Text(verbatim: debugDiagnosticsText(stopReason: diagnostics.stopReason))
                    } label: {
                        Text(verbatim: "止まった理由")
                    }
                    .accessibilityIdentifier("debug_capture_stop_reason")
                    LabeledContent {
                        Text(verbatim: debugDiagnosticsText(date: diagnostics.lastFrameReceivedAt))
                    } label: {
                        Text(verbatim: "最後に映像を受け取った時刻")
                    }
                    .accessibilityIdentifier("debug_capture_last_frame_at")
                    LabeledContent {
                        Text(verbatim: String(diagnostics.receivedFrameCount))
                    } label: {
                        Text(verbatim: "受け取った映像の数")
                    }
                    .accessibilityIdentifier("debug_capture_frame_count")
                } else {
                    Text(verbatim: "記録なし (まだ取り込みを始めていない)")
                        .accessibilityIdentifier("debug_capture_no_diagnostics")
                }
            } header: {
                Text(verbatim: "画面の取り込みの診断の記録")
            } footer: {
                Text(verbatim: "直近の 1 回の取り込みの記録。始めた時刻があり、止めた時刻が「なし」のまま取り込み中の表示が出ていない時は、止まる前にアプリが終了している")
            }
        }
        .navigationTitle(Text(verbatim: "開発者メニュー"))
        .onAppear {
            reloadSavedLatestReading()
        }
    }

    /// 見本の読み取り結果を、キーボードが読む場所に保存する。capturedAt は読んだ時刻、replySuggestions は返信案。
    /// 何度実行しても、最後に保存した 1 つだけが残る
    private func saveSampleLatestReading(capturedAt: Date, replySuggestions: [ReplySuggestion]) {
        guard let fileURL = latestReadingFileURL() else {
            latestReadingOperationError = debugAppGroupUnavailableMessage
            return
        }
        do {
            try save(
                latestReading: LatestReading(capturedAt: capturedAt, messages: debugSampleMessages, replySuggestions: replySuggestions),
                fileURL: fileURL
            )
            latestReadingOperationError = nil
        } catch {
            latestReadingOperationError = error.localizedDescription
        }
        reloadSavedLatestReading()
    }

    /// 保存してある読み取り結果を削除する。保存していない時に実行しても何も起きない
    private func deleteSavedLatestReading() {
        guard let fileURL = latestReadingFileURL() else {
            latestReadingOperationError = debugAppGroupUnavailableMessage
            return
        }
        do {
            try deleteLatestReading(fileURL: fileURL)
            latestReadingOperationError = nil
        } catch {
            latestReadingOperationError = error.localizedDescription
        }
        reloadSavedLatestReading()
    }

    /// 保存してある読み取り結果を読み直して savedLatestReading に入れる
    private func reloadSavedLatestReading() {
        savedLatestReading = latestReadingFileURL().flatMap { loadLatestReading(fileURL: $0) }
    }
}

/// 診断の記録の時刻を、開発者メニューに出す文にして返す。date が nil の時は「なし」を返す
private func debugDiagnosticsText(date: Date?) -> String {
    date.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "なし"
}

/// 診断の記録の止まった理由を、開発者メニューに出す文にして返す。stopReason が nil の時は「なし」を返す
private func debugDiagnosticsText(stopReason: ScreenCaptureStopReason?) -> String {
    switch stopReason {
    case .stoppedInApp:
        "本体アプリの停止の操作"
    case .stoppedOutsideApp:
        "アプリの外 (システムの操作) での停止"
    case .error(let failureDescription):
        "エラー: \(failureDescription)"
    case nil:
        "なし"
    }
}

/// App Group の共有コンテナを使えない時に、開発者メニューに出す文
private let debugAppGroupUnavailableMessage = "App Group の共有コンテナを使えない (署名していないビルド等)"

/// 開発者メニューで結果の画面を開く時と、見本の読み取り結果を保存する時に使う、見本の発言と翻訳
private let debugSampleMessages = [
    TranslatedMessage(
        originalText: "Hey, are you free for a quick call this afternoon?",
        translatedText: "今日の午後、少し通話する時間はありますか？"
    ),
    TranslatedMessage(
        originalText: "I want to go over the release plan before Friday.",
        translatedText: "金曜日までにリリースの計画を確認しておきたいです。"
    ),
]

/// 開発者メニューで結果の画面を開く時と、見本の読み取り結果を保存する時に使う、見本の返信案
private let debugSampleReplySuggestions = [
    ReplySuggestion(text: "Sure, I'm free after 3 pm.", meaning: "はい、15 時以降なら空いています。"),
    ReplySuggestion(text: "Can we do it tomorrow morning instead?", meaning: "代わりに明日の午前でもいいですか？"),
    ReplySuggestion(text: "Sorry, I'm busy today. Could you send me the plan first?", meaning: "すみません、今日は忙しいです。先に計画を送ってもらえますか？"),
]
#endif
