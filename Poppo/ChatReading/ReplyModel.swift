import Foundation

/// 返信案を作るモデル。選べるモデルの一覧は、この enum の case だけに置く (選べるモデルを足す時は case を足す)。
/// 生の値は、選んだモデルの保存 (selectedReplyModelUserDefaultsKey) と診断の記録に書くため、変えない
nonisolated enum ReplyModel: String, CaseIterable, Codable {
    /// 端末内のモデル (Foundation Models の SystemLanguageModel.default)
    case onDevice
    /// Private Cloud Compute (Apple のサーバーで動くモデル。Foundation Models の PrivateCloudComputeLanguageModel)。
    /// 選ぶと、画面から読んだ発言が Apple のサーバーへ送られる
    case privateCloudCompute
}

/// replyModel のモデルで返信案を作る時に、画面から読んだ発言を端末の外へ送るかを返す。
/// true のモデルは、選ぶ前に送る内容と送信先を画面で示して確かめる (documents/adr/0002-process-on-device-without-backend.md)
func sendsMessagesOutsideDevice(replyModel: ReplyModel) -> Bool {
    switch replyModel {
    case .onDevice:
        false
    case .privateCloudCompute:
        true
    }
}

/// 選んだ返信案を作るモデル (ReplyModel の生の値) を保存する、UserDefaults のキー
let selectedReplyModelUserDefaultsKey = "selectedReplyModel"

/// 返信案を作るモデルとして選ばれているものを返す。userDefaults は選んだモデルを保存してある場所。
/// 選べるのは開発者メニューだけのため、開発者メニューの無いビルド (DEBUG の条件が無いビルド) では、保存してある値を見ずに端末内を返す
/// (開発者メニューのあるビルドで Private Cloud Compute を選んだ端末に、開発者メニューの無いビルドを上書きで入れた時に、
/// 選び直す手段が無いまま発言を端末の外へ送り続けないようにする)
func selectedReplyModel(userDefaults: UserDefaults) -> ReplyModel {
    #if DEBUG
    // 何も選んでいない時と、保存してある値が今の一覧に無い時は端末内: モデルを選べるようにする前の動き (端末内のモデルだけで作る) を
    // 変えず、発言を端末の外へ送らない側にするため
    return userDefaults.string(forKey: selectedReplyModelUserDefaultsKey).flatMap { ReplyModel(rawValue: $0) } ?? .onDevice
    #else
    return .onDevice
    #endif
}

/// 返信案を作るモデルとして selectedReplyModel を選んだことを、userDefaults に保存する。前に選んだモデルは上書きされる
func save(selectedReplyModel: ReplyModel, userDefaults: UserDefaults) {
    userDefaults.set(selectedReplyModel.rawValue, forKey: selectedReplyModelUserDefaultsKey)
}
