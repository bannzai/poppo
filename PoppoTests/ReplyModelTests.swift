import Foundation
import Testing

@testable import Poppo

/// テストごとに別の、空の UserDefaults を作って返す。アプリの UserDefaults (standard) と、ほかのテストの値を混ぜないため
private func makeEmptyUserDefaults() throws -> UserDefaults {
    let suiteName = "ReplyModelTests-\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    userDefaults.removePersistentDomain(forName: suiteName)
    return userDefaults
}

/// 選べるモデルは、端末内と Private Cloud Compute の 2 つで、保存と診断の記録に書く生の値がこの 2 つの文字列であること
/// (生の値を変えると、保存してある選択と診断の記録を読めなくなる)
@Test func replyModelsAreOnDeviceAndPrivateCloudCompute() {
    #expect(ReplyModel.allCases.map(\.rawValue) == ["onDevice", "privateCloudCompute"])
}

/// 発言を端末の外へ送る (選ぶ前に確認が要る) のは Private Cloud Compute だけで、端末内は送らないこと
@Test func onlyPrivateCloudComputeSendsMessagesOutsideDevice() {
    #expect(sendsMessagesOutsideDevice(replyModel: .onDevice) == false)
    #expect(sendsMessagesOutsideDevice(replyModel: .privateCloudCompute) == true)
}

/// 何も選んでいない時は、端末内のモデルが選ばれていること (モデルを選べるようにする前の動きを変えない)
@Test func selectedReplyModelIsOnDeviceWhenNothingIsSelected() throws {
    #expect(selectedReplyModel(userDefaults: try makeEmptyUserDefaults(), hasDeveloperMenu: true) == .onDevice)
}

/// 選んだモデルは、同じ保存先を読み直しても選ばれたままであること (アプリを起動し直した後も残る)。選べるモデルのそれぞれで確かめる
@Test(arguments: ReplyModel.allCases) func selectedReplyModelIsKeptAfterSaving(replyModel: ReplyModel) throws {
    let suiteName = "ReplyModelTests-\(UUID().uuidString)"
    save(selectedReplyModel: replyModel, userDefaults: try #require(UserDefaults(suiteName: suiteName)))

    #expect(selectedReplyModel(userDefaults: try #require(UserDefaults(suiteName: suiteName)), hasDeveloperMenu: true) == replyModel)
    try #require(UserDefaults(suiteName: suiteName)).removePersistentDomain(forName: suiteName)
}

/// 選び直すと、後から選んだモデルだけが選ばれていること
@Test func selectedReplyModelIsReplacedBySavingAgain() throws {
    let userDefaults = try makeEmptyUserDefaults()
    save(selectedReplyModel: .privateCloudCompute, userDefaults: userDefaults)
    save(selectedReplyModel: .onDevice, userDefaults: userDefaults)

    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == .onDevice)
}

/// 保存してある値が選べるモデルの一覧に無い時 (空文字・知らない名前・文字列でない値) は、端末内のモデルが選ばれていること
@Test func selectedReplyModelIsOnDeviceWhenSavedValueIsNotSelectableModel() throws {
    let userDefaults = try makeEmptyUserDefaults()

    userDefaults.set("", forKey: selectedReplyModelUserDefaultsKey)
    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == .onDevice)
    userDefaults.set("removedModel", forKey: selectedReplyModelUserDefaultsKey)
    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == .onDevice)
    userDefaults.set(["privateCloudCompute"], forKey: selectedReplyModelUserDefaultsKey)
    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == .onDevice)
}

/// 開発者メニューの無いビルドでは、Private Cloud Compute が保存してあっても、端末内のモデルが選ばれていること。
/// 同じ保存先を開発者メニューのあるビルドで読むと Private Cloud Compute になることも確かめる (保存してある値ではなく、
/// 開発者メニューの有無で結果が分かれていることを見るため)
@Test func selectedReplyModelIsOnDeviceWithoutDeveloperMenu() throws {
    let userDefaults = try makeEmptyUserDefaults()
    save(selectedReplyModel: .privateCloudCompute, userDefaults: userDefaults)

    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: false) == .onDevice)
    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == .privateCloudCompute)
}

/// 発言を端末の外へ送ることの確認が要るのは、端末内から Private Cloud Compute へ切り替える操作だけであること。
/// 既に選んでいる Private Cloud Compute を選び直す操作と、端末内を選ぶ操作 (選び直し・Private Cloud Compute からの切り替え) では要らない
@Test func sendingConfirmationIsNeededOnlyWhenSwitchingToModelSendingMessagesOutsideDevice() {
    #expect(needsSendingConfirmation(selectingReplyModel: .privateCloudCompute, currentReplyModel: .onDevice) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .privateCloudCompute, currentReplyModel: .privateCloudCompute) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .onDevice, currentReplyModel: .privateCloudCompute) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .onDevice, currentReplyModel: .onDevice) == false)
}
