import Photos
import UIKit

/// 写真へのアクセスの許可の状態から決まる、最初の画面の出し方
nonisolated enum ScreenshotAccess {
    /// 利用者がまだ許可を選んでいない。許可を求める導線を出す
    case notRequested
    /// すべての写真が許可されている。直近のスクリーンショットを並べる
    case allowed
    /// 利用者が選んだ写真だけが許可されている。選んだ中のスクリーンショットを並べる。
    /// 新しく撮ったスクリーンショットは選んだ写真に入らず並ばないため、すべての写真を許可する導線も出す
    case limited
    /// 許可されていない。設定アプリで許可する導線を出す
    case denied
}

/// 写真へのアクセスの許可の状態を、最初の画面の出し方に直す
nonisolated func screenshotAccess(authorizationStatus: PHAuthorizationStatus) -> ScreenshotAccess {
    switch authorizationStatus {
    case .notDetermined:
        return .notRequested
    case .authorized:
        return .allowed
    case .limited:
        return .limited
    case .denied, .restricted:
        return .denied
    @unknown default:
        return .denied
    }
}

/// スクリーンショットの一覧に、スクリーンショットだけを並べるか (false は動画を除く写真のすべて) の選択を保存する、UserDefaults のキー
let showsOnlyScreenshotsUserDefaultsKey = "showsOnlyScreenshots"

/// 写真ライブラリから、直近の画像を新しい順に limit 枚まで取る。showsOnlyScreenshots が true の時はスクリーンショットだけ、false の時は動画を除く写真のすべて。
/// 写真へのアクセスが許可されている時に呼ぶ
func fetchRecentScreenshots(limit: Int, showsOnlyScreenshots: Bool) -> [PHAsset] {
    let fetchResult = PHAsset.fetchAssets(with: recentScreenshotFetchOptions(limit: limit, showsOnlyScreenshots: showsOnlyScreenshots))
    return fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
}

/// 写真ライブラリへの問い合わせの条件。画像 (動画を除く) を、撮った日時の新しい順に、limit 枚まで取る。
/// showsOnlyScreenshots が true の時は、そのうちスクリーンショットの種別を持つものだけを取る
func recentScreenshotFetchOptions(limit: Int, showsOnlyScreenshots: Bool) -> PHFetchOptions {
    let options = PHFetchOptions()
    options.predicate =
        showsOnlyScreenshots
        ? NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue
        )
        : NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = limit
    return options
}

/// 写真ライブラリの 1 枚を読み出せなかった理由。PHImageManager が結果に添える info (PHImageManager.h の「Result's handler info dictionary keys」) から決める
nonisolated enum ScreenshotImageUnavailableReason: Error, Hashable {
    /// 端末に無く iCloud にだけある (PHImageResultIsInCloudKey)。iCloud から取るのは、利用者が一覧のダウンロードのボタンを押した時と、
    /// 読み取る 1 枚として選んだ時だけ (documents/DIRECTION.md「決めたこと」2026-11-27)
    case inCloudOnly
    /// 読み出しが取り消された (PHImageCancelledKey)
    case cancelled
    /// 写真ライブラリがエラーを返した (PHImageErrorKey)。errorDescription はそのエラーの説明
    case failed(errorDescription: String)
    /// info に理由が無いまま画像が返らなかった
    case unknown
}

/// 画像が返らなかった時の info から、読み出せなかった理由を返す。
/// iCloud にだけある時はエラーも添えられることがあるため、iCloud・取り消し・エラーの順に見る
nonisolated func screenshotImageUnavailableReason(info: [AnyHashable: Any]?) -> ScreenshotImageUnavailableReason {
    if (info?[PHImageResultIsInCloudKey] as? NSNumber)?.boolValue == true {
        return .inCloudOnly
    }
    if (info?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
        return .cancelled
    }
    if let error = info?[PHImageErrorKey] as? NSError {
        return .failed(errorDescription: "\(error.domain) \(error.code): \(error.localizedDescription)")
    }
    return .unknown
}

/// loadScreenshotImage が写真ライブラリへ渡す読み出しの条件。isNetworkAccessAllowed と progressHandler は loadScreenshotImage と同じ。
/// 結果は 1 回だけ返す (deliveryMode が highQualityFormat)
nonisolated func screenshotImageRequestOptions(
    isNetworkAccessAllowed: Bool,
    progressHandler: (@Sendable (_ fractionCompleted: Double) -> Void)?
) -> PHImageRequestOptions {
    let options = PHImageRequestOptions()
    // 結果を 1 回だけ受け取るため。既定の opportunistic は質の低い画像と本来の画像で resultHandler を複数回呼ぶことがあり、
    // continuation を 2 回 resume してしまう (PHImageManager.h: highQualityFormat は「client will get one result only」)
    options.deliveryMode = .highQualityFormat
    options.isNetworkAccessAllowed = isNetworkAccessAllowed
    // このクロージャは main actor の外 (この nonisolated の関数の中) で作る。写真ライブラリは進み具合を別のキューから伝えるため、
    // main actor に隔離したクロージャを渡すと実行時に止まる (createDebugSampleScreenshotAssets の変更のブロックと同じ理由)
    if let progressHandler {
        options.progressHandler = { fractionCompleted, _, _, _ in
            progressHandler(fractionCompleted)
        }
    }
    return options
}

/// 写真ライブラリの 1 枚を、targetSize に合わせた画像として読み出す。読み出せない時は、その理由を failure で返す。
/// isNetworkAccessAllowed が true の時だけ、端末に無い画像 (iCloud にだけある) を iCloud から取る
/// (Apple の文書: 「A Boolean value that specifies whether Photos can download the requested image from iCloud.」
/// https://developer.apple.com/documentation/photos/phimagerequestoptions/isnetworkaccessallowed )。
/// progressHandler は iCloud から取っている間の進み具合 (0〜1) を受け取る。写真ライブラリが main actor の外のキューから呼ぶ
@concurrent nonisolated func loadScreenshotImage(
    asset: PHAsset,
    targetSize: CGSize,
    contentMode: PHImageContentMode,
    isNetworkAccessAllowed: Bool,
    progressHandler: (@Sendable (_ fractionCompleted: Double) -> Void)?
) async -> Result<UIImage, ScreenshotImageUnavailableReason> {
    await withCheckedContinuation { continuation in
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: screenshotImageRequestOptions(isNetworkAccessAllowed: isNetworkAccessAllowed, progressHandler: progressHandler)
        ) { image, info in
            continuation.resume(returning: image.map { .success($0) } ?? .failure(screenshotImageUnavailableReason(info: info)))
        }
    }
}

/// 一覧の 1 枚 (asset) を、縮小画像の大きさで読み出す。isNetworkAccessAllowed と progressHandler は loadScreenshotImage と同じ
@concurrent nonisolated func loadScreenshotThumbnailImage(
    asset: PHAsset,
    isNetworkAccessAllowed: Bool,
    progressHandler: @escaping @Sendable (_ fractionCompleted: Double) -> Void
) async -> Result<UIImage, ScreenshotImageUnavailableReason> {
    // 幅 440・高さ 960: 3 列の一覧の 1 枚は画面の幅の約 1/3 で、幅 440pt・3 倍の解像度の機種で約 440px になるため
    await loadScreenshotImage(
        asset: asset,
        targetSize: CGSize(width: 440, height: 960),
        contentMode: .aspectFit,
        isNetworkAccessAllowed: isNetworkAccessAllowed,
        progressHandler: progressHandler
    )
}

/// 一覧の 1 枚の縮小画像の状態
enum ScreenshotThumbnailState {
    /// 読み出す前
    case loading
    /// 読み出せた。タップで読み取りの画面へ進める
    case loaded(image: UIImage)
    /// 端末に無く iCloud にだけある。ダウンロードのボタンを出す
    case needsDownload
    /// 利用者がダウンロードのボタンを押し、iCloud から取っている。fractionCompleted は進み具合 (0〜1)
    case downloading(fractionCompleted: Double)
    /// iCloud から取れなかった。reason はその理由で、セルに出し、ダウンロードのボタンをもう一度出す
    case downloadFailed(reason: ScreenshotImageUnavailableReason)
    /// iCloud にだけあること以外の理由で読み出せない。取る手段が無いため一覧に出さない
    case unavailable
}

/// 一覧の 1 枚を loadImage で読み出し、その結果から縮小画像の状態を返す。loadImage には isNetworkAccessAllowed をそのまま渡す。
/// isNetworkAccessAllowed は、利用者がダウンロードのボタンを押した時だけ true にする (一覧を開いただけでは iCloud と通信しないため)。
/// true で読み出せなかった時は理由を出す状態に、false で iCloud にだけあった時はダウンロードのボタンを出す状態に、false でほかの理由の時は一覧に出さない状態にする
func screenshotThumbnailState(
    isNetworkAccessAllowed: Bool,
    loadImage: (_ isNetworkAccessAllowed: Bool) async -> Result<UIImage, ScreenshotImageUnavailableReason>
) async -> ScreenshotThumbnailState {
    switch await loadImage(isNetworkAccessAllowed) {
    case .success(let image):
        .loaded(image: image)
    case .failure(let reason) where isNetworkAccessAllowed:
        .downloadFailed(reason: reason)
    case .failure(.inCloudOnly):
        .needsDownload
    case .failure:
        .unavailable
    }
}

/// 一覧の 1 枚の縮小画像の状態 (thumbnailState) で、ダウンロードのボタンを押して iCloud から取り始めてよいかを返す。
/// ボタンを出している状態 (iCloud にだけある・取れなかった) だけ true にする (取っている間や読み出せた後に続けて押されても、同じ 1 枚を 2 本並べて取らないため)
func canStartScreenshotDownload(thumbnailState: ScreenshotThumbnailState) -> Bool {
    switch thumbnailState {
    case .needsDownload, .downloadFailed:
        true
    case .loading, .loaded, .downloading, .unavailable:
        false
    }
}

/// 一覧に並べる写真 (screenshots) から、読み出せないと分かった写真 (localIdentifier が unavailableScreenshotIdentifiers にあるもの) を除いて返す。
/// 残りは渡した順のまま。localIdentifier は写真の localIdentifier を返す (テストで PHAsset を作らずに確かめるため、取り出し方を受け取る)
func listedScreenshots<Screenshot>(
    screenshots: [Screenshot],
    localIdentifier: (Screenshot) -> String,
    unavailableScreenshotIdentifiers: Set<String>
) -> [Screenshot] {
    screenshots.filter { !unavailableScreenshotIdentifiers.contains(localIdentifier($0)) }
}
