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

/// 選べるモデルは、端末内・Private Cloud Compute・OpenAI・Gemini の 4 つで、保存・診断の記録・API キーの置き場所に書く生の値が
/// この 4 つの文字列であること (生の値を変えると、保存してある選択・診断の記録・保存してある API キーを読めなくなる)
@Test func replyModelsAreOnDevicePrivateCloudComputeOpenAIAndGemini() {
    #expect(ReplyModel.allCases.map(\.rawValue) == ["onDevice", "privateCloudCompute", "openAI", "gemini"])
}

/// 発言を端末の外へ送らない (選ぶ前に確認が要らない) のは端末内だけで、Private Cloud Compute・OpenAI・Gemini は送ること
@Test func everyModelExceptOnDeviceSendsMessagesOutsideDevice() {
    #expect(sendsMessagesOutsideDevice(replyModel: .onDevice) == false)
    #expect(sendsMessagesOutsideDevice(replyModel: .privateCloudCompute) == true)
    #expect(sendsMessagesOutsideDevice(replyModel: .openAI) == true)
    #expect(sendsMessagesOutsideDevice(replyModel: .gemini) == true)
}

/// API キーが要るのは OpenAI と Gemini だけで、端末内と Private Cloud Compute は要らないこと
/// (開発者メニューは、要るモデルにだけ API キーの入力欄を出す)
@Test func onlyOpenAIAndGeminiUseAPIKey() {
    #expect(usesAPIKey(replyModel: .onDevice) == false)
    #expect(usesAPIKey(replyModel: .privateCloudCompute) == false)
    #expect(usesAPIKey(replyModel: .openAI) == true)
    #expect(usesAPIKey(replyModel: .gemini) == true)
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

/// 開発者メニューの無いビルドでは、発言を端末の外へ送るモデル (Private Cloud Compute・OpenAI・Gemini) が保存してあっても、
/// 端末内のモデルが選ばれていること。同じ保存先を開発者メニューのあるビルドで読むと保存したモデルになることも確かめる
/// (保存してある値ではなく、開発者メニューの有無で結果が分かれていることを見るため)
@Test(arguments: [ReplyModel.privateCloudCompute, .openAI, .gemini])
func selectedReplyModelIsOnDeviceWithoutDeveloperMenu(savedReplyModel: ReplyModel) throws {
    let userDefaults = try makeEmptyUserDefaults()
    save(selectedReplyModel: savedReplyModel, userDefaults: userDefaults)

    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: false) == .onDevice)
    #expect(selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: true) == savedReplyModel)
}

/// 発言を端末の外へ送ることの確認が要るのは、発言を端末の外へ送るモデルへ、ほかのモデルから切り替える操作だけであること。
/// 送り先が変わる切り替え (Private Cloud Compute から OpenAI など) でも要る。
/// 既に選んでいるモデルを選び直す操作と、端末内を選ぶ操作 (選び直し・ほかのモデルからの切り替え) では要らない
@Test func sendingConfirmationIsNeededOnlyWhenSwitchingToModelSendingMessagesOutsideDevice() {
    #expect(needsSendingConfirmation(selectingReplyModel: .privateCloudCompute, currentReplyModel: .onDevice) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .openAI, currentReplyModel: .onDevice) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .gemini, currentReplyModel: .onDevice) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .openAI, currentReplyModel: .privateCloudCompute) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .gemini, currentReplyModel: .openAI) == true)
    #expect(needsSendingConfirmation(selectingReplyModel: .privateCloudCompute, currentReplyModel: .privateCloudCompute) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .openAI, currentReplyModel: .openAI) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .gemini, currentReplyModel: .gemini) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .onDevice, currentReplyModel: .privateCloudCompute) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .onDevice, currentReplyModel: .openAI) == false)
    #expect(needsSendingConfirmation(selectingReplyModel: .onDevice, currentReplyModel: .onDevice) == false)
}
