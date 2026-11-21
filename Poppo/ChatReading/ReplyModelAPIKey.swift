import Foundation
import Security

/// 返信案を作るモデルの API キーを置く、Keychain の service。API キーはこの service の下に、モデルごと (account が ReplyModel の生の値) に 1 つずつ置く
nonisolated let replyModelAPIKeyKeychainService = "com.bannzai.poppo.replyModelAPIKey"

/// Keychain の操作が失敗したことを表すエラー。API キーの値は持たない
nonisolated struct ReplyModelAPIKeyKeychainError: Error, Equatable, LocalizedError {
    /// Keychain の関数 (SecItemAdd・SecItemUpdate・SecItemCopyMatching・SecItemDelete) が返した結果のコード
    let status: OSStatus

    /// 開発者メニューと診断の記録に出す、失敗の説明 (結果のコードだけを持つ)
    var errorDescription: String? {
        "Keychain status \(status)"
    }
}

/// enteredText (API キーの入力欄に入力した文) から、前後の空白と改行を取り除いて、保存する API キーにして返す。
/// 貼り付けで付いた改行や空白が残ると、提供元の認証が通らないため。空白と改行だけの入力では空文字を返す
nonisolated func apiKey(enteredText: String) -> String {
    enteredText.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// keychainService の下で replyModel の API キーを指す、Keychain の検索の条件を返す
private nonisolated func apiKeyKeychainQuery(replyModel: ReplyModel, keychainService: String) -> [CFString: Any] {
    [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: keychainService,
        kSecAttrAccount: replyModel.rawValue,
    ]
}

/// replyModel のモデルの API キー (apiKey) を、端末の Keychain の keychainService の下に保存する。前に保存したキーは上書きされる。
/// 保存できなかった時は ReplyModelAPIKeyKeychainError を投げる
nonisolated func save(apiKey: String, replyModel: ReplyModel, keychainService: String) throws {
    switch SecItemAdd(
        apiKeyKeychainQuery(replyModel: replyModel, keychainService: keychainService).merging([
            kSecValueData: Data(apiKey.utf8),
            // 取り込みの間は本体アプリが背面にいて、画面を閉じた間にも読むため、最初のロック解除の後はいつでも読める指定にする。
            // ThisDeviceOnly: ほかの端末とバックアップへ移さない
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { _, new in new } as CFDictionary,
        nil
    ) {
    case errSecSuccess:
        return
    case errSecDuplicateItem:
        let updateStatus = SecItemUpdate(
            apiKeyKeychainQuery(replyModel: replyModel, keychainService: keychainService) as CFDictionary,
            [kSecValueData: Data(apiKey.utf8)] as CFDictionary
        )
        guard updateStatus == errSecSuccess else {
            throw ReplyModelAPIKeyKeychainError(status: updateStatus)
        }
    case let addStatus:
        throw ReplyModelAPIKeyKeychainError(status: addStatus)
    }
}

/// replyModel のモデルの API キーを、端末の Keychain の keychainService の下から読んで返す。保存していない時は nil を返す。
/// 読めなかった時 (端末を起動してから一度もロックを解除していない時など) は ReplyModelAPIKeyKeychainError を投げる
nonisolated func loadAPIKey(replyModel: ReplyModel, keychainService: String) throws -> String? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
        apiKeyKeychainQuery(replyModel: replyModel, keychainService: keychainService).merging([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]) { _, new in new } as CFDictionary,
        &item
    )
    guard status != errSecItemNotFound else {
        return nil
    }
    guard status == errSecSuccess, let data = item as? Data else {
        throw ReplyModelAPIKeyKeychainError(status: status)
    }
    return String(decoding: data, as: UTF8.self)
}

/// replyModel のモデルの API キーを、端末の Keychain の keychainService の下から削除する。保存していない時に実行しても何も起きない。
/// 削除できなかった時は ReplyModelAPIKeyKeychainError を投げる
nonisolated func deleteAPIKey(replyModel: ReplyModel, keychainService: String) throws {
    let status = SecItemDelete(apiKeyKeychainQuery(replyModel: replyModel, keychainService: keychainService) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
        throw ReplyModelAPIKeyKeychainError(status: status)
    }
}
