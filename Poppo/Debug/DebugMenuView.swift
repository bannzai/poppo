#if DEBUG
import Photos
import SwiftUI

/// 開発者メニュー。simulator では動かない処理 (翻訳・返信案の生成・言語のダウンロード・画面の取り込み) を通さずに、その先の画面を確かめるための入口。
/// DEBUG ビルドにだけ入る。書き換えるデータは、キーボードに渡す読み取り結果 (見本の保存と削除)、返信案を作るモデルの選択、
/// 返信案を作るモデルの API キー (端末の Keychain)、写真ライブラリ (見本のスクリーンショットを足す。消さない) だけ
struct DebugMenuView: View {
    /// 取り込みの状態。診断の記録を出すのに使う
    @Environment(ScreenCaptureController.self) private var screenCaptureController
    /// 今保存してある読み取り結果。保存していない時は nil。この画面の操作の後と、画面を開いた時に読み直す
    @State private var savedLatestReading: LatestReading?
    /// 直前の読み取り結果の保存・削除が失敗した時のエラーの説明。成功した時と、まだ操作していない時は nil
    @State private var latestReadingOperationError: String?

    /// 返信案を作るモデルとして選ばれているもの。この画面で選んだ後と、画面を開いた時に読み直す
    @State private var replyModel = selectedReplyModel(userDefaults: .standard)
    /// 発言を端末の外へ送るモデルのうち、選ぶ操作をして、送ることの確認の返事を待っているもの。確認を出していない時は nil
    @State private var replyModelWaitingForSendingConfirmation: ReplyModel?

    /// API キーの入力欄に入力している文。モデルごとに持ち、保存か削除をしたモデルの分は空に戻す。保存するまで端末には残らない
    @State private var enteredAPIKeys: [ReplyModel: String] = [:]
    /// API キーを Keychain に保存してあるモデル。この画面の操作の後と、画面を開いた時に読み直す
    @State private var replyModelsWithSavedAPIKey: Set<ReplyModel> = []
    /// 直前の API キーの保存か削除が失敗した時のエラーの説明 (API キーの値は入らない)。次の保存か削除が成功するまで残す。
    /// 直前の保存か削除が成功した時と、まだ操作していない時は nil
    @State private var apiKeyOperationError: String?
    /// 直前の、保存してある API キーの読み直しが失敗した時のエラーの説明 (API キーの値は入らない)。すべてのモデルを読めた時は nil
    @State private var apiKeyReloadError: String?

    /// 写真ライブラリに残っている見本のスクリーンショットの数。この画面の操作の後と、画面を開いた時に読み直す
    @State private var sampleScreenshotCount = 0
    /// 見本のスクリーンショットのうち、写真アプリがスクリーンショットの種別を付けたものの数。sampleScreenshotCount と同じ時に読み直す
    @State private var sampleScreenshotMarkedCount = 0
    /// 直前の見本のスクリーンショットの追加が失敗した時のエラーの説明。成功した時と、まだ操作していない時は nil
    @State private var sampleScreenshotError: String?

    /// 写真ライブラリへのアクセスの許可を (まだ選んでいなければ) 求めてから、見本のスクリーンショットを足す。
    /// 足せなかった時は、エラーの説明を sampleScreenshotError に入れる
    private func addSampleScreenshots() async {
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        do {
            try await addDebugSampleScreenshots()
            sampleScreenshotError = nil
        } catch {
            sampleScreenshotError = error.localizedDescription
        }
        reloadSampleScreenshotCounts()
    }

    /// 写真ライブラリに残っている見本のスクリーンショットの数を読み直す
    private func reloadSampleScreenshotCounts() {
        sampleScreenshotCount = debugSampleScreenshots().count
        sampleScreenshotMarkedCount = debugSampleScreenshotsMarkedAsScreenshotCount()
    }

    /// 返信案を作るモデルとして selectingReplyModel を選んだことを保存し、この画面の表示を保存した後の値にする
    private func select(replyModel selectingReplyModel: ReplyModel) {
        save(selectedReplyModel: selectingReplyModel, userDefaults: .standard)
        replyModel = selectedReplyModel(userDefaults: .standard)
    }

    /// 入力欄の文を、apiKeyReplyModel のモデルの API キーとして Keychain に保存する。前に保存したキーは上書きされる。
    /// 貼り付けた文の前後の空白と改行は取り除く。保存できた時は入力欄を空に戻す。
    /// 保存できなかった時は、エラーの説明を apiKeyOperationError に入れる (画面を開き直しても、次の保存か削除が成功するまで残る)
    private func saveEnteredAPIKey(apiKeyReplyModel: ReplyModel) {
        do {
            try save(
                apiKey: apiKey(enteredText: enteredAPIKeys[apiKeyReplyModel, default: ""]),
                replyModel: apiKeyReplyModel,
                keychainService: replyModelAPIKeyKeychainService
            )
            enteredAPIKeys[apiKeyReplyModel] = nil
            apiKeyOperationError = nil
        } catch {
            apiKeyOperationError = error.localizedDescription
        }
        reloadReplyModelsWithSavedAPIKey()
    }

    /// apiKeyReplyModel のモデルの API キーを Keychain から削除し、入力欄を空に戻す。保存していない時に実行しても何も起きない。
    /// 削除できなかった時は、エラーの説明を apiKeyOperationError に入れる (画面を開き直しても、次の保存か削除が成功するまで残る)
    private func deleteSavedAPIKey(apiKeyReplyModel: ReplyModel) {
        do {
            try deleteAPIKey(replyModel: apiKeyReplyModel, keychainService: replyModelAPIKeyKeychainService)
            enteredAPIKeys[apiKeyReplyModel] = nil
            apiKeyOperationError = nil
        } catch {
            apiKeyOperationError = error.localizedDescription
        }
        reloadReplyModelsWithSavedAPIKey()
    }

    /// API キーを保存してあるモデルを Keychain から読み直して replyModelsWithSavedAPIKey に入れる。
    /// 読めなかったモデルは保存していない扱いにし、エラーの説明を apiKeyReloadError に入れる。
    /// すべてのモデルを読めた時は apiKeyReloadError を nil にする。保存と削除の失敗の説明 (apiKeyOperationError) は変えない
    private func reloadReplyModelsWithSavedAPIKey() {
        apiKeyReloadError = nil
        replyModelsWithSavedAPIKey = Set(
            ReplyModel.allCases.filter { usesAPIKey(replyModel: $0) }.filter { apiKeyReplyModel in
                do {
                    return try loadAPIKey(replyModel: apiKeyReplyModel, keychainService: replyModelAPIKeyKeychainService) != nil
                } catch {
                    apiKeyReloadError = error.localizedDescription
                    return false
                }
            }
        )
    }

    var body: some View {
        List {
            Section {
                ForEach(ReplyModel.allCases, id: \.self) { selectableReplyModel in
                    Button {
                        if needsSendingConfirmation(selectingReplyModel: selectableReplyModel, currentReplyModel: replyModel) {
                            replyModelWaitingForSendingConfirmation = selectableReplyModel
                        } else {
                            select(replyModel: selectableReplyModel)
                        }
                    } label: {
                        HStack {
                            Text(verbatim: debugMenuText(replyModel: selectableReplyModel))
                            Spacer()
                            if selectableReplyModel == replyModel {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .accessibilityIdentifier("debug_select_reply_model_\(selectableReplyModel.rawValue)")
                }
                LabeledContent {
                    Text(verbatim: debugMenuText(replyModel: replyModel))
                } label: {
                    Text(verbatim: "選ばれているモデル")
                }
                .accessibilityIdentifier("debug_selected_reply_model")
                LabeledContent {
                    Text(verbatim: canGenerateReplies(replyModel: replyModel) ? "使える" : "使えない")
                } label: {
                    Text(verbatim: "選ばれているモデルが今使えるか")
                }
                .accessibilityIdentifier("debug_selected_reply_model_availability")
            } header: {
                Text(verbatim: "返信案を作るモデル")
            } footer: {
                Text(verbatim: "選んだ後に読む画面 (スクリーンショットからの読み取りと、取り込み) の返信案を、選んだモデルが作る。アプリを起動し直しても選んだままになる。選んだモデルが使えない時 (OpenAI と Gemini は API キーを保存していない時。Claude は simulator など App Attest を使えない端末の時) は、ほかのモデルに切り替えず、返信案なしで翻訳だけを出す。「端末内」のほかを選ぶと、画面から読んだ発言がそのモデルの提供元のサーバーへ送られるため、選ぶ時に確認が出る (取り消すと選択は変わらない)")
            }
            Section {
                ForEach(ReplyModel.allCases.filter { usesAPIKey(replyModel: $0) }, id: \.self) { apiKeyReplyModel in
                    SecureField(
                        text: Binding(
                            get: { enteredAPIKeys[apiKeyReplyModel, default: ""] },
                            set: { enteredAPIKeys[apiKeyReplyModel] = $0 }
                        )
                    ) {
                        Text(verbatim: "\(debugMenuText(replyModel: apiKeyReplyModel)) の API キー")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("debug_reply_model_api_key_field_\(apiKeyReplyModel.rawValue)")
                    Button {
                        saveEnteredAPIKey(apiKeyReplyModel: apiKeyReplyModel)
                    } label: {
                        Text(verbatim: "\(debugMenuText(replyModel: apiKeyReplyModel)) の API キーを保存する")
                    }
                    .disabled(apiKey(enteredText: enteredAPIKeys[apiKeyReplyModel, default: ""]).isEmpty)
                    .accessibilityIdentifier("debug_save_reply_model_api_key_\(apiKeyReplyModel.rawValue)")
                    Button(role: .destructive) {
                        deleteSavedAPIKey(apiKeyReplyModel: apiKeyReplyModel)
                    } label: {
                        Text(verbatim: "\(debugMenuText(replyModel: apiKeyReplyModel)) の API キーを消す")
                    }
                    .accessibilityIdentifier("debug_delete_reply_model_api_key_\(apiKeyReplyModel.rawValue)")
                    LabeledContent {
                        Text(verbatim: replyModelsWithSavedAPIKey.contains(apiKeyReplyModel) ? "保存済み" : "なし")
                    } label: {
                        Text(verbatim: "保存してある \(debugMenuText(replyModel: apiKeyReplyModel)) の API キー")
                    }
                    .accessibilityIdentifier("debug_reply_model_api_key_state_\(apiKeyReplyModel.rawValue)")
                }
                if let apiKeyOperationError {
                    Text(verbatim: apiKeyOperationError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("debug_reply_model_api_key_error")
                }
                if let apiKeyReloadError {
                    Text(verbatim: apiKeyReloadError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("debug_reply_model_api_key_reload_error")
                }
            } header: {
                Text(verbatim: "返信案を作るモデルの API キー")
            } footer: {
                Text(verbatim: "保存した API キーは、この端末の Keychain にだけ置く (ほかの端末へは移さない)。保存したキーの値はこの画面に出さない。費用の上限は、各社の画面でキーに付ける")
            }
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
                    Task {
                        await addSampleScreenshots()
                    }
                } label: {
                    Text(verbatim: "見本のスクリーンショット (30 枚) を写真に足す")
                }
                .accessibilityIdentifier("debug_add_sample_screenshots")
                LabeledContent {
                    Text(verbatim: "\(sampleScreenshotCount) 枚 (スクリーンショットの種別: \(sampleScreenshotMarkedCount) 枚)")
                } label: {
                    Text(verbatim: "写真にある見本")
                }
                .accessibilityIdentifier("debug_sample_screenshots_state")
                NavigationLink {
                    ScreenshotGrid(screenshots: debugSampleScreenshots())
                } label: {
                    Text(verbatim: "見本だけの一覧を開く")
                }
                .accessibilityIdentifier("debug_open_sample_screenshot_grid")
                NavigationLink {
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(
                                [
                                    ScreenshotImageUnavailableReason.inCloudOnly,
                                    .cancelled,
                                    .failed(errorDescription: "PHPhotosErrorDomain 3164: 見本のエラーの内容"),
                                    .unknown,
                                ],
                                id: \.self
                            ) { reason in
                                ScreenshotThumbnailFrame(loadResult: .failure(reason))
                            }
                        }
                        .padding()
                    }
                } label: {
                    Text(verbatim: "読み出せない縮小画像の見本を開く")
                }
                .accessibilityIdentifier("debug_open_unavailable_thumbnails")
                if let sampleScreenshotError {
                    Text(verbatim: sampleScreenshotError)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("debug_sample_screenshots_error")
                }
            } header: {
                Text(verbatim: "スクリーンショットの一覧")
            } footer: {
                Text(verbatim: "simulator の写真にはスクリーンショットが無いため、番号を書いた見本を足して一覧とタップを確かめる。1 番が最も新しく、2 番は横長、5 番は正方形、ほかは縦長。足した見本は写真アプリで消す (何度押しても、残っていれば足し直さない)。スクリーンショットの種別が付かなかった時は「見本だけの一覧を開く」で、同じ一覧の画面に見本を並べる")
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
                            ScreenCaptureCapturingBar(failedToStop: false, stop: {})
                        }
                } label: {
                    Text(verbatim: "取り込み中の表示を開く")
                }
                .accessibilityIdentifier("debug_open_capture_capturing")
                NavigationLink {
                    Color.clear
                        .safeAreaInset(edge: .bottom) {
                            ScreenCaptureCapturingBar(failedToStop: true, stop: {})
                        }
                } label: {
                    Text(verbatim: "取り込み中の表示を開く (止められなかった後)")
                }
                .accessibilityIdentifier("debug_open_capture_capturing_stop_failed")
            } header: {
                Text(verbatim: "画面の取り込みの画面")
            }
            Section {
                if let diagnostics = screenCaptureController.diagnostics {
                    DebugScreenCaptureDiagnosticsRows(diagnostics: diagnostics)
                } else {
                    Text(verbatim: "記録なし (まだ取り込みを始めていない)")
                        .accessibilityIdentifier("debug_capture_no_diagnostics")
                }
                if let stopFailureDescription = screenCaptureController.stopFailureDescription {
                    LabeledContent {
                        Text(verbatim: stopFailureDescription)
                    } label: {
                        Text(verbatim: "停止の操作の失敗 (取り込みは続いているかもしれない)")
                    }
                    .accessibilityIdentifier("debug_capture_stop_failure")
                }
            } header: {
                Text(verbatim: "画面の取り込みの診断の記録")
            } footer: {
                Text(verbatim: "直近の 1 回の取り込みの記録。始めた時刻があり、止めた時刻が「なし」のまま取り込み中の表示が出ていない時は、止まる前にアプリが終了している。読み取りの各段は、取り込み中に画面が変わるたびに 1 回進む。取り込みの途中で返信案を作るモデルを選び直すと、返信案の生成の回数には選び直す前のモデルの分も入る")
            }
            Section {
                NavigationLink {
                    List {
                        DebugScreenCaptureDiagnosticsRows(diagnostics: debugSampleDiagnostics)
                    }
                } label: {
                    Text(verbatim: "診断の記録の見本を開く")
                }
                .accessibilityIdentifier("debug_open_sample_diagnostics")
            } header: {
                Text(verbatim: "診断の記録の表示")
            } footer: {
                Text(verbatim: "simulator では取り込みが始まらず記録が出ないため、見本の値で表示を確かめる")
            }
        }
        .navigationTitle(Text(verbatim: "開発者メニュー"))
        .onAppear {
            reloadSavedLatestReading()
            replyModel = selectedReplyModel(userDefaults: .standard)
            reloadReplyModelsWithSavedAPIKey()
            reloadSampleScreenshotCounts()
        }
        .alert(
            Text(verbatim: "発言を端末の外へ送る"),
            isPresented: Binding(
                get: { replyModelWaitingForSendingConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        replyModelWaitingForSendingConfirmation = nil
                    }
                }
            ),
            presenting: replyModelWaitingForSendingConfirmation
        ) { confirmingReplyModel in
            Button {
                select(replyModel: confirmingReplyModel)
            } label: {
                Text(verbatim: "送ることを確かめて選ぶ")
            }
            .accessibilityIdentifier("debug_confirm_sending_messages_outside_device")
            Button(role: .cancel) {
            } label: {
                Text(verbatim: "取り消す")
            }
            .accessibilityIdentifier("debug_cancel_sending_messages_outside_device")
        } message: { confirmingReplyModel in
            Text(verbatim: "\(debugMenuText(replyModel: confirmingReplyModel)) を選ぶと、この後に読む画面 (スクリーンショットからの読み取りと、取り込み) から読んだチャットの発言 (相手の発言を含む) を、返信案を作るために \(debugMenuSendingDestinationText(replyModel: confirmingReplyModel)) へ送る。ほかのモデルを選び直すまで送り続ける")
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

/// 診断の記録 1 つの中身を、開発者メニューの行として並べる。List か Section の中に置く
struct DebugScreenCaptureDiagnosticsRows: View {
    /// 表示する診断の記録
    let diagnostics: ScreenCaptureDiagnostics

    var body: some View {
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
        DebugScreenReadingStageRow(title: "文字の読み取り", stage: diagnostics.reading.recognition)
            .accessibilityIdentifier("debug_reading_recognition")
        DebugScreenReadingStageRow(title: "翻訳", stage: diagnostics.reading.translation)
            .accessibilityIdentifier("debug_reading_translation")
        DebugScreenReadingStageRow(title: "返信案の生成", stage: diagnostics.reading.replyGeneration)
            .accessibilityIdentifier("debug_reading_reply_generation")
        LabeledContent {
            Text(verbatim: diagnostics.reading.replyGenerationModel.map { debugMenuText(replyModel: $0) } ?? "なし")
        } label: {
            Text(verbatim: "最後に返信案の生成を試したモデル")
        }
        .accessibilityIdentifier("debug_reading_reply_generation_model")
        DebugScreenReadingStageRow(title: "保存", stage: diagnostics.reading.saving)
            .accessibilityIdentifier("debug_reading_saving")
        LabeledContent {
            Text(verbatim: String(diagnostics.reading.noMessagesCount))
        } label: {
            Text(verbatim: "発言が無かった回数")
        }
        .accessibilityIdentifier("debug_reading_no_messages_count")
        LabeledContent {
            Text(verbatim: String(diagnostics.reading.unchangedMessagesCount))
        } label: {
            Text(verbatim: "発言が前と同じで訳さなかった回数")
        }
        .accessibilityIdentifier("debug_reading_unchanged_messages_count")
        LabeledContent {
            Text(verbatim: String(diagnostics.reading.untranslatableCount))
        } label: {
            Text(verbatim: "訳す必要が無いか訳せない言語だった回数")
        }
        .accessibilityIdentifier("debug_reading_untranslatable_count")
        LabeledContent {
            Text(verbatim: String(diagnostics.reading.shownLatestReadingCount))
        } label: {
            Text(verbatim: "キーボードの表示が映っていて読み直さなかった回数")
        }
        .accessibilityIdentifier("debug_reading_shown_latest_reading_count")
    }
}

/// 読み取りの 1 つの段の記録を、開発者メニューの 1 行として出す。成功と失敗の回数、最後の時刻、最後のエラーの内容を縦に並べる
struct DebugScreenReadingStageRow: View {
    /// 段の名前
    let title: String
    /// 表示する段の記録
    let stage: ScreenReadingStageDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: title)
            Text(verbatim: "成功 \(stage.successCount) 回 (最後: \(debugDiagnosticsText(date: stage.lastSucceededAt)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(verbatim: "失敗 \(stage.failureCount) 回 (最後: \(debugDiagnosticsText(date: stage.lastFailedAt)))")
                .font(.footnote)
                .foregroundStyle(stage.failureCount > 0 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            if let lastFailureDescription = stage.lastFailureDescription {
                Text(verbatim: "最後のエラー: \(lastFailureDescription)")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 開発者メニューで診断の記録の表示を確かめる時に使う、見本の診断の記録。
/// 取り込み中に文字を 12 回読み、そのうち 3 回で翻訳と保存まで進み、返信案の生成は 1 回失敗した、という値
private let debugSampleDiagnostics = ScreenCaptureDiagnostics(
    startedAt: Date(timeIntervalSinceReferenceDate: 800_000_000),
    stoppedAt: nil,
    stopReason: nil,
    lastFrameReceivedAt: Date(timeIntervalSinceReferenceDate: 800_000_090),
    receivedFrameCount: 5400,
    reading: ScreenReadingDiagnostics(
        recognition: ScreenReadingStageDiagnostics(successCount: 12, lastSucceededAt: Date(timeIntervalSinceReferenceDate: 800_000_088)),
        translation: ScreenReadingStageDiagnostics(successCount: 3, lastSucceededAt: Date(timeIntervalSinceReferenceDate: 800_000_089)),
        replyGeneration: ScreenReadingStageDiagnostics(
            successCount: 2,
            lastSucceededAt: Date(timeIntervalSinceReferenceDate: 800_000_050),
            failureCount: 1,
            lastFailedAt: Date(timeIntervalSinceReferenceDate: 800_000_089),
            lastFailureDescription: "com.example.model 4: 見本のエラーの内容"
        ),
        replyGenerationModel: .onDevice,
        saving: ScreenReadingStageDiagnostics(successCount: 3, lastSucceededAt: Date(timeIntervalSinceReferenceDate: 800_000_089)),
        noMessagesCount: 4,
        unchangedMessagesCount: 3,
        untranslatableCount: 1,
        shownLatestReadingCount: 1
    )
)

/// 返信案を作るモデルを、開発者メニューに出す名前にして返す
private func debugMenuText(replyModel: ReplyModel) -> String {
    switch replyModel {
    case .onDevice:
        "端末内"
    case .privateCloudCompute:
        "Private Cloud Compute"
    case .openAI:
        "OpenAI"
    case .gemini:
        "Gemini"
    case .claude:
        "Claude"
    }
}

/// replyModel のモデルで返信案を作る時に、画面から読んだ発言を送る先を、開発者メニューに出す名前にして返す。
/// 選ぶ時の確認に出す (sendsMessagesOutsideDevice(replyModel:) が true のモデル)
private func debugMenuSendingDestinationText(replyModel: ReplyModel) -> String {
    switch replyModel {
    case .onDevice:
        "端末内 (端末の外へは送らない)"
    case .privateCloudCompute:
        "Apple のサーバー (Private Cloud Compute)"
    case .openAI:
        "OpenAI のサーバー"
    case .gemini:
        "Google のサーバー"
    case .claude:
        "Anthropic のサーバー"
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
