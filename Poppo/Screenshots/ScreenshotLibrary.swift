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

/// スクリーンショットの一覧に並べる、写真ライブラリの項目の種類の組。利用者が絞り込みの画面で選ぶ
nonisolated struct PhotoLibraryMediaKinds: OptionSet, Hashable {
    /// 種類ごとのビットの組。端末に保存するため、各種類のビットの位置は変えない
    let rawValue: Int

    /// スクリーンショットの種別を持つ画像
    static let screenshots = PhotoLibraryMediaKinds(rawValue: 1 << 0)
    /// スクリーンショットの種別を持たない画像 (保存したチャットの画像・切り抜いた画像・カメラの写真)
    static let otherPhotos = PhotoLibraryMediaKinds(rawValue: 1 << 1)
    /// 画面収録の種別を持つ動画
    static let screenRecordings = PhotoLibraryMediaKinds(rawValue: 1 << 2)
    /// 画面収録の種別を持たない動画
    static let otherVideos = PhotoLibraryMediaKinds(rawValue: 1 << 3)
}

/// スクリーンショットの一覧に並べる種類の組 (PhotoLibraryMediaKinds) の選択を保存する、UserDefaults のキー
let listedPhotoLibraryMediaKindsUserDefaultsKey = "listedPhotoLibraryMediaKinds"

/// 絞り込みの画面で、種類 (mediaKind) を選ぶ・外す (isOn) 操作をした後の種類の組を返す。current は操作の前の組。
/// 外すと組が空になる時は current のまま返す (何も並ばない一覧にしないため)
nonisolated func toggledPhotoLibraryMediaKinds(
    current: PhotoLibraryMediaKinds,
    mediaKind: PhotoLibraryMediaKinds,
    isOn: Bool
) -> PhotoLibraryMediaKinds {
    let toggled = isOn ? current.union(mediaKind) : current.subtracting(mediaKind)
    return toggled.isEmpty ? current : toggled
}

/// 写真ライブラリから、直近の項目を新しい順に limit 件まで取る。mediaKinds は並べる種類の組。
/// 写真へのアクセスが許可されている時に呼ぶ
func fetchRecentScreenshots(limit: Int, mediaKinds: PhotoLibraryMediaKinds) -> [PHAsset] {
    let fetchResult = PHAsset.fetchAssets(with: recentScreenshotFetchOptions(limit: limit, mediaKinds: mediaKinds))
    // PHFetchResult は項目を読む時に読み出すため、limit 件に達した所で読むのをやめる
    return listedPhotoLibraryItems(
        items: (0..<fetchResult.count).lazy.map { fetchResult.object(at: $0) },
        limit: limit,
        mediaKinds: mediaKinds,
        mediaKind: { photoLibraryMediaKind(mediaType: $0.mediaType, mediaSubtypes: $0.mediaSubtypes) }
    )
}

/// 新しい順の項目 (items) から、種類 (mediaKind で求める) が mediaKinds に入っているものを、先頭から limit 件まで返す。
/// 問い合わせの述語 (photoLibraryMediaKindsPredicate) が選んだ項目から、述語では絞れない種類を除くために使う
nonisolated func listedPhotoLibraryItems<Item>(
    items: some Sequence<Item>,
    limit: Int,
    mediaKinds: PhotoLibraryMediaKinds,
    mediaKind: (Item) -> PhotoLibraryMediaKinds?
) -> [Item] {
    Array(items.lazy.filter { mediaKind($0).map { mediaKinds.contains($0) } ?? false }.prefix(limit))
}

/// 写真ライブラリの項目 (mediaType と mediaSubtypes) が当たる種類を返す。画像と動画のどちらでもない (音声等) 時は nil
nonisolated func photoLibraryMediaKind(mediaType: PHAssetMediaType, mediaSubtypes: PHAssetMediaSubtype) -> PhotoLibraryMediaKinds? {
    switch mediaType {
    case .image:
        mediaSubtypes.contains(.photoScreenshot) ? .screenshots : .otherPhotos
    case .video:
        mediaSubtypes.contains(.videoScreenRecording) ? .screenRecordings : .otherVideos
    default:
        nil
    }
}

/// 写真ライブラリへの問い合わせの条件。mediaKinds の種類に当たる項目を含む項目を、撮った日時の新しい順に取る。
/// 述語が mediaKinds の種類だけを選べる時は limit 件までに限り、選べない時 (photoLibraryMediaKindsPredicate の「ほか」の種類) は限らない
/// (述語が選んだ項目から、呼び出し側が種類で除いた後に limit 件を残すため)
func recentScreenshotFetchOptions(limit: Int, mediaKinds: PhotoLibraryMediaKinds) -> PHFetchOptions {
    let options = PHFetchOptions()
    options.predicate = photoLibraryMediaKindsPredicate(mediaKinds: mediaKinds)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    if photoLibraryMediaKindsPredicateIsExact(mediaKinds: mediaKinds) {
        options.fetchLimit = limit
    }
    return options
}

/// photoLibraryMediaKindsPredicate が、mediaKinds の種類の項目だけを選ぶか (ほかの種類の項目を含めないか) を返す。
/// 「ほかの写真」か「ほかの動画」を、同じ画像・動画のもう一方の種類を選ばずに選んだ時は、述語がその画像・動画のすべてを選ぶため false
nonisolated func photoLibraryMediaKindsPredicateIsExact(mediaKinds: PhotoLibraryMediaKinds) -> Bool {
    !(mediaKinds.contains(.otherPhotos) && !mediaKinds.contains(.screenshots))
        && !(mediaKinds.contains(.otherVideos) && !mediaKinds.contains(.screenRecordings))
}

/// 種類の組 mediaKinds に当たる項目を含む項目を選ぶ、写真ライブラリへの問い合わせの述語。画像と動画の述語を OR でつなぐ。
/// 片方だけの時は OR でつながずにその述語を返す (スクリーンショットだけの時に、種類の組を足す前と同じ述語で問い合わせるため)
nonisolated func photoLibraryMediaKindsPredicate(mediaKinds: PhotoLibraryMediaKinds) -> NSPredicate {
    let subpredicates = [
        mediaTypePredicate(
            mediaType: .image,
            mediaSubtype: .photoScreenshot,
            includesSubtype: mediaKinds.contains(.screenshots),
            includesOthers: mediaKinds.contains(.otherPhotos)
        ),
        mediaTypePredicate(
            mediaType: .video,
            mediaSubtype: .videoScreenRecording,
            includesSubtype: mediaKinds.contains(.screenRecordings),
            includesOthers: mediaKinds.contains(.otherVideos)
        ),
    ].compactMap { $0 }
    return subpredicates.count == 1 ? subpredicates[0] : NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
}

/// mediaType の項目のうち、種別 mediaSubtype を持つもの (includesSubtype) と持たないもの (includesOthers) を含む項目を選ぶ述語。
/// 持たないものだけを選ぶ時も種別を見ずに mediaType のすべてを選ぶ。写真ライブラリは「種別を持たない」の述語
/// (`(mediaSubtypes & %d) == 0`) で 1 件も返さなかったため (2026-11-27 に iOS 27.2 の simulator で、種別を持たない動画が
/// この述語では並ばず、mediaType だけの述語では並んだ。https://github.com/bannzai/poppo/pull/71 )。持つものを除くのは呼び出し側が行う。
/// どちらも選ばない時は nil
nonisolated private func mediaTypePredicate(
    mediaType: PHAssetMediaType,
    mediaSubtype: PHAssetMediaSubtype,
    includesSubtype: Bool,
    includesOthers: Bool
) -> NSPredicate? {
    switch (includesSubtype, includesOthers) {
    case (true, true), (false, true):
        NSPredicate(format: "mediaType == %d", mediaType.rawValue)
    case (true, false):
        NSPredicate(format: "mediaType == %d AND (mediaSubtypes & %d) != 0", mediaType.rawValue, mediaSubtype.rawValue)
    case (false, false):
        nil
    }
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

/// セルが画面に出た時の初めの読み出しの結果を、読み出しを待った後の今の状態 (currentThumbnailState) に書いてよいかを返す。
/// isDownloadRequested は、読み出しを始めた時に利用者がその 1 枚のダウンロードのボタンを押していたか (true の時は取っている状態から読み出した)。
/// 読み出しを始めた時の状態のままの時だけ true にする。待っている間に利用者がダウンロードのボタンを押して取り始めた時は、
/// iCloud から取らずに読み出した結果 (ダウンロードのボタンを出す状態) で、取っている表示を上書きしないため
func canApplyInitialScreenshotThumbnailState(
    currentThumbnailState: ScreenshotThumbnailState,
    isDownloadRequested: Bool
) -> Bool {
    switch currentThumbnailState {
    case .loading:
        !isDownloadRequested
    case .downloading:
        isDownloadRequested
    case .loaded, .needsDownload, .downloadFailed, .unavailable:
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
