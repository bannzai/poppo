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
    /// 並べるスクリーンショット。新しい順
    @State private var screenshots: [PHAsset] = []

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
                if screenshots.isEmpty {
                    ContentUnavailableView {
                        // ja: スクリーンショットがまだありません
                        Label("No screenshots yet", systemImage: "photo.on.rectangle")
                    } description: {
                        // ja: チャットのスクリーンショットを撮ってからこのアプリを開き直してください
                        Text("Take a screenshot of a chat and open this app again")
                    }
                } else {
                    ScreenshotGrid(screenshots: screenshots)
                }
            case .limited:
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        // ja: 選んだ写真だけを表示しています
                        Text("Only the photos you selected are shown")
                            .font(.subheadline.bold())
                        // ja: 新しく撮ったスクリーンショットを並べるには設定ですべての写真へのアクセスを許可してください
                        Text("Allow access to all photos in Settings to see new screenshots")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        openSettingsButton
                    }
                    .padding()
                    if screenshots.isEmpty {
                        Spacer()
                    } else {
                        ScreenshotGrid(screenshots: screenshots)
                    }
                }
            }
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

    /// 写真へのアクセスが許可されている時 (選んだ写真だけの許可を含む) に、直近のスクリーンショットを取り直す。
    /// 許可を選ぶ前には取らない。許可が要る操作を初めて行うとシステムが許可の確認を出すため、利用者が許可の導線を押す前に確認を出さない
    /// (Apple の文書: 「The first time your app performs an operation that requires authorization, the system automatically and
    /// asynchronously prompts the user for it.」
    /// https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app )
    private func loadScreenshots() {
        switch screenshotAccess(authorizationStatus: authorizationStatus) {
        case .allowed, .limited:
            // 30: 3 列で 10 行ぶん。直近のものをすぐ選ぶための画面で、古いスクリーンショットを探す用途は持たないため
            screenshots = fetchRecentScreenshots(limit: 30)
        case .notRequested, .denied:
            return
        }
    }
}

/// スクリーンショットを 3 列に並べた一覧。1 枚を選ぶと、その読み取りの画面へ進む
struct ScreenshotGrid: View {
    /// 並べるスクリーンショット。渡した順に左上から並べる
    let screenshots: [PHAsset]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // ja: 直近のスクリーンショット
                Text("Recent screenshots")
                    .font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(screenshots, id: \.localIdentifier) { screenshot in
                        NavigationLink {
                            ChatReadingView(screenshot: screenshot)
                        } label: {
                            ScreenshotThumbnail(screenshot: screenshot)
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
                    }
                }
            }
            .padding()
        }
    }
}

/// 一覧に並べるスクリーンショット 1 枚の縮小画像
struct ScreenshotThumbnail: View {
    /// 表示するスクリーンショット
    let screenshot: PHAsset
    /// 縮小画像を読み出した結果。読み出すまでは nil
    @State private var loadResult: Result<UIImage, ScreenshotImageUnavailableReason>?

    var body: some View {
        ScreenshotThumbnailFrame(loadResult: loadResult)
            .task(id: screenshot.localIdentifier) {
                // 幅 440・高さ 960: 3 列の一覧の 1 枚は画面の幅の約 1/3 で、幅 440pt・3 倍の解像度の機種で約 440px になるため
                loadResult = await loadScreenshotImage(
                    asset: screenshot,
                    targetSize: CGSize(width: 440, height: 960),
                    contentMode: .aspectFit
                )
            }
    }
}

/// 一覧の 1 枚の枠。読み出す前は枠だけ、読み出せた時は縮小画像、読み出せなかった時は読み出せないことを出す
struct ScreenshotThumbnailFrame: View {
    /// 縮小画像を読み出した結果。読み出す前は nil
    let loadResult: Result<UIImage, ScreenshotImageUnavailableReason>?

    var body: some View {
        Color(uiColor: .secondarySystemBackground)
            // 9:19.5 はホームボタンの無い iPhone の画面の縦横比。iPhone 専用で作るため (documents/DIRECTION.md「決めたこと」)、枠をこの比で取る
            .aspectRatio(9 / 19.5, contentMode: .fit)
            .overlay {
                switch loadResult {
                case .success(let image):
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                case .failure(let reason):
                    ScreenshotUnavailableLabel(reason: reason)
                case nil:
                    EmptyView()
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            // scaledToFill の画像は枠より横長の時に左右へはみ出し、clipShape は見た目だけを切るため、タップを受ける範囲が隣のセルまで広がる。
            // タップを受ける範囲を枠に揃える (simtunnel の simulator で、横長の 2 枚目が幅 558pt の範囲でタップを受け、1 枚目を押すと 2 枚目が開いた)
            .contentShape(.rect(cornerRadius: 8))
    }
}

/// 縮小画像を読み出せなかった時に枠の中に出す表示。端末に無い (iCloud にだけある) 時と、ほかの理由の時で文を分ける
struct ScreenshotUnavailableLabel: View {
    /// 読み出せなかった理由
    let reason: ScreenshotImageUnavailableReason

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: reason == .inCloudOnly ? "icloud.slash" : "exclamationmark.triangle")
                .font(.title3)
            if reason == .inCloudOnly {
                // ja: この iPhone にありません
                Text("Not on this iPhone")
            } else {
                // ja: 読み込めません
                Text("Couldn't load")
            }
            #if DEBUG
            // 実機で読み出せない原因を開発者メニューのあるビルドで見分けるため、写真ライブラリが返した理由をそのまま出す
            Text(verbatim: debugText(screenshotImageUnavailableReason: reason))
                .accessibilityIdentifier("debug_screenshot_unavailable_reason")
            #endif
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(4)
    }
}

#if DEBUG
/// 縮小画像を読み出せなかった理由を、開発者メニューのあるビルドで枠の中に出す文にして返す
func debugText(screenshotImageUnavailableReason: ScreenshotImageUnavailableReason) -> String {
    switch screenshotImageUnavailableReason {
    case .inCloudOnly:
        "iCloud にだけある"
    case .cancelled:
        "取り消された"
    case .failed(let errorDescription):
        errorDescription
    case .unknown:
        "理由なし"
    }
}
#endif
