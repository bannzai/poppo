import Photos
import Testing
import UIKit

@testable import Poppo

/// 写真ライブラリの 1 枚を、述語が評価できる形 (PHAsset の mediaType と mediaSubtypes のキー) で返す
private func photoLibraryAssetValues(mediaType: PHAssetMediaType, mediaSubtypes: PHAssetMediaSubtype) -> [String: Any] {
    ["mediaType": mediaType.rawValue, "mediaSubtypes": mediaSubtypes.rawValue]
}

/// スクリーンショットだけを並べる時の問い合わせが、スクリーンショットの種別を持つ画像だけを選ぶこと。
/// スクリーンショットとほかの種別を併せ持つ画像は選び、ほかの種別だけの画像 (Live Photo・パノラマ)・種別の無い画像・動画は選ばない
@Test func recentScreenshotFetchOptionsSelectOnlyScreenshotsWhenShowingOnlyScreenshots() throws {
    let predicate = try #require(recentScreenshotFetchOptions(limit: 30, showsOnlyScreenshots: true).predicate)

    #expect(predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: .photoScreenshot)))
    #expect(predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: [.photoScreenshot, .photoHDR])))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: .photoLive)))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: .photoPanorama)))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: [])))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .video, mediaSubtypes: [])))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .video, mediaSubtypes: .videoHighFrameRate)))
}

/// 写真のすべてを並べる時の問い合わせが、種別を問わず画像を選び (スクリーンショット・Live Photo・種別の無い画像)、動画と音声は選ばないこと
@Test func recentScreenshotFetchOptionsSelectAllImagesWhenShowingAllPhotos() throws {
    let predicate = try #require(recentScreenshotFetchOptions(limit: 30, showsOnlyScreenshots: false).predicate)

    #expect(predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: .photoScreenshot)))
    #expect(predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: .photoLive)))
    #expect(predicate.evaluate(with: photoLibraryAssetValues(mediaType: .image, mediaSubtypes: [])))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .video, mediaSubtypes: [])))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .video, mediaSubtypes: .videoHighFrameRate)))
    #expect(!predicate.evaluate(with: photoLibraryAssetValues(mediaType: .audio, mediaSubtypes: [])))
}

/// 写真ライブラリへの問い合わせが、どちらの並べ方でも撮った日時の新しい順に並べること
@Test(arguments: [true, false]) func recentScreenshotFetchOptionsSortNewestFirst(showsOnlyScreenshots: Bool) {
    let options = recentScreenshotFetchOptions(limit: 30, showsOnlyScreenshots: showsOnlyScreenshots)

    #expect(options.sortDescriptors?.map(\.key) == ["creationDate"])
    #expect(options.sortDescriptors?.map(\.ascending) == [false])
}

/// 写真ライブラリへの問い合わせが、どちらの並べ方でも渡した枚数までに限ること (1 枚と 30 枚)
@Test(arguments: [true, false]) func recentScreenshotFetchOptionsLimitCount(showsOnlyScreenshots: Bool) {
    #expect(recentScreenshotFetchOptions(limit: 1, showsOnlyScreenshots: showsOnlyScreenshots).fetchLimit == 1)
    #expect(recentScreenshotFetchOptions(limit: 30, showsOnlyScreenshots: showsOnlyScreenshots).fetchLimit == 30)
}

/// 一覧の見出しは、スクリーンショットだけの時は「直近のスクリーンショット」、写真のすべての時は「直近の写真」にすること
@Test func recentScreenshotsTitleFollowsShowsOnlyScreenshots() {
    #expect(recentScreenshotsTitle(showsOnlyScreenshots: true).key == "Recent screenshots")
    #expect(recentScreenshotsTitle(showsOnlyScreenshots: false).key == "Recent photos")
}

/// 写真ライブラリの読み出しの代わりに screenshotThumbnailState へ渡す処理。渡された isNetworkAccessAllowed を控え、決めておいた結果を返す
@MainActor private final class ScreenshotImageLoaderSpy {
    /// loadImage に渡された isNetworkAccessAllowed。渡された順
    var requestedNetworkAccess: [Bool] = []
    /// loadImage が返す結果
    let result: Result<UIImage, ScreenshotImageUnavailableReason>

    // class は memberwise initializer を持たないため、返す結果を受け取る init を書く
    init(result: Result<UIImage, ScreenshotImageUnavailableReason>) {
        self.result = result
    }

    /// screenshotThumbnailState の loadImage に渡す処理。isNetworkAccessAllowed を控えて result を返す
    func loadImage(isNetworkAccessAllowed: Bool) async -> Result<UIImage, ScreenshotImageUnavailableReason> {
        requestedNetworkAccess.append(isNetworkAccessAllowed)
        return result
    }
}

/// 一覧を開いた時の読み出しは iCloud から取らず (isNetworkAccessAllowed は false)、読み出せた画像はそのまま縮小画像にすること
@MainActor @Test func screenshotThumbnailStateIsLoadedWithoutNetworkAccess() async {
    let image = UIImage()
    let loader = ScreenshotImageLoaderSpy(result: .success(image))

    let state = await screenshotThumbnailState(isNetworkAccessAllowed: false, loadImage: loader.loadImage)

    #expect(loader.requestedNetworkAccess == [false])
    guard case .loaded(let loadedImage) = state else {
        Issue.record("縮小画像の状態にならなかった: \(state)")
        return
    }
    #expect(loadedImage === image)
}

/// 一覧を開いた時に iCloud にだけあった画像は、一覧から外さずダウンロードのボタンを出す状態にすること
@MainActor @Test func screenshotThumbnailStateNeedsDownloadWhenInCloudOnly() async {
    let loader = ScreenshotImageLoaderSpy(result: .failure(.inCloudOnly))

    let state = await screenshotThumbnailState(isNetworkAccessAllowed: false, loadImage: loader.loadImage)

    #expect(loader.requestedNetworkAccess == [false])
    guard case .needsDownload = state else {
        Issue.record("ダウンロードのボタンを出す状態にならなかった: \(state)")
        return
    }
}

/// iCloud にだけあること以外の、縮小画像を読み出せなかった理由 (取り消し・エラー・理由なし)
private nonisolated let screenshotImageUnavailableReasonsOtherThanInCloud: [ScreenshotImageUnavailableReason] = [
    .cancelled,
    .failed(errorDescription: "PHPhotosErrorDomain 3164: network"),
    .unknown,
]

/// 一覧を開いた時に iCloud にだけあること以外の理由 (取り消し・エラー・理由なし) で読み出せなかった画像は、一覧に出さない状態にすること
@MainActor @Test(arguments: screenshotImageUnavailableReasonsOtherThanInCloud) func screenshotThumbnailStateIsUnavailableForOtherReasons(reason: ScreenshotImageUnavailableReason) async {
    let state = await screenshotThumbnailState(
        isNetworkAccessAllowed: false,
        loadImage: ScreenshotImageLoaderSpy(result: .failure(reason)).loadImage
    )

    guard case .unavailable = state else {
        Issue.record("一覧に出さない状態にならなかった: \(state)")
        return
    }
}

/// ダウンロードのボタンを押した時の読み出しは iCloud から取り (isNetworkAccessAllowed は true)、取れた画像を縮小画像にすること
@MainActor @Test func screenshotThumbnailStateIsLoadedAfterDownload() async {
    let image = UIImage()
    let loader = ScreenshotImageLoaderSpy(result: .success(image))

    let state = await screenshotThumbnailState(isNetworkAccessAllowed: true, loadImage: loader.loadImage)

    #expect(loader.requestedNetworkAccess == [true])
    guard case .loaded(let loadedImage) = state else {
        Issue.record("縮小画像の状態にならなかった: \(state)")
        return
    }
    #expect(loadedImage === image)
}

/// iCloud から取れなかった時は、どの理由でも一覧から外さず、その理由を出す状態にすること
/// (iCloud にだけある理由のままでも、ダウンロードのボタンだけの状態に戻さない)
@MainActor @Test(arguments: [ScreenshotImageUnavailableReason.inCloudOnly] + screenshotImageUnavailableReasonsOtherThanInCloud) func screenshotThumbnailStateIsDownloadFailedWhenDownloadFails(reason: ScreenshotImageUnavailableReason) async {
    let loader = ScreenshotImageLoaderSpy(result: .failure(reason))

    let state = await screenshotThumbnailState(isNetworkAccessAllowed: true, loadImage: loader.loadImage)

    #expect(loader.requestedNetworkAccess == [true])
    guard case .downloadFailed(let failedReason) = state else {
        Issue.record("取れなかった理由を出す状態にならなかった: \(state)")
        return
    }
    #expect(failedReason == reason)
}

/// 一覧に並べる写真から、読み出せないと分かった写真だけを除き、残りの順を変えないこと
/// (最初・途中・最後の写真を除く時、何も除かない時、一覧に無い識別子だけが渡された時)
@Test func listedScreenshotsExcludesUnavailableScreenshots() {
    let screenshotIdentifiers = ["first", "second", "third", "fourth"]

    #expect(
        listedScreenshots(screenshots: screenshotIdentifiers, localIdentifier: { $0 }, unavailableScreenshotIdentifiers: ["first", "third", "fourth"])
            == ["second"]
    )
    #expect(
        listedScreenshots(screenshots: screenshotIdentifiers, localIdentifier: { $0 }, unavailableScreenshotIdentifiers: [])
            == screenshotIdentifiers
    )
    #expect(
        listedScreenshots(screenshots: screenshotIdentifiers, localIdentifier: { $0 }, unavailableScreenshotIdentifiers: ["absent"])
            == screenshotIdentifiers
    )
}

/// iCloud から取れなかった理由ごとに、セルに出す文を分けること (エラーと理由なしは同じ文で、エラーの説明はセルに別に出す)
@Test func screenshotDownloadFailedMessageForEachReason() {
    #expect(screenshotDownloadFailedMessage(reason: .inCloudOnly).key == "Couldn't get it from iCloud")
    #expect(screenshotDownloadFailedMessage(reason: .cancelled).key == "Download was canceled")
    #expect(screenshotDownloadFailedMessage(reason: .failed(errorDescription: "PHPhotosErrorDomain 3164: network")).key == "Couldn't download")
    #expect(screenshotDownloadFailedMessage(reason: .unknown).key == "Couldn't download")
}

/// 端末に無く iCloud にだけある時は、エラーが添えられていても iCloud にだけある理由にすること (一覧でダウンロードのボタンを出すため)
@Test func screenshotImageUnavailableReasonIsInCloudOnlyWhenInCloud() {
    #expect(screenshotImageUnavailableReason(info: [PHImageResultIsInCloudKey: NSNumber(value: true)]) == .inCloudOnly)
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageResultIsInCloudKey: NSNumber(value: true),
            PHImageErrorKey: NSError(domain: "PHPhotosErrorDomain", code: 3164),
        ]) == .inCloudOnly
    )
}

/// 取り消された時は取り消しの理由にし、iCloud の印が false の時は iCloud にだけある理由にしないこと
@Test func screenshotImageUnavailableReasonIsCancelledWhenCancelled() {
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageResultIsInCloudKey: NSNumber(value: false),
            PHImageCancelledKey: NSNumber(value: true),
        ]) == .cancelled
    )
}

/// iCloud・取り消し・エラーの印が重なった時は、iCloud・取り消し・エラーの順で先に当たった理由にすること
@Test func screenshotImageUnavailableReasonFollowsInCloudCancelledErrorOrder() {
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageResultIsInCloudKey: NSNumber(value: true),
            PHImageCancelledKey: NSNumber(value: true),
        ]) == .inCloudOnly
    )
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageCancelledKey: NSNumber(value: true),
            PHImageErrorKey: NSError(domain: "PHPhotosErrorDomain", code: 3072),
        ]) == .cancelled
    )
}

/// エラーだけが添えられた時は、エラーのドメインとコードを含む失敗の理由にすること
@Test func screenshotImageUnavailableReasonIsFailedWithErrorDescription() {
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageErrorKey: NSError(domain: "PHPhotosErrorDomain", code: 3164, userInfo: [NSLocalizedDescriptionKey: "network"])
        ]) == .failed(errorDescription: "PHPhotosErrorDomain 3164: network")
    )
}

/// info が無い時と、印がどれも false の時は、理由なしにすること
@Test func screenshotImageUnavailableReasonIsUnknownWithoutReason() {
    #expect(screenshotImageUnavailableReason(info: nil) == .unknown)
    #expect(screenshotImageUnavailableReason(info: [:]) == .unknown)
    #expect(
        screenshotImageUnavailableReason(info: [
            PHImageResultIsInCloudKey: NSNumber(value: false),
            PHImageCancelledKey: NSNumber(value: false),
        ]) == .unknown
    )
}

/// 利用者が写真へのアクセスの許可をまだ選んでいない時は、許可を求める導線を出す状態になること
@Test func screenshotAccessIsNotRequestedBeforeUserChooses() {
    #expect(screenshotAccess(authorizationStatus: .notDetermined) == .notRequested)
}

/// すべての写真へのアクセスが許可されている時は、スクリーンショットを並べる状態になること
@Test func screenshotAccessIsAllowedWhenAuthorized() {
    #expect(screenshotAccess(authorizationStatus: .authorized) == .allowed)
}

/// 選んだ写真だけが許可されている時は、すべての写真の許可とは別の状態 (選んだ中のスクリーンショットを並べ、
/// すべての写真を許可する導線も出す状態) になること。新しく撮ったスクリーンショットが並ばない理由を伝えるため
@Test func screenshotAccessIsLimitedWhenOnlySelectedPhotosAreAllowed() {
    #expect(screenshotAccess(authorizationStatus: .limited) == .limited)
}

/// 写真へのアクセスが拒否・制限されている時は、スクリーンショットを並べず、設定アプリで許可する導線を出す状態になること
@Test func screenshotAccessIsDeniedWhenDeniedOrRestricted() {
    #expect(screenshotAccess(authorizationStatus: .denied) == .denied)
    #expect(screenshotAccess(authorizationStatus: .restricted) == .denied)
}
