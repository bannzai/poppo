import Photos
import Testing

@testable import Poppo

/// 写真ライブラリへの問い合わせが、スクリーンショットの種別を持つ写真だけを選ぶこと。
/// スクリーンショットとほかの種別を併せ持つ写真は選び、ほかの種別だけの写真 (Live Photo・パノラマ) と種別の無い写真は選ばない
@Test func recentScreenshotFetchOptionsSelectOnlyScreenshots() throws {
    let predicate = try #require(recentScreenshotFetchOptions(limit: 30).predicate)

    #expect(predicate.evaluate(with: ["mediaSubtypes": PHAssetMediaSubtype.photoScreenshot.rawValue]))
    #expect(
        predicate.evaluate(with: [
            "mediaSubtypes": PHAssetMediaSubtype.photoScreenshot.union(.photoHDR).rawValue
        ])
    )
    #expect(!predicate.evaluate(with: ["mediaSubtypes": PHAssetMediaSubtype.photoLive.rawValue]))
    #expect(!predicate.evaluate(with: ["mediaSubtypes": PHAssetMediaSubtype.photoPanorama.rawValue]))
    #expect(!predicate.evaluate(with: ["mediaSubtypes": PHAssetMediaSubtype().rawValue]))
}

/// 写真ライブラリへの問い合わせが、撮った日時の新しい順に並べること
@Test func recentScreenshotFetchOptionsSortNewestFirst() {
    #expect(recentScreenshotFetchOptions(limit: 30).sortDescriptors?.map(\.key) == ["creationDate"])
    #expect(recentScreenshotFetchOptions(limit: 30).sortDescriptors?.map(\.ascending) == [false])
}

/// 写真ライブラリへの問い合わせが、渡した枚数までに限ること (1 枚と 30 枚)
@Test func recentScreenshotFetchOptionsLimitCount() {
    #expect(recentScreenshotFetchOptions(limit: 1).fetchLimit == 1)
    #expect(recentScreenshotFetchOptions(limit: 30).fetchLimit == 30)
}

/// 端末に無く iCloud にだけある時は、エラーが添えられていても iCloud にだけある理由にすること (一覧で「この iPhone にありません」と出すため)
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
