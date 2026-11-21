import Foundation

/// 返信案を作るモデル。選べるモデルの一覧は、この enum の case だけに置く (選べるモデルを足す時は case を足す)。
/// 生の値は、選んだモデルの保存 (selectedReplyModelUserDefaultsKey) と診断の記録に書くため、変えない
nonisolated enum ReplyModel: String, CaseIterable, Codable {
    /// 端末内のモデル (Foundation Models の SystemLanguageModel.default)
    case onDevice
    /// Private Cloud Compute (Apple のサーバーで動くモデル。Foundation Models の PrivateCloudComputeLanguageModel)。
    /// 選ぶと、画面から読んだ発言が Apple のサーバーへ送られる
    case privateCloudCompute
    /// OpenAI のモデル (OpenAI の API。開発者メニューで保存した API キーで使う)。
    /// 選ぶと、画面から読んだ発言が OpenAI のサーバーへ送られる
    case openAI
    /// Gemini のモデル (Google の Gemini API。開発者メニューで保存した API キーで使う)。
    /// 選ぶと、画面から読んだ発言が Google のサーバーへ送られる
    case gemini
    /// Claude のモデル (Anthropic の API。API キーを持たず、App Attest で認証する)。
    /// 選ぶと、画面から読んだ発言が Anthropic のサーバーへ送られる
    case claude
}

/// replyModel のモデルで返信案を作る時に、画面から読んだ発言を端末の外へ送るかを返す。
/// true のモデルは、選ぶ前に送る内容と送信先を画面で示して確かめる (documents/adr/0002-process-on-device-without-backend.md)
func sendsMessagesOutsideDevice(replyModel: ReplyModel) -> Bool {
    switch replyModel {
    case .onDevice:
        false
    case .privateCloudCompute, .openAI, .gemini, .claude:
        true
    }
}

/// replyModel のモデルで返信案を作るのに、開発者メニューで保存する API キーが要るかを返す
func usesAPIKey(replyModel: ReplyModel) -> Bool {
    switch replyModel {
    case .onDevice, .privateCloudCompute, .claude:
        false
    case .openAI, .gemini:
        true
    }
}

/// 開発者メニューで selectingReplyModel を選ぶ操作の前に、発言を端末の外へ送ることの確認が要るかを返す。
/// currentReplyModel は今選ばれているモデル。要るのは、発言を端末の外へ送るモデルへ、ほかのモデルから切り替える時だけ
/// (既に選んでいるモデルを選び直す操作は送り先を変えず、端末の外へ送らないモデルを選ぶ操作は送るのをやめるため)
func needsSendingConfirmation(selectingReplyModel: ReplyModel, currentReplyModel: ReplyModel) -> Bool {
    sendsMessagesOutsideDevice(replyModel: selectingReplyModel) && selectingReplyModel != currentReplyModel
}

/// 選んだ返信案を作るモデル (ReplyModel の生の値) を保存する、UserDefaults のキー
let selectedReplyModelUserDefaultsKey = "selectedReplyModel"

/// このビルドに開発者メニュー (返信案を作るモデルを選ぶ唯一の場所) があるか
var hasDeveloperMenu: Bool {
    #if DEBUG
    true
    #else
    false
    #endif
}

/// 返信案を作るモデルとして選ばれているものを返す。userDefaults は選んだモデルを保存してある場所
func selectedReplyModel(userDefaults: UserDefaults) -> ReplyModel {
    selectedReplyModel(userDefaults: userDefaults, hasDeveloperMenu: hasDeveloperMenu)
}

/// 返信案を作るモデルとして選ばれているものを返す。userDefaults は選んだモデルを保存してある場所。
/// hasDeveloperMenu が false の時 (開発者メニューの無いビルド) は、保存してある値を見ずに端末内を返す
/// (開発者メニューのあるビルドで Private Cloud Compute を選んだ端末に、開発者メニューの無いビルドを上書きで入れた時に、
/// 選び直す手段が無いまま発言を端末の外へ送り続けないようにする)
func selectedReplyModel(userDefaults: UserDefaults, hasDeveloperMenu: Bool) -> ReplyModel {
    guard hasDeveloperMenu else {
        return .onDevice
    }
    // 何も選んでいない時と、保存してある値が今の一覧に無い時は端末内: モデルを選べるようにする前の動き (端末内のモデルだけで作る) を
    // 変えず、発言を端末の外へ送らない側にするため
    return userDefaults.string(forKey: selectedReplyModelUserDefaultsKey).flatMap { ReplyModel(rawValue: $0) } ?? .onDevice
}

/// 返信案を作るモデルとして selectedReplyModel を選んだことを、userDefaults に保存する。前に選んだモデルは上書きされる
func save(selectedReplyModel: ReplyModel, userDefaults: UserDefaults) {
    userDefaults.set(selectedReplyModel.rawValue, forKey: selectedReplyModelUserDefaultsKey)
}
