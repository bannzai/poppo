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

/// 写真ライブラリから、直近に撮ったスクリーンショットを新しい順に limit 枚まで取る。
/// 写真へのアクセスが許可されている時に呼ぶ
func fetchRecentScreenshots(limit: Int) -> [PHAsset] {
    let fetchResult = PHAsset.fetchAssets(with: .image, options: recentScreenshotFetchOptions(limit: limit))
    return fetchResult.objects(at: IndexSet(integersIn: 0..<fetchResult.count))
}

/// 写真ライブラリへの問い合わせの条件。スクリーンショットだけを、撮った日時の新しい順に、limit 枚まで取る
func recentScreenshotFetchOptions(limit: Int) -> PHFetchOptions {
    let options = PHFetchOptions()
    options.predicate = NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
    options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    options.fetchLimit = limit
    return options
}

/// 写真ライブラリの 1 枚を、targetSize に合わせた画像として読み出す。
/// 端末に無い画像 (iCloud にだけある) は取りに行かず、読み出せない時は nil を返す
@concurrent nonisolated func loadScreenshotImage(
    asset: PHAsset,
    targetSize: CGSize,
    contentMode: PHImageContentMode
) async -> UIImage? {
    let options = PHImageRequestOptions()
    // 結果を 1 回だけ受け取るため。既定の opportunistic は質の低い画像と本来の画像で resultHandler を複数回呼ぶことがあり、
    // continuation を 2 回 resume してしまう (PHImageManager.h: highQualityFormat は「client will get one result only」)
    options.deliveryMode = .highQualityFormat
    return await withCheckedContinuation { continuation in
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: contentMode,
            options: options
        ) { image, _ in
            continuation.resume(returning: image)
        }
    }
}
