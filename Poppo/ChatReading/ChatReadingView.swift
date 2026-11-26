import Photos
import SwiftUI
import Translation

/// スクリーンショットからの読み取りの画面の状態
enum ChatReadingPhase {
    /// 読み取りの処理が動いている
    case reading
    /// 読み取りが終わり、発言ごとの翻訳と返信案を出している
    case loaded(messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
    /// 訳す言語が端末に入っておらず、言語のダウンロードを促している
    case needsLanguageDownload(source: Locale.Language, target: Locale.Language)
    /// 画像から発言を 1 つも読み取れなかった
    case noMessages
    /// 原文の言語を利用者の言語に翻訳できない
    case untranslatableLanguage
    /// 上のどれでもない理由で読み取りに失敗した。もう一度読み取ることを選べる
    case failed
}

/// 読み取りの処理 read を実行し、その結果から画面の状態を決める。
/// 訳す言語が端末に入っていない失敗 (ChatReadingError.languageNotInstalled) は言語のダウンロードを促す状態に、
/// 発言が無い失敗 (noMessages) と翻訳できない言語の失敗 (untranslatableLanguage) はそれぞれの状態に、ほかの失敗は failed にする
func chatReadingPhase(
    read: @MainActor () async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
) async -> ChatReadingPhase {
    do {
        let reading = try await read()
        return .loaded(messages: reading.messages, replySuggestions: reading.replySuggestions)
    } catch ChatReadingError.languageNotInstalled(let source, let target) {
        return .needsLanguageDownload(source: source, target: target)
    } catch ChatReadingError.noMessages {
        return .noMessages
    } catch ChatReadingError.untranslatableLanguage {
        return .untranslatableLanguage
    } catch {
        return .failed
    }
}

/// 利用者が言語のダウンロードを選んだ時に、システムへダウンロードを頼むための設定を返す。
/// current が同じ言語の組 (source・target) の設定なら、同じ設定のままでは translationTask が動き直さないため、
/// 無効にして動かし直せるようにした current を返す。current が無い・違う言語の組の時は、渡した組の新しい設定を返す
func nextLanguageDownloadConfiguration(
    current: TranslationSession.Configuration?,
    source: Locale.Language,
    target: Locale.Language
) -> TranslationSession.Configuration {
    guard var configuration = current, configuration.source == source, configuration.target == target else {
        return TranslationSession.Configuration(source: source, target: target)
    }
    configuration.invalidate()
    return configuration
}

/// 選んだスクリーンショットを読み取り、発言ごとの翻訳と返信案を出す画面
struct ChatReadingView: View {
    /// 読み取るスクリーンショット
    let screenshot: PHAsset
    /// 画面の状態
    @State private var phase = ChatReadingPhase.reading
    /// 言語のダウンロードをシステムに頼むための設定。利用者がダウンロードを選ぶまでは nil
    @State private var languageDownloadConfiguration: TranslationSession.Configuration?
    #if DEBUG
    /// 一覧でタップしてからこの画面が出るまでの時間 (ミリ秒)。一覧からのタップを控えていない時 (開発者メニューから開いた時等) は nil
    @State private var debugTapToAppearMilliseconds: Int?
    #endif

    var body: some View {
        ChatReadingPhaseView(
            phase: phase,
            downloadLanguage: { source, target in
                languageDownloadConfiguration = nextLanguageDownloadConfiguration(
                    current: languageDownloadConfiguration,
                    source: source,
                    target: target
                )
            },
            retry: {
                Task {
                    await read()
                }
            }
        )
        // ja: 翻訳
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        // 一覧でタップした 1 枚がこの画面に渡されたかを、一覧のセルの撮影日時 (accessibilityLabel) と比べて確かめるため、
        // 開発者メニューのあるビルドでだけ、読んでいる 1 枚の撮影日時と、タップしてからこの画面が出るまでの時間を出す
        .safeAreaInset(edge: .top) {
            debugReadingInfo
        }
        .onAppear {
            debugTapToAppearMilliseconds = debugLastScreenshotTapUptime.map {
                Int((ProcessInfo.processInfo.systemUptime - $0) * 1000)
            }
            debugLastScreenshotTapUptime = nil
        }
        #endif
        .task {
            await read()
        }
        .translationTask(languageDownloadConfiguration) { session in
            // TranslationSession は Sendable でなく、prepareTranslation() は呼び出し元の actor の外で動く宣言のため、
            // MainActor のこのクロージャが受け取った session をそのままでは呼べない (data race の検査で止まる)。
            // session はこのクロージャの中で 1 度に 1 つの呼び出しにしか使わないため、検査の対象から外す
            nonisolated(unsafe) let downloadSession = session
            // ダウンロードを利用者が取りやめた時は、促す表示のまま残す
            if (try? await downloadSession.prepareTranslation()) != nil {
                await read()
            }
        }
    }

    #if DEBUG
    /// 開発者メニューのあるビルドでだけ画面の上に出す、読んでいる 1 枚の撮影日時と、タップしてからこの画面が出るまでの時間
    private var debugReadingInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: debugReadingScreenshotText(creationDate: screenshot.creationDate))
                .accessibilityIdentifier("debug_reading_screenshot_date")
            Text(verbatim: debugTapToAppearText(milliseconds: debugTapToAppearMilliseconds))
                .accessibilityIdentifier("debug_tap_to_appear")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    #endif

    /// スクリーンショットを読み取り、結果を画面の状態に入れる
    private func read() async {
        phase = .reading
        phase = await chatReadingPhase {
            guard
                case .success(let loadedImage) = await loadScreenshotImage(
                    asset: screenshot,
                    targetSize: PHImageManagerMaximumSize,
                    contentMode: .default
                ),
                let image = loadedImage.cgImage
            else {
                throw ChatReadingError.imageUnavailable
            }
            return try await readChat(
                image: image,
                recognizeTextLines: { try await recognizeTextLines(image: $0) },
                translateTexts: {
                    try await translateOnDevice(texts: $0, targetLanguage: userLanguage(preferredLanguages: Locale.preferredLanguages))
                },
                replyModel: selectedReplyModel(userDefaults: .standard),
                canGenerateReplies: { canGenerateReplies(replyModel: $0) },
                generateReplyTexts: { try await generateReplyTexts(messages: $0, replyModel: $1) }
            )
        }
    }
}

/// 読み取りの画面の、状態ごとの表示
struct ChatReadingPhaseView: View {
    /// 表示する状態
    let phase: ChatReadingPhase
    /// 利用者が言語のダウンロードを選んだ時に、訳す言語の組を渡して呼ぶ
    let downloadLanguage: (_ source: Locale.Language, _ target: Locale.Language) -> Void
    /// 利用者がもう一度読み取ることを選んだ時に呼ぶ
    let retry: () -> Void

    var body: some View {
        switch phase {
        case .reading:
            // ja: スクリーンショットを読み取っています
            ProgressView("Reading the screenshot")
        case .loaded(let messages, let replySuggestions):
            ChatReadingResultView(messages: messages, replySuggestions: replySuggestions)
        case .needsLanguageDownload(let source, let target):
            ContentUnavailableView {
                // ja: 翻訳用の言語が必要です
                Label("Translation language needed", systemImage: "arrow.down.circle")
            } description: {
                // ja: この端末で翻訳するには言語のダウンロードが必要です
                Text("Download the language to translate this screenshot on your device")
            } actions: {
                Button {
                    downloadLanguage(source, target)
                } label: {
                    // ja: 言語をダウンロード
                    Text("Download language")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("language_download_button")
            }
        case .noMessages:
            // ja: チャットの文字が見つかりませんでした
            ContentUnavailableView("No chat text found", systemImage: "text.magnifyingglass")
        case .untranslatableLanguage:
            // ja: この言語はあなたの言語に翻訳できません
            ContentUnavailableView("This language can't be translated into your language", systemImage: "character.bubble")
        case .failed:
            ContentUnavailableView {
                // ja: このスクリーンショットを読み取れませんでした
                Label("Couldn't read this screenshot", systemImage: "exclamationmark.triangle")
            } actions: {
                Button {
                    retry()
                } label: {
                    // ja: もう一度試す
                    Text("Try again")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chat_reading_retry_button")
            }
        }
    }
}
