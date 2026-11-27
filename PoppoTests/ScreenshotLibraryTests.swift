import Photos
import Synchronization
import Testing
import UIKit

@testable import Poppo

/// 写真ライブラリの 1 枚を、述語が評価できる形 (PHAsset の mediaType と mediaSubtypes のキー) で返す
private func photoLibraryAssetValues(mediaType: PHAssetMediaType, mediaSubtypes: PHAssetMediaSubtype) -> [String: Any] {
    ["mediaType": mediaType.rawValue, "mediaSubtypes": mediaSubtypes.rawValue]
}

/// 種類の組 mediaKinds で問い合わせる時の述語が、項目 (mediaType と mediaSubtypes) を選ぶかを返す
private func photoLibraryMediaKindsPredicateSelects(
    mediaKinds: PhotoLibraryMediaKinds,
    mediaType: PHAssetMediaType,
    mediaSubtypes: PHAssetMediaSubtype
) -> Bool {
    recentScreenshotFetchOptions(limit: 30, mediaKinds: mediaKinds).predicate?
        .evaluate(with: photoLibraryAssetValues(mediaType: mediaType, mediaSubtypes: mediaSubtypes)) == true
}

/// 写真ライブラリの項目の見本と、その項目が当たる種類。どの種類にも当たらない音声は nil
private nonisolated let photoLibraryItemSamples: [(mediaType: PHAssetMediaType, mediaSubtypes: PHAssetMediaSubtype, mediaKind: PhotoLibraryMediaKinds?)] = [
    (.image, .photoScreenshot, .screenshots),
    // スクリーンショットとほかの種別を併せ持つ画像はスクリーンショット
    (.image, [.photoScreenshot, .photoHDR], .screenshots),
    (.image, .photoLive, .otherPhotos),
    (.image, .photoPanorama, .otherPhotos),
    (.image, [], .otherPhotos),
    (.video, .videoScreenRecording, .screenRecordings),
    (.video, [.videoScreenRecording, .videoHighFrameRate], .screenRecordings),
    (.video, [], .otherVideos),
    (.video, .videoHighFrameRate, .otherVideos),
    // 種別のビットがスクリーンショットと同じでも動画は画像ではなく、画面収録と同じでも画像は動画ではない (述語が mediaType を見ていることを確かめるため)
    (.video, .photoScreenshot, .otherVideos),
    (.image, .videoScreenRecording, .otherPhotos),
    (.audio, [], nil),
]

/// 種類の組のすべて (空を除く 15 通り) で、問い合わせの述語が、組に入っている種類の項目だけを選ぶこと
@Test(arguments: 1..<16) func recentScreenshotFetchOptionsSelectOnlyListedMediaKinds(mediaKindsRawValue: Int) {
    let mediaKinds = PhotoLibraryMediaKinds(rawValue: mediaKindsRawValue)
    for sample in photoLibraryItemSamples {
        #expect(
            photoLibraryMediaKindsPredicateSelects(mediaKinds: mediaKinds, mediaType: sample.mediaType, mediaSubtypes: sample.mediaSubtypes)
                == sample.mediaKind.map { mediaKinds.contains($0) } ?? false,
            "種類の組 \(mediaKindsRawValue) で \(sample)"
        )
    }
}

/// スクリーンショットだけの時の述語が、種類の組を足す前 (スクリーンショットだけの切り替え) と同じ書式であること。
/// 実機で動いていた問い合わせを変えないため
@Test func recentScreenshotFetchOptionsKeepScreenshotsOnlyPredicate() {
    #expect(
        recentScreenshotFetchOptions(limit: 30, mediaKinds: .screenshots).predicate?.predicateFormat
            == NSPredicate(
                format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
                PHAssetMediaType.image.rawValue,
                PHAssetMediaSubtype.photoScreenshot.rawValue
            ).predicateFormat
    )
}

/// 写真ライブラリへの問い合わせが、どの種類の組でも撮った日時の新しい順に並べること
@Test(arguments: [PhotoLibraryMediaKinds.screenshots, [.screenshots, .otherVideos], [.otherPhotos, .screenRecordings, .otherVideos]])
func recentScreenshotFetchOptionsSortNewestFirst(mediaKinds: PhotoLibraryMediaKinds) {
    let options = recentScreenshotFetchOptions(limit: 30, mediaKinds: mediaKinds)

    #expect(options.sortDescriptors?.map(\.key) == ["creationDate"])
    #expect(options.sortDescriptors?.map(\.ascending) == [false])
}

/// 写真ライブラリへの問い合わせが、どの種類の組でも渡した件数までに限ること (1 件と 30 件)
@Test(arguments: [PhotoLibraryMediaKinds.screenshots, [.screenshots, .otherVideos]])
func recentScreenshotFetchOptionsLimitCount(mediaKinds: PhotoLibraryMediaKinds) {
    #expect(recentScreenshotFetchOptions(limit: 1, mediaKinds: mediaKinds).fetchLimit == 1)
    #expect(recentScreenshotFetchOptions(limit: 30, mediaKinds: mediaKinds).fetchLimit == 30)
}

/// 絞り込みの切り替えが、選ぶと種類を足し、外すと種類を除くこと
@Test func toggledPhotoLibraryMediaKindsAddsAndRemoves() {
    #expect(toggledPhotoLibraryMediaKinds(current: .screenshots, mediaKind: .screenRecordings, isOn: true) == [.screenshots, .screenRecordings])
    #expect(toggledPhotoLibraryMediaKinds(current: [.screenshots, .screenRecordings], mediaKind: .screenshots, isOn: false) == .screenRecordings)
    // 選んでいる種類を選び直しても、選んでいない種類を外しても、組は変わらない
    #expect(toggledPhotoLibraryMediaKinds(current: .screenshots, mediaKind: .screenshots, isOn: true) == .screenshots)
    #expect(toggledPhotoLibraryMediaKinds(current: .screenshots, mediaKind: .otherVideos, isOn: false) == .screenshots)
}

/// 絞り込みの切り替えで最後に残った種類を外しても、組を空にしないこと (何も並ばない一覧にしないため)
@Test func toggledPhotoLibraryMediaKindsKeepsLastKind() {
    #expect(toggledPhotoLibraryMediaKinds(current: .otherVideos, mediaKind: .otherVideos, isOn: false) == .otherVideos)
}

/// 種類ごとのビットの位置が、端末に保存した選択を読み直せる値のままであること (変えると、前に保存した選択が別の種類として読まれるため)
@Test func photoLibraryMediaKindsRawValuesAreStable() {
    #expect(PhotoLibraryMediaKinds.screenshots.rawValue == 1)
    #expect(PhotoLibraryMediaKinds.otherPhotos.rawValue == 2)
    #expect(PhotoLibraryMediaKinds.screenRecordings.rawValue == 4)
    #expect(PhotoLibraryMediaKinds.otherVideos.rawValue == 8)
}

/// 一覧の見出しが、スクリーンショットだけ・写真だけ・動画だけ・写真と動画の組で変わること
@Test func recentScreenshotsTitleFollowsMediaKinds() {
    #expect(recentScreenshotsTitle(mediaKinds: .screenshots).key == "Recent screenshots")
    #expect(recentScreenshotsTitle(mediaKinds: .otherPhotos).key == "Recent photos")
    #expect(recentScreenshotsTitle(mediaKinds: [.screenshots, .otherPhotos]).key == "Recent photos")
    #expect(recentScreenshotsTitle(mediaKinds: .screenRecordings).key == "Recent videos")
    #expect(recentScreenshotsTitle(mediaKinds: [.screenRecordings, .otherVideos]).key == "Recent videos")
    #expect(recentScreenshotsTitle(mediaKinds: [.screenshots, .screenRecordings]).key == "Recent photos and videos")
}

/// 一覧の上の行が、選んでいる種類の名前だけを、絞り込みの画面と同じ順に並べること
@Test func photoLibraryMediaKindsSummaryListsSelectedKindsInFilterOrder() throws {
    let summary = photoLibraryMediaKindsSummary(mediaKinds: [.otherVideos, .screenshots])

    #expect(summary.contains("Screenshots"))
    #expect(summary.contains("Other videos"))
    #expect(!summary.contains("Other photos"))
    #expect(!summary.contains("Screen recordings"))
    #expect(try #require(summary.range(of: "Screenshots")).lowerBound < (try #require(summary.range(of: "Other videos")).lowerBound))
}

/// 写真ライブラリの読み出しの代わりに result を返す処理を screenshotThumbnailState へ渡して呼ぶ。
/// 返す値は、決まった縮小画像の状態 (state) と、読み出しに渡された isNetworkAccessAllowed (requestedNetworkAccess。渡された順)
private func screenshotThumbnailStateWithStubbedImage(
    isNetworkAccessAllowed: Bool,
    result: Result<UIImage, ScreenshotImageUnavailableReason>
) async -> (state: ScreenshotThumbnailState, requestedNetworkAccess: [Bool]) {
    var requestedNetworkAccess: [Bool] = []
    // tuple の要素は左から順に評価されるため、requestedNetworkAccess は読み出しが終わった後の値になる
    return (
        await screenshotThumbnailState(isNetworkAccessAllowed: isNetworkAccessAllowed) { requestedIsNetworkAccessAllowed in
            requestedNetworkAccess.append(requestedIsNetworkAccessAllowed)
            return result
        },
        requestedNetworkAccess
    )
}

/// 一覧を開いた時の読み出しは iCloud から取らず (isNetworkAccessAllowed は false)、読み出せた画像はそのまま縮小画像にすること
@Test func screenshotThumbnailStateIsLoadedWithoutNetworkAccess() async {
    let image = UIImage()
    let (state, requestedNetworkAccess) = await screenshotThumbnailStateWithStubbedImage(
        isNetworkAccessAllowed: false,
        result: .success(image)
    )

    #expect(requestedNetworkAccess == [false])
    guard case .loaded(let loadedImage) = state else {
        Issue.record("縮小画像の状態にならなかった: \(state)")
        return
    }
    #expect(loadedImage === image)
}

/// 一覧を開いた時に iCloud にだけあった画像は、一覧から外さずダウンロードのボタンを出す状態にすること
@Test func screenshotThumbnailStateNeedsDownloadWhenInCloudOnly() async {
    let (state, requestedNetworkAccess) = await screenshotThumbnailStateWithStubbedImage(
        isNetworkAccessAllowed: false,
        result: .failure(.inCloudOnly)
    )

    #expect(requestedNetworkAccess == [false])
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
@Test(arguments: screenshotImageUnavailableReasonsOtherThanInCloud) func screenshotThumbnailStateIsUnavailableForOtherReasons(reason: ScreenshotImageUnavailableReason) async {
    let (state, _) = await screenshotThumbnailStateWithStubbedImage(isNetworkAccessAllowed: false, result: .failure(reason))

    guard case .unavailable = state else {
        Issue.record("一覧に出さない状態にならなかった: \(state)")
        return
    }
}

/// ダウンロードのボタンを押した時の読み出しは iCloud から取り (isNetworkAccessAllowed は true)、取れた画像を縮小画像にすること
@Test func screenshotThumbnailStateIsLoadedAfterDownload() async {
    let image = UIImage()
    let (state, requestedNetworkAccess) = await screenshotThumbnailStateWithStubbedImage(
        isNetworkAccessAllowed: true,
        result: .success(image)
    )

    #expect(requestedNetworkAccess == [true])
    guard case .loaded(let loadedImage) = state else {
        Issue.record("縮小画像の状態にならなかった: \(state)")
        return
    }
    #expect(loadedImage === image)
}

/// iCloud から取れなかった時は、どの理由でも一覧から外さず、その理由を出す状態にすること
/// (iCloud にだけある理由のままでも、ダウンロードのボタンだけの状態に戻さない)
@Test(arguments: [ScreenshotImageUnavailableReason.inCloudOnly] + screenshotImageUnavailableReasonsOtherThanInCloud) func screenshotThumbnailStateIsDownloadFailedWhenDownloadFails(reason: ScreenshotImageUnavailableReason) async {
    let (state, requestedNetworkAccess) = await screenshotThumbnailStateWithStubbedImage(
        isNetworkAccessAllowed: true,
        result: .failure(reason)
    )

    #expect(requestedNetworkAccess == [true])
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

/// ダウンロードのボタンを出している状態 (iCloud にだけある・取れなかった) だけ、iCloud から取り始めてよいこと。
/// 取っている間・読み出せた後・読み出す前・読み出せない時は取り始めない (続けて押した時に 2 本並べて取らないため)
@Test func canStartScreenshotDownloadOnlyWhileShowingDownloadButton() {
    #expect(canStartScreenshotDownload(thumbnailState: .needsDownload))
    #expect(canStartScreenshotDownload(thumbnailState: .downloadFailed(reason: .inCloudOnly)))
    #expect(canStartScreenshotDownload(thumbnailState: .downloadFailed(reason: .unknown)))
    #expect(!canStartScreenshotDownload(thumbnailState: .downloading(fractionCompleted: 0)))
    #expect(!canStartScreenshotDownload(thumbnailState: .downloading(fractionCompleted: 1)))
    #expect(!canStartScreenshotDownload(thumbnailState: .loaded(image: UIImage())))
    #expect(!canStartScreenshotDownload(thumbnailState: .loading))
    #expect(!canStartScreenshotDownload(thumbnailState: .unavailable))
}

/// 初めの読み出しの結果は、読み出しを始めた時の状態のままの時だけ書くこと。
/// ボタンを押していない時は読み出す前の状態、押した後に作り直されたセルでは取っている状態の時だけ書く
@Test func canApplyInitialScreenshotThumbnailStateOnlyWhenStateIsUnchanged() {
    #expect(canApplyInitialScreenshotThumbnailState(currentThumbnailState: .loading, isDownloadRequested: false))
    #expect(canApplyInitialScreenshotThumbnailState(currentThumbnailState: .downloading(fractionCompleted: 0.5), isDownloadRequested: true))
}

/// 待っている間に状態が変わった時は、初めの読み出しの結果を書かないこと
/// (ボタンを押していない読み出しの間に取り始めた時、読み出せた後、ボタンを出した後、取れなかった後、一覧から外した後)
@Test func canApplyInitialScreenshotThumbnailStateRejectsChangedState() {
    #expect(!canApplyInitialScreenshotThumbnailState(currentThumbnailState: .downloading(fractionCompleted: 0), isDownloadRequested: false))
    #expect(!canApplyInitialScreenshotThumbnailState(currentThumbnailState: .loading, isDownloadRequested: true))
    for isDownloadRequested in [true, false] {
        #expect(!canApplyInitialScreenshotThumbnailState(currentThumbnailState: .loaded(image: UIImage()), isDownloadRequested: isDownloadRequested))
        #expect(!canApplyInitialScreenshotThumbnailState(currentThumbnailState: .needsDownload, isDownloadRequested: isDownloadRequested))
        #expect(
            !canApplyInitialScreenshotThumbnailState(
                currentThumbnailState: .downloadFailed(reason: .inCloudOnly),
                isDownloadRequested: isDownloadRequested
            )
        )
        #expect(!canApplyInitialScreenshotThumbnailState(currentThumbnailState: .unavailable, isDownloadRequested: isDownloadRequested))
    }
}

/// 写真ライブラリへ渡す読み出しの条件が、iCloud から取ってよいかをそのまま写し、結果を 1 回だけ返す形にすること
@Test(arguments: [true, false]) func screenshotImageRequestOptionsCopyNetworkAccess(isNetworkAccessAllowed: Bool) {
    let options = screenshotImageRequestOptions(isNetworkAccessAllowed: isNetworkAccessAllowed, progressHandler: nil)

    #expect(options.isNetworkAccessAllowed == isNetworkAccessAllowed)
    #expect(options.deliveryMode == .highQualityFormat)
    #expect(options.progressHandler == nil)
}

/// 進み具合を受け取る処理を渡した時は、写真ライブラリが伝えた進み具合をそのまま渡すこと
@Test func screenshotImageRequestOptionsForwardProgress() throws {
    let receivedFractions = Mutex<[Double]>([])
    let progressHandler = try #require(
        screenshotImageRequestOptions(isNetworkAccessAllowed: true) { fractionCompleted in
            receivedFractions.withLock { $0.append(fractionCompleted) }
        }.progressHandler
    )
    var stop = ObjCBool(false)

    progressHandler(0.25, nil, &stop, nil)
    progressHandler(1, nil, &stop, nil)

    #expect(receivedFractions.withLock { $0 } == [0.25, 1])
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
