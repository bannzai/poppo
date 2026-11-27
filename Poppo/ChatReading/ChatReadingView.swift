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

/// スクリーンショット (screenshot) の画像を読み出し、写っている文字を行ごとに読んで返す。
/// スクリーンショットを読み出せない時は ChatReadingError.imageUnavailable を、ほかは recognizeTextLines(image:) と同じエラーを投げる
func recognizeTextLines(screenshot: PHAsset) async throws -> [RecognizedTextLine] {
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
    return try await recognizeTextLines(image: image)
}

/// スクリーンショットから読んだ行 (lines) から、発言ごとの翻訳と返信案を作って返す。
/// 訳す先の言語・相手との関係・返信案を作るモデルは、端末に保存してある選択を使う。readChat(lines:...) と同じエラーを投げる
func readChat(lines: [RecognizedTextLine]) async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion]) {
    try await readChat(
        lines: lines,
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

/// 読み取りの画面の、読み取りを動かすタスクの id。選んでいる言語・関係・読み直しを頼んだ回数のどれかが変わると、違う id を返す
/// (id が変わると、SwiftUI が前の読み取りを取りやめて読み直す)
func chatReadingTaskID(
    targetLanguageIdentifier: String,
    chatPartnerRelationship: ChatPartnerRelationship?,
    readRequestCount: Int
) -> [String?] {
    [targetLanguageIdentifier, chatPartnerRelationship?.rawValue, String(readRequestCount)]
}

/// 過去の読み取りの記録の既定 (defaultChoice) を今の選択 (savedTargetLanguageIdentifier・chatPartnerRelationship) に当てると、
/// 読み取りの画面が読み取りを始め直すか (読み取りのタスクの id chatReadingTaskID が変わるか) を返す。
/// savedTargetLanguageIdentifier は端末に保存してある書き方のまま (未選択は空文字) で受け取る。訳す先の言語は保存の書き方ではなく、
/// 未選択の時に端末の言語 (preferredLanguages) へ置き換えた後の言語で比べる (タスクの id がその言語から作られるため)
func defaultChoiceRestartsChatReading(
    defaultChoice: ScreenshotReadingChoice,
    savedTargetLanguageIdentifier: String,
    chatPartnerRelationship: ChatPartnerRelationship?,
    preferredLanguages: [String]
) -> Bool {
    // 0: 既定を当てても読み直しを頼んだ回数は変わらないため、両方に同じ値を渡す
    chatReadingTaskID(
        targetLanguageIdentifier: targetLanguage(
            savedIdentifier: defaultChoice.targetLanguageIdentifier,
            preferredLanguages: preferredLanguages
        ).maximalIdentifier,
        chatPartnerRelationship: defaultChoice.chatPartnerRelationship,
        readRequestCount: 0
    )
        != chatReadingTaskID(
            targetLanguageIdentifier: targetLanguage(
                savedIdentifier: savedTargetLanguageIdentifier,
                preferredLanguages: preferredLanguages
            ).maximalIdentifier,
            chatPartnerRelationship: chatPartnerRelationship,
            readRequestCount: 0
        )
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
/// 画面を開いて文字を読んだ時に、前に読んだ同じ相手のスクリーンショットで選ばれていた言語と関係を既定として選ぶ (addScreenshotReadingChoice)。
/// 言語か関係を選び直すと、選んだものを端末に保存して読み取りをやり直す。選択は端末の保存 (UserDefaults) だけを正として読み書きする
struct ChatReadingView: View {
    /// 読んでいるスクリーンショット。開発者メニューのあるビルドで撮影日時を出すのに使う。開発者メニューの見本から開いた時は nil
    let screenshot: PHAsset?
    /// 画像に写っている文字を行ごとに読む処理 (本物は recognizeTextLines(screenshot:))。画面を開いて最初の読み取りで 1 度だけ呼び、
    /// 読めなかった時は読み直しを頼んだ時にもう一度呼ぶ
    let recognizeTextLines: @MainActor () async throws -> [RecognizedTextLine]
    /// 読み取りの処理。読んだ行を受け取り、発言ごとの翻訳と返信案を返す。訳す先の言語と相手との関係は、処理の中で端末に保存してある選択を読む
    /// (本物は readChat(lines:)。開発者メニューは見本の読み取り結果を返す処理を渡す)
    let readChatContent: @MainActor (_ lines: [RecognizedTextLine]) async throws -> (messages: [TranslatedMessage], replySuggestions: [ReplySuggestion])
    /// 画面の状態
    @State private var phase = ChatReadingPhase.reading
    /// 画面を開いてから読んだ文字の行。まだ読んでいない時と、読めなかった時は nil
    @State private var recognizedLines: [RecognizedTextLine]?
    /// この画面の読み取りを残した記録 (ScreenshotReadingChoice) の id。利用者が選び直した時に、この記録の言語と関係を書き換える。
    /// まだ文字を読んでいない時と、記録を残せなかった時は nil
    @State private var screenshotReadingChoiceID: UUID?
    /// この画面で利用者が言語か関係を選び直したか。選び直した後に文字を読み終えた時は、過去の記録の選択で上書きしないために使う
    @State private var hasUserChangedChoice = false
    /// 言語のダウンロードをシステムに頼むための設定。利用者がダウンロードを選ぶまでは nil
    @State private var languageDownloadConfiguration: TranslationSession.Configuration?
    /// 端末に保存してある、訳す先として選んだ言語の maximalIdentifier。選択の正は端末の保存だけに置き、画面に写しを持たない
    /// (写しを持つと、画面を開き直した時に古い写しで保存を上書きするため)
    // 既定の空文字は未選択 (targetLanguage(savedIdentifier:preferredLanguages:) が空文字を端末の言語として扱う)。
    // 画面を開いただけでは書かず、利用者が欄で選んだ時と、前に読んだ同じ相手の選択を既定にした時だけ書くため、
    // どちらも無いまま後で端末の言語を変えると訳す先も変わる
    @AppStorage(selectedTargetLanguageUserDefaultsKey) private var savedTargetLanguageIdentifier = ""
    /// 端末に保存してある、選んだ相手との関係。nil は未選択。選択の正は端末の保存だけに置く
    @AppStorage(selectedChatPartnerRelationshipUserDefaultsKey) private var chatPartnerRelationship: ChatPartnerRelationship?
    /// Translation が端末で訳せる言語。読み出すまでは空
    @State private var supportedLanguages: [Locale.Language] = []
    /// 読み直しを頼んだ回数 (「もう一度試す」と、言語のダウンロードが終わった時に増やす)。
    /// 読み取りを 1 つの .task(id:) だけから始めるために使い、新しい読み取りが前の読み取りを取りやめるようにする
    @State private var readRequestCount = 0

    /// 訳す先として選ばれている言語の maximalIdentifier (保存してある選択。無ければ端末の言語)
    private var targetLanguageIdentifier: String {
        targetLanguage(savedIdentifier: savedTargetLanguageIdentifier, preferredLanguages: Locale.preferredLanguages).maximalIdentifier
    }
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
                    // 表示は保存してある選択 (無ければ端末の言語) で、利用者が選んだ時だけ保存する
                    Picker(
                        selection: Binding(
                            get: { targetLanguageIdentifier },
                            set: {
                                savedTargetLanguageIdentifier = $0
                                recordUserChoice()
                            }
                        )
                    ) {
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
                    Picker(
                        selection: Binding(
                            get: { chatPartnerRelationship },
                            set: {
                                chatPartnerRelationship = $0
                                recordUserChoice()
                            }
                        )
                    ) {
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
            supportedLanguages = await translationSupportedLanguages()
        }
        // 最初に開いた時、言語か関係を選び直した時、読み直しを頼んだ時に読み取る。どの時も、途中の前の読み取りを取りやめて読み直す
        .task(
            id: chatReadingTaskID(
                targetLanguageIdentifier: targetLanguageIdentifier,
                chatPartnerRelationship: chatPartnerRelationship,
                readRequestCount: readRequestCount
            )
        ) {
            phase = .reading
            guard let lines = await linesForReading() else {
                return
            }
            if let readPhase = await chatReadingPhaseUnlessCancelled(read: { try await readChatContent(lines) }) {
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

    /// この画面の読み取りに使う文字の行を返す。画面を開いて最初の 1 回だけ文字を読み、読み取りを記録して、
    /// 前に読んだ同じ相手のスクリーンショットで選ばれていた言語と関係を既定として選ぶ (この画面で利用者が既に選び直していた時は選ばない)。
    /// 既定を選んで、読み取りのタスクの id (chatReadingTaskID) が変わった時 (.task(id:) がその選択で読み取りを始め直すため) と、読んでいる途中で取りやめられた時は nil を返す。
    /// 文字を読めなかった時は、画面を失敗の状態にして nil を返す
    private func linesForReading() async -> [RecognizedTextLine]? {
        if let recognizedLines {
            return recognizedLines
        }
        let lines: [RecognizedTextLine]
        do {
            lines = try await recognizeTextLines()
        } catch {
            if let failedPhase = await chatReadingPhaseUnlessCancelled(read: { throw error }) {
                phase = failedPhase
            }
            return nil
        }
        guard !Task.isCancelled else {
            return nil
        }
        recognizedLines = lines
        let reading = recordScreenshotReading(
            lines: lines,
            savedTargetLanguageIdentifier: savedTargetLanguageIdentifier,
            chatPartnerRelationship: chatPartnerRelationship,
            hasUserChangedChoice: hasUserChangedChoice,
            preferredLanguages: Locale.preferredLanguages,
            id: UUID(),
            now: Date(),
            fileURL: screenshotReadingChoicesFileURL()
        )
        guard let defaultChoice = reading.choice else {
            return lines
        }
        screenshotReadingChoiceID = defaultChoice.id
        // 保存の書き方が違うだけで訳す先の言語が同じ時 (記録は未選択で、今は端末の言語と同じ言語を選んでいる等) も、記録のとおりに書き換える。
        // 空文字: 記録で何も選んでいなかった (nil) 時は、この保存の「未選択」(端末の言語へ訳す) の書き方に戻すため
        savedTargetLanguageIdentifier = defaultChoice.targetLanguageIdentifier ?? ""
        chatPartnerRelationship = defaultChoice.chatPartnerRelationship
        return reading.restartsReading ? nil : lines
    }

    /// 利用者が言語か関係を選び直したことを覚え、この画面の読み取りの記録の言語と関係を、選び直したものに書き換える
    /// (次に同じ相手のスクリーンショットを読んだ時の既定にするため)。まだ文字を読んでいない時は、読み終えた時に今の選択で記録する
    private func recordUserChoice() {
        hasUserChangedChoice = true
        guard let screenshotReadingChoiceID, let fileURL = screenshotReadingChoicesFileURL() else {
            return
        }
        // 書き換えられない時は、次に同じ相手を読んだ時の既定が前の選択のままになるだけで、この画面の読み取りには関わらないため、読み取りを止めない
        try? updateScreenshotReadingChoice(
            id: screenshotReadingChoiceID,
            targetLanguageIdentifier: recordedTargetLanguageIdentifier(savedIdentifier: savedTargetLanguageIdentifier),
            chatPartnerRelationship: chatPartnerRelationship,
            now: Date(),
            fileURL: fileURL
        )
    }

    #if DEBUG
    /// 開発者メニューのあるビルドでだけ画面の上に出す、読んでいる 1 枚の撮影日時と、タップしてからこの画面が出るまでの時間
    private var debugReadingInfo: some View {
        // 2pt: 開発者向けの 2 行を 1 つのまとまりとして詰めて出し、読み取りの画面の本文を押し下げる量を小さくするため
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: debugReadingScreenshotText(creationDate: screenshot?.creationDate))
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
