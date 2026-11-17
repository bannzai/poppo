import Photos
import Testing
@testable import Poppo

/// 利用者が写真へのアクセスの許可をまだ選んでいない時は、許可を求める導線を出す状態になること
@Test func screenshotAccessIsNotRequestedBeforeUserChooses() {
    #expect(screenshotAccess(authorizationStatus: .notDetermined) == .notRequested)
}

/// 写真へのアクセスが許可されている時 (すべての写真・選んだ写真だけのどちらも) は、スクリーンショットを並べる状態になること
@Test func screenshotAccessIsAllowedWhenAuthorizedOrLimited() {
    #expect(screenshotAccess(authorizationStatus: .authorized) == .allowed)
    #expect(screenshotAccess(authorizationStatus: .limited) == .allowed)
}

/// 写真へのアクセスが拒否・制限されている時は、スクリーンショットを並べず、設定アプリで許可する導線を出す状態になること
@Test func screenshotAccessIsDeniedWhenDeniedOrRestricted() {
    #expect(screenshotAccess(authorizationStatus: .denied) == .denied)
    #expect(screenshotAccess(authorizationStatus: .restricted) == .denied)
}
