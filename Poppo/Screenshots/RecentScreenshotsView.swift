import Photos
import SwiftUI

/// 直近に撮ったスクリーンショットを新しい順に並べ、読み取る 1 枚を選ばせる画面。
/// 写真へのアクセスが許可されていない時は、許可を求める導線を出す
struct RecentScreenshotsView: View {
    /// 本体アプリが前面にいるか。前面に戻った時にスクリーンショットを取り直すために見る
    @Environment(\.scenePhase) private var scenePhase
    /// 設定アプリの、本体アプリの許可の画面を開くために使う
    @Environment(\.openURL) private var openURL
    /// 写真へのアクセスの許可の状態
    @State private var authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// 並べる写真。新しい順。showsOnlyScreenshots が true の時はスクリーンショットだけ、false の時は動画を除く写真のすべて
    @State private var screenshots: [PHAsset] = []
    /// スクリーンショットだけを並べるか (false は動画を除く写真のすべて)。端末に保存し、次に開いた時も同じにする。
    // 既定の true: 切り替えを足す前と同じ一覧 (スクリーンショットだけ) から始めるため (https://github.com/bannzai/poppo/issues/66 )
    @AppStorage(showsOnlyScreenshotsUserDefaultsKey) private var showsOnlyScreenshots = true

    var body: some View {
        Group {
            switch screenshotAccess(authorizationStatus: authorizationStatus) {
            case .notRequested:
                ContentUnavailableView {
                    // ja: スクリーンショットを選んで翻訳
                    Label("Pick a screenshot to translate", systemImage: "photo.on.rectangle")
                } description: {
                    // ja: 写真へのアクセスを許可すると直近のスクリーンショットがここに並びます
                    Text("Allow photo access to see your recent screenshots here")
                } actions: {
                    Button {
                        Task {
                            authorizationStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                            loadScreenshots()
                        }
                    } label: {
                        // ja: 写真へのアクセスを許可
                        Text("Allow photo access")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("photo_access_request_button")
                }
            case .denied:
                ContentUnavailableView {
                    // ja: 写真へのアクセスがオフになっています
                    Label("Photo access is turned off", systemImage: "photo.on.rectangle")
                } description: {
                    // ja: 設定で写真へのアクセスをオンにすると直近のスクリーンショットがここに並びます
                    Text("Turn on photo access in Settings to see your recent screenshots here")
                } actions: {
                    openSettingsButton
                }
            case .allowed:
                // 0: 切り替えの行の上下の余白は切り替え自身が持つため、切り替えと一覧の間に余白を足さない (選んだ写真だけの時の VStack と同じ)
                VStack(spacing: 0) {
                    showsOnlyScreenshotsToggle
                    if screenshots.isEmpty {
                        ContentUnavailableView {
                            if showsOnlyScreenshots {
                                // ja: スクリーンショットがまだありません
                                Label("No screenshots yet", systemImage: "photo.on.rectangle")
                            } else {
                                // ja: 写真がまだありません
                                Label("No photos yet", systemImage: "photo.on.rectangle")
                            }
                        } description: {
                            if showsOnlyScreenshots {
                                // ja: チャットのスクリーンショットを撮ってからこのアプリを開き直してください
                                Text("Take a screenshot of a chat and open this app again")
                            } else {
                                // ja: チャットの画像を写真に保存してからこのアプリを開き直してください
                                Text("Save a chat image to Photos and open this app again")
                            }
                        }
                    } else {
                        screenshotGrid
                    }
                }
            case .limited:
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        // ja: 選んだ写真だけを表示しています
                        Text("Only the photos you selected are shown")
                            .font(.subheadline.bold())
                        Group {
                            if showsOnlyScreenshots {
                                // ja: 新しく撮ったスクリーンショットを並べるには設定ですべての写真へのアクセスを許可してください
                                Text("Allow access to all photos in Settings to see new screenshots")
                            } else {
                                // ja: 新しく保存した写真を並べるには設定ですべての写真へのアクセスを許可してください
                                Text("Allow access to all photos in Settings to see new photos")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        openSettingsButton
                    }
                    .padding()
                    showsOnlyScreenshotsToggle
                    if screenshots.isEmpty {
                        Spacer()
                    } else {
                        screenshotGrid
                    }
                }
            }
        }
        .onChange(of: showsOnlyScreenshots) {
            loadScreenshots()
        }
        // 利用者がスクリーンショットを撮ってから本体アプリへ戻った時に、撮ったばかりの 1 枚を並べるため、前面に戻るたびに取り直す
        .onChange(of: scenePhase, initial: true) { _, newScenePhase in
            guard newScenePhase == .active else {
                return
            }
            authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            loadScreenshots()
        }
    }

    /// screenshots を並べた一覧。縮小画像は写真ライブラリから読み出す
    private var screenshotGrid: some View {
        ScreenshotGrid(
            title: recentScreenshotsTitle(showsOnlyScreenshots: showsOnlyScreenshots),
            screenshots: screenshots,
            loadThumbnailImage: { asset, isNetworkAccessAllowed, progressHandler in
                await loadScreenshotThumbnailImage(
                    asset: asset,
                    isNetworkAccessAllowed: isNetworkAccessAllowed,
                    progressHandler: progressHandler
                )
            }
        )
    }

    /// 一覧の上に置く、スクリーンショットだけを並べるかの切り替え。一覧が空の時も出す (スクリーンショットが無くても写真のすべてへ切り替えられるように)
    private var showsOnlyScreenshotsToggle: some View {
        Toggle(isOn: $showsOnlyScreenshots) {
            // ja: スクリーンショットだけ
            Text("Screenshots only")
        }
        .padding(.horizontal)
        // 8pt: 切り替えの行の上下を、下の一覧の見出しとの間より詰めて、切り替えを一覧の上の操作として近くに置くため
        .padding(.vertical, 8)
        .accessibilityIdentifier("shows_only_screenshots_toggle")
    }

    /// 設定アプリの、本体アプリの画面を開くボタン。利用者が写真へのアクセスの許可を変えられるように出す
    @ViewBuilder private var openSettingsButton: some View {
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            Button {
                openURL(settingsURL)
            } label: {
                // ja: 設定を開く
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("photo_access_open_settings_button")
        }
    }

    /// 写真へのアクセスが許可されている時 (選んだ写真だけの許可を含む) に、直近の写真 (showsOnlyScreenshots が true の時はスクリーンショットだけ) を取り直す。
    /// 許可を選ぶ前には取らない。許可が要る操作を初めて行うとシステムが許可の確認を出すため、利用者が許可の導線を押す前に確認を出さない
    /// (Apple の文書: 「The first time your app performs an operation that requires authorization, the system automatically and
    /// asynchronously prompts the user for it.」
    /// https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app )
    private func loadScreenshots() {
        switch screenshotAccess(authorizationStatus: authorizationStatus) {
        case .allowed, .limited:
            screenshots = fetchRecentScreenshots(limit: recentScreenshotsLimit, showsOnlyScreenshots: showsOnlyScreenshots)
        case .notRequested, .denied:
            return
        }
    }
}

/// 直近のスクリーンショットの一覧に並べる枚数の上限。
/// 30: 3 列で 10 行ぶん。直近のものをすぐ選ぶための画面で、古いスクリーンショットを探す用途は持たないため
nonisolated let recentScreenshotsLimit = 30

/// スクリーンショットの一覧のセルどうしの間隔 (列と行で揃える)。8pt は、3 列でも縮小画像から何の画面かが分かる幅を残しつつ、隣のセルと見分けられる間にするため
let screenshotGridSpacing: CGFloat = 8

/// スクリーンショットの一覧の列。3 列は、iPhone の幅で縮小画像から何の画面かが分かる大きさにするため
let screenshotGridColumns = Array(repeating: GridItem(.flexible(), spacing: screenshotGridSpacing), count: 3)

/// 一覧の縮小画像の枠の形。見た目を切る形とタップを受ける形を同じにするため 1 か所に置く。角丸 8pt はセルの間隔と揃える
let screenshotThumbnailShape = RoundedRectangle(cornerRadius: screenshotGridSpacing)

/// 一覧の見出し。showsOnlyScreenshots はスクリーンショットだけを並べているか (false は写真のすべて)
func recentScreenshotsTitle(showsOnlyScreenshots: Bool) -> LocalizedStringResource {
    if showsOnlyScreenshots {
        // ja: 直近のスクリーンショット
        "Recent screenshots"
    } else {
        // ja: 直近の写真
        "Recent photos"
    }
}

/// 写真 (スクリーンショットか、動画を除く写真のすべて) を 3 列に並べた一覧。1 枚を選ぶと、その読み取りの画面へ進む。
/// iCloud にだけあること以外の理由で縮小画像を読み出せなかった写真は並べない
struct ScreenshotGrid: View {
    /// 一覧の見出し
    let title: LocalizedStringResource
    /// 並べる写真。渡した順に左上から並べる
    let screenshots: [PHAsset]
    /// 一覧の 1 枚を縮小画像の大きさで読み出す処理。asset は読み出す 1 枚、isNetworkAccessAllowed は iCloud から取ってよいか、
    /// progressHandler は iCloud から取っている間の進み具合 (0〜1) を受け取る (main actor の外から呼ばれる)。
    /// 本物は loadScreenshotThumbnailImage(asset:isNetworkAccessAllowed:progressHandler:)。開発者メニューは iCloud にだけある見本を作る処理を渡す
    let loadThumbnailImage:
        (
            _ asset: PHAsset,
            _ isNetworkAccessAllowed: Bool,
            _ progressHandler: @escaping @Sendable (_ fractionCompleted: Double) -> Void
        ) async -> Result<UIImage, ScreenshotImageUnavailableReason>
    /// 本体アプリが前面にいるか。前面に戻った時に、一覧から外した写真を読み出し直すために見る
    @Environment(\.scenePhase) private var scenePhase
    /// 縮小画像を読み出せないと分かった写真の localIdentifier。セルが画面の外に出て作り直されても並べないように、一覧の側で持つ
    @State private var unavailableScreenshotIdentifiers: Set<String> = []
    /// 利用者がダウンロードのボタンを押した写真の localIdentifier。セルが画面の外に出て作り直された時に、
    /// ボタンを出し直さずに iCloud から取ってよい写真として読み出し直すため、一覧の側で持つ
    @State private var downloadRequestedScreenshotIdentifiers: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                LazyVGrid(columns: screenshotGridColumns, spacing: screenshotGridSpacing) {
                    ForEach(
                        listedScreenshots(
                            screenshots: screenshots,
                            localIdentifier: \.localIdentifier,
                            unavailableScreenshotIdentifiers: unavailableScreenshotIdentifiers
                        ),
                        id: \.localIdentifier
                    ) { screenshot in
                        ScreenshotGridCell(
                            screenshot: screenshot,
                            isDownloadRequested: downloadRequestedScreenshotIdentifiers.contains(screenshot.localIdentifier),
                            loadThumbnailImage: loadThumbnailImage,
                            markUnavailable: {
                                unavailableScreenshotIdentifiers.insert(screenshot.localIdentifier)
                            },
                            markDownloadRequested: {
                                downloadRequestedScreenshotIdentifiers.insert(screenshot.localIdentifier)
                            }
                        )
                    }
                }
            }
            .padding()
        }
        // 読み出せなかった理由が後で無くなるかは確かめていないため、本体アプリが前面に戻るたびに一覧から外した写真の控えを空にして読み出し直す
        // (RecentScreenshotsView が写真を取り直すのと同じ時点)
        .onChange(of: scenePhase) { _, newScenePhase in
            if newScenePhase == .active {
                unavailableScreenshotIdentifiers = []
            }
        }
    }
}

/// 一覧の 1 枚のセル。縮小画像を読み出せた時はタップで読み取りの画面へ進み、iCloud にだけある時はダウンロードのボタンを出す
struct ScreenshotGridCell: View {
    /// 表示する写真 (スクリーンショットか、動画を除く写真のどれか)
    let screenshot: PHAsset
    /// 利用者がこの 1 枚のダウンロードのボタンを押したか (ScreenshotGrid が持つ。セルが作り直されても残る)
    let isDownloadRequested: Bool
    /// 縮小画像を読み出す処理 (ScreenshotGrid の loadThumbnailImage をそのまま受け取る)
    let loadThumbnailImage:
        (
            _ asset: PHAsset,
            _ isNetworkAccessAllowed: Bool,
            _ progressHandler: @escaping @Sendable (_ fractionCompleted: Double) -> Void
        ) async -> Result<UIImage, ScreenshotImageUnavailableReason>
    /// iCloud にだけあること以外の理由で読み出せなかった時に呼ぶ。一覧からこの 1 枚を外す
    let markUnavailable: () -> Void
    /// 利用者がダウンロードのボタンを押した時に呼ぶ。この 1 枚を、iCloud から取ってよい写真として ScreenshotGrid に控える
    let markDownloadRequested: () -> Void
    /// 縮小画像の状態
    @State private var thumbnailState = ScreenshotThumbnailState.loading

    var body: some View {
        Group {
            if case .loaded = thumbnailState {
                NavigationLink {
                    ChatReadingView(
                        screenshot: screenshot,
                        recognizeTextLines: { try await recognizeTextLines(screenshot: screenshot) },
                        readChatContent: { try await readChat(lines: $0) }
                    )
                } label: {
                    ScreenshotThumbnailFrame(thumbnailState: thumbnailState, download: {})
                }
                .buttonStyle(.plain)
                #if DEBUG
                // タップしてから読み取りの画面が出るまでの時間を開発者メニューのあるビルドで測るため、タップした時刻を控える。
                // 同時に認識させるジェスチャーで、NavigationLink の遷移とタップを受ける範囲は変えない
                .simultaneousGesture(
                    TapGesture().onEnded {
                        debugLastScreenshotTapUptime = ProcessInfo.processInfo.systemUptime
                    }
                )
                #endif
                .accessibilityLabel(
                    screenshot.creationDate.map {
                        Text($0, format: Date.FormatStyle(date: .abbreviated, time: .shortened))
                    }
                        // ja: スクリーンショット
                        ?? Text("Screenshot")
                )
            } else {
                ScreenshotThumbnailFrame(
                    thumbnailState: thumbnailState,
                    download: {
                        Task {
                            await download()
                        }
                    }
                )
            }
        }
        .task(id: screenshot.localIdentifier) {
            // セルが画面に出直すたびに task は動き直す。読み出した後と取っている間に動き直した時は、その表示を読み出す前の結果で上書きしない
            guard case .loading = thumbnailState else {
                return
            }
            // 一覧を開いただけでは iCloud と通信しないため、利用者がこの 1 枚のダウンロードのボタンを押していない時は iCloud から取らずに読み出す。
            // 押した後にセルが作り直された時は、ボタンを出し直さずに iCloud から取り直す
            if isDownloadRequested {
                // 0: 取り直しを始めた直後は進み具合が伝わる前のため、何も進んでいない値から出す
                thumbnailState = .downloading(fractionCompleted: 0)
            }
            let loadedThumbnailState = await screenshotThumbnailState(
                isNetworkAccessAllowed: isDownloadRequested,
                loadImage: loadThumbnail
            )
            // 待っている間に利用者がダウンロードのボタンを押して取り始めた時は、その表示を読み出す前の結果で上書きしない
            // (読み出しを待つ前に畳むと、待った後の状態を確かめられないため、結果を変数で受ける)。
            // task が取りやめられても結果は書く。写真ライブラリの読み出しは task の取りやめで止まらずに結果を返し、
            // 取りやめの後に画面に出直したセルの task は冒頭の guard で抜けるため、ここで書かないと取っている表示のまま止まる
            guard
                canApplyInitialScreenshotThumbnailState(
                    currentThumbnailState: thumbnailState,
                    isDownloadRequested: isDownloadRequested
                )
            else {
                return
            }
            thumbnailState = loadedThumbnailState
            if case .unavailable = thumbnailState {
                markUnavailable()
            }
        }
    }

    /// 利用者がダウンロードのボタンを押した時に、iCloud から取って縮小画像を出す。取れなかった時は理由を出す。
    /// ボタンを出していない状態 (取っている間・読み出せた後) で呼ばれた時は何もしない (続けて押した時に同じ 1 枚を 2 本並べて取らないため)
    private func download() async {
        guard canStartScreenshotDownload(thumbnailState: thumbnailState) else {
            return
        }
        markDownloadRequested()
        // 0: 押した直後は進み具合が伝わる前のため、何も進んでいない値から出す
        thumbnailState = .downloading(fractionCompleted: 0)
        thumbnailState = await screenshotThumbnailState(isNetworkAccessAllowed: true, loadImage: loadThumbnail)
    }

    /// この 1 枚の縮小画像を読み出す。iCloud から取っている間は、進み具合をセルの状態に写す
    private func loadThumbnail(isNetworkAccessAllowed: Bool) async -> Result<UIImage, ScreenshotImageUnavailableReason> {
        await loadThumbnailImage(screenshot, isNetworkAccessAllowed) { fractionCompleted in
            Task { @MainActor in
                // 取り終えた後に届いた進み具合で、縮小画像や失敗の表示を上書きしないため、取っている間だけ写す
                if case .downloading = thumbnailState {
                    thumbnailState = .downloading(fractionCompleted: fractionCompleted)
                }
            }
        }
    }
}

/// 一覧の 1 枚の枠。読み出す前は枠だけ、読み出せた時は縮小画像、iCloud にだけある時はダウンロードのボタン、
/// 取っている間は進み具合、取れなかった時は理由とダウンロードのボタンを出す
struct ScreenshotThumbnailFrame: View {
    /// 縮小画像の状態
    let thumbnailState: ScreenshotThumbnailState
    /// 利用者がダウンロードのボタンを押した時に呼ぶ
    let download: () -> Void

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            // 9:19.5 はホームボタンの無い iPhone の画面の縦横比。iPhone 専用で作るため (documents/DIRECTION.md「決めたこと」)、枠をこの比で取る
            .aspectRatio(9 / 19.5, contentMode: .fit)
            .overlay {
                switch thumbnailState {
                case .loaded(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .needsDownload:
                    ScreenshotDownloadButton(download: download)
                case .downloading(let fractionCompleted):
                    ProgressView(value: fractionCompleted) {
                        // ja: ダウンロード中
                        Text("Downloading")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    // 8pt: 進み具合の棒を枠の左右の端から離し、角の丸みで棒の端が切れないようにするため
                    .padding(8)
                    .accessibilityIdentifier("screenshot_downloading_progress")
                case .downloadFailed(let reason):
                    ScreenshotDownloadFailedLabel(reason: reason, download: download)
                case .loading, .unavailable:
                    EmptyView()
                }
            }
            .clipShape(screenshotThumbnailShape)
            // scaledToFill の画像は枠より横長の時に左右へはみ出し、clipShape は見た目だけを切るため、タップを受ける範囲が隣のセルまで広がる。
            // タップを受ける範囲を枠に揃える (simtunnel の simulator で、横長の 2 枚目が幅 558pt の範囲でタップを受け、1 枚目を押すと 2 枚目が開いた)
            .contentShape(screenshotThumbnailShape)
    }
}

/// iCloud にだけある 1 枚の枠に出す、iCloud から取るボタン
struct ScreenshotDownloadButton: View {
    /// 押した時に呼ぶ
    let download: () -> Void

    var body: some View {
        Button(action: download) {
            // 4pt: 幅 約 118pt の枠の中でアイコンと 2 行の文を詰めて収めるための、間隔の小さい値
            VStack(spacing: 4) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.title3)
                // ja: iCloud からダウンロード
                Text("Download from iCloud")
            }
            .font(.caption2)
            .multilineTextAlignment(.center)
            // 4pt: 幅 約 118pt の枠の中で、文が枠の端に触れない最小の余白にするため
            .padding(4)
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("screenshot_download_button")
    }
}

/// iCloud から取れなかった時の文。reason は取れなかった理由
nonisolated func screenshotDownloadFailedMessage(reason: ScreenshotImageUnavailableReason) -> LocalizedStringResource {
    switch reason {
    case .inCloudOnly:
        // ja: iCloud から取れませんでした
        "Couldn't get it from iCloud"
    case .cancelled:
        // ja: ダウンロードが取り消されました
        "Download was canceled"
    case .failed, .unknown:
        // ja: ダウンロードできませんでした
        "Couldn't download"
    }
}

/// iCloud から取れなかった 1 枚の枠に出す、取れなかった理由ともう一度取るボタン
struct ScreenshotDownloadFailedLabel: View {
    /// 取れなかった理由
    let reason: ScreenshotImageUnavailableReason
    /// もう一度取るボタンを押した時に呼ぶ
    let download: () -> Void

    var body: some View {
        // 4pt: 幅 約 118pt の枠の中でアイコンと理由の文とボタンを詰めて収めるための、間隔の小さい値
        VStack(spacing: 4) {
            Image(systemName: "exclamationmark.icloud")
                .font(.title3)
            Text(screenshotDownloadFailedMessage(reason: reason))
                .accessibilityIdentifier("screenshot_download_failed_message")
            #if DEBUG
            // 写真ライブラリが返したエラーのドメイン・コード・説明は、実機で取れない原因を開発者メニューのあるビルドで見分けるためだけに出す
            // (利用者の行動に効かないため、配布するビルドには出さない)
            if case .failed(let errorDescription) = reason {
                // 3 行: 幅 約 118pt の枠に、ドメインとコードと説明の始まりまでを収め、ボタンを枠の外へ押し出さないため
                Text(verbatim: errorDescription)
                    .lineLimit(3)
            }
            #endif
            ScreenshotDownloadButton(download: download)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // 4pt: 幅 約 118pt の枠の中で、文が枠の端に触れない最小の余白にするため
        .padding(4)
    }
}
