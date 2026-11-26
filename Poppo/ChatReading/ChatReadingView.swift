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

/// スクリーンショット (screenshot) から、発言ごとの翻訳と返信案を作って返す。
/// 訳す先の言語・相手との関係・返信案を作るモデルは、端末に保存してある選択を使う。
/// スクリーンショットを読み出せない時は ChatReadingError.imageUnavailable を、ほかは readChat(image:...) と同じエラーを投げる
func readChat(screenshot: PHAsset) async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion]) {
    guard
        let image = await loadScreenshotImage(
            asset: screenshot,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default
        )?.cgImage
    else {
        throw ChatReadingError.imageUnavailable
    }
    return try await readChat(
        image: image,
        recognizeTextLines: { try await recognizeTextLines(image: $0) },
        translateTexts: { try await translateIntoSelectedLanguageOnDevice(texts: $0) },
        replyModel: selectedReplyModel(userDefaults: .standard),
        canGenerateReplies: { canGenerateReplies(replyModel: $0) },
        generateReplyTexts: { try await generateReplyTextsForSelectedRelationship(messages: $0, replyModel: $1) }
    )
}

/// 訳す先として選べる言語の一覧を、名前の順に並べて返す。supportedLanguages は Translation が端末で訳せる言語、
/// selectedLanguage は今選んでいる言語。selectedLanguage が supportedLanguages に無い時 (一覧を読み出す前を含む) も、選んでいる値を出すために足す。
/// 同じ言語 (maximalIdentifier が同じ) は 1 つにまとめる
func targetLanguageOptions(supportedLanguages: [Locale.Language], selectedLanguage: Locale.Language) -> [Locale.Language] {
    ([selectedLanguage] + supportedLanguages)
        .reduce(into: [Locale.Language]()) { options, language in
            if !options.contains(where: { $0.maximalIdentifier == language.maximalIdentifier }) {
                options.append(language)
            }
        }
        .sorted { languageName(language: $0).localizedStandardCompare(languageName(language: $1)) == .orderedAscending }
}

/// Translation が端末で訳せる言語を返す。LanguageAvailability は Sendable でないため、main actor の外で作って読む
@concurrent nonisolated func translationSupportedLanguages() async -> [Locale.Language] {
    await LanguageAvailability().supportedLanguages
}

/// 言語を、利用者が読める名前 (アプリが動いている言語での言語の名前) にして返す
func languageName(language: Locale.Language) -> String {
    // 名前を引けない言語でも、言語の一覧で空の行にせず、ほかの言語と見分けられるようにするため、識別子を出す
    Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
}

/// 訳す先の言語の欄の見出し。欄の上に出す見出しと、読み上げに使う Picker のラベルの両方に使う
func targetLanguageFieldTitle() -> Text {
    // ja: 訳す言語
    Text("Translate into")
}

/// 相手との関係の欄の見出し。欄の上に出す見出しと、読み上げに使う Picker のラベルの両方に使う
func chatPartnerRelationshipFieldTitle() -> Text {
    // ja: 相手との関係
    Text("Relationship")
}

/// 読み取りの処理 (read) を実行して、画面の状態 (読み取りの結果か失敗) を返す。
/// 読み取りの途中でこの関数を動かすタスクが取りやめられた時は nil を返す (後から始めた読み取りの結果を、前の読み取りの結果で上書きしないため)
func chatReadingPhaseUnlessCancelled(
    read: @MainActor () async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
) async -> ChatReadingPhase? {
    // 取りやめを確かめる前に読み取りを終えるため、結果を変数に置く (式のまま畳むと、取りやめの確かめが読み取りより先に評価される)
    let readPhase = await chatReadingPhase(read: read)
    return Task.isCancelled ? nil : readPhase
}

/// 選ぶ欄で選んでいる値 (selectedValue) を、保存してある値 (savedValue。何も保存していない時は既定の値) と違う時だけ save で保存する。
/// 画面を開いただけで既定の値 (端末の言語・未選択) を「選んだ値」として保存しないため (保存すると、後で端末の言語を変えても訳す先が変わらなくなる)
func saveIfChanged<Value: Equatable>(selectedValue: Value, savedValue: Value, save: (Value) -> Void) {
    if selectedValue != savedValue {
        save(selectedValue)
    }
}

/// 相手との関係 (nil は未選択) の、選ぶ画面に出す名前
func chatPartnerRelationshipText(chatPartnerRelationship: ChatPartnerRelationship?) -> Text {
    switch chatPartnerRelationship {
    case nil:
        // ja: 未選択
        Text("Not selected")
    case .friendOrFamily:
        // ja: 友人・家族
        Text("Friend or family")
    case .coworker:
        // ja: 仕事の仲間
        Text("Coworker")
    case .superiorOrClient:
        // ja: 目上・取引先
        Text("Superior or client")
    case .stranger:
        // ja: 初めての相手
        Text("Someone new")
    }
}

/// 読み取りの画面。訳す先の言語と相手との関係を選ぶ欄を上に置き、その下に読み取りの状態 (翻訳と返信案など) を出す。
/// 言語か関係を選び直すと、選んだものを端末に保存して読み取りをやり直す
struct ChatReadingView: View {
    /// 読み取りの処理。発言ごとの翻訳と返信案を返す。訳す先の言語と相手との関係は、処理の中で端末に保存してある選択を読む
    /// (本物は readChat(screenshot:)。開発者メニューは見本の読み取り結果を返す処理を渡す)
    let readChatContent: @MainActor () async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
    /// 画面の状態
    @State private var phase = ChatReadingPhase.reading
    /// 言語のダウンロードをシステムに頼むための設定。利用者がダウンロードを選ぶまでは nil
    @State private var languageDownloadConfiguration: TranslationSession.Configuration?
    /// 訳す先として選んでいる言語の maximalIdentifier。最初は端末に保存してある選択 (無ければ端末の言語)
    @State private var targetLanguageIdentifier = selectedTargetLanguage(
        userDefaults: .standard,
        preferredLanguages: Locale.preferredLanguages
    ).maximalIdentifier
    /// 選んでいる相手との関係。nil は未選択。最初は端末に保存してある選択
    @State private var chatPartnerRelationship = selectedChatPartnerRelationship(userDefaults: .standard)
    /// Translation が端末で訳せる言語。読み出すまでは空
    @State private var supportedLanguages: [Locale.Language] = []
    /// 読み直しを頼んだ回数 (「もう一度試す」と、言語のダウンロードが終わった時に増やす)。
    /// 読み取りを 1 つの .task(id:) だけから始めるために使い、新しい読み取りが前の読み取りを取りやめるようにする
    @State private var readRequestCount = 0

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
                readRequestCount += 1
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    targetLanguageFieldTitle()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(selection: $targetLanguageIdentifier) {
                        ForEach(
                            targetLanguageOptions(
                                supportedLanguages: supportedLanguages,
                                selectedLanguage: Locale.Language(identifier: targetLanguageIdentifier)
                            ),
                            id: \.maximalIdentifier
                        ) { language in
                            Text(verbatim: languageName(language: language))
                                .tag(language.maximalIdentifier)
                        }
                    } label: {
                        targetLanguageFieldTitle()
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("target_language_picker")
                }
                VStack(alignment: .leading, spacing: 2) {
                    chatPartnerRelationshipFieldTitle()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker(selection: $chatPartnerRelationship) {
                        chatPartnerRelationshipText(chatPartnerRelationship: nil)
                            .tag(ChatPartnerRelationship?.none)
                        ForEach(ChatPartnerRelationship.allCases, id: \.self) { relationship in
                            chatPartnerRelationshipText(chatPartnerRelationship: relationship)
                                .tag(Optional(relationship))
                        }
                    } label: {
                        chatPartnerRelationshipFieldTitle()
                    }
                    .labelsHidden()
                    .accessibilityIdentifier("chat_partner_relationship_picker")
                }
                Spacer(minLength: 0)
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        // ja: 翻訳
        .navigationTitle("Translation")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            supportedLanguages = await translationSupportedLanguages()
        }
        // 最初に開いた時、言語か関係を選び直した時、読み直しを頼んだ時に読み取る。どの時も、途中の前の読み取りを取りやめて読み直す
        .task(id: [targetLanguageIdentifier, chatPartnerRelationship?.rawValue, String(readRequestCount)]) {
            saveIfChanged(
                selectedValue: targetLanguageIdentifier,
                savedValue: selectedTargetLanguage(userDefaults: .standard, preferredLanguages: Locale.preferredLanguages).maximalIdentifier,
                save: { save(selectedTargetLanguage: Locale.Language(identifier: $0), userDefaults: .standard) }
            )
            saveIfChanged(
                selectedValue: chatPartnerRelationship,
                savedValue: selectedChatPartnerRelationship(userDefaults: .standard),
                save: { save(selectedChatPartnerRelationship: $0, userDefaults: .standard) }
            )
            phase = .reading
            if let readPhase = await chatReadingPhaseUnlessCancelled(read: readChatContent) {
                phase = readPhase
            }
        }
        .translationTask(languageDownloadConfiguration) { session in
            // TranslationSession は Sendable でなく、prepareTranslation() は呼び出し元の actor の外で動く宣言のため、
            // MainActor のこのクロージャが受け取った session をそのままでは呼べない (data race の検査で止まる)。
            // session はこのクロージャの中で 1 度に 1 つの呼び出しにしか使わないため、検査の対象から外す
            nonisolated(unsafe) let downloadSession = session
            // ダウンロードを利用者が取りやめた時は、促す表示のまま残す
            if (try? await downloadSession.prepareTranslation()) != nil {
                readRequestCount += 1
            }
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
