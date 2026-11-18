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
