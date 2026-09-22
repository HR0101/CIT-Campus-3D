//
//  KeychainStore.swift
//  CIT-Campus-3D
//
//  Keychainへの文字列の保存・取得・削除を行う薄いラッパー．
//  サービス識別子（service）ごとに1つ生成して使う．PortalCredentialStoreと
//  AttendanceCredentialStoreの双方で，同じ低レベル処理を重複させないために切り出した．
//

import Foundation
import Security

/// Keychain操作のエラー
enum KeychainError: LocalizedError {
  /// Keychainの読み書きに失敗（OSStatusを保持）
  case status(OSStatus)

  var errorDescription: String? {
    switch self {
    case .status(let status):
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "不明なエラー"
      return "認証情報の保存／取得に失敗しました（\(message)）．"
    }
  }
}

/// 指定サービスに紐づくアカウント文字列をKeychainに保存・取得・削除する
struct KeychainStore {

  /// Keychainのサービス識別子
  let service: String

  /// 文字列を保存する（既存があれば上書き）．
  /// 端末ロック解除中のみアクセス可・iCloud同期と別端末復元の対象外にする
  func writeString(_ value: String, account: String) throws {
    guard let data = value.data(using: .utf8) else { return }

    // 既存項目を一旦削除してから追加する（更新の取りこぼしを防ぐ）
    SecItemDelete(baseQuery(account: account) as CFDictionary)

    var addQuery = baseQuery(account: account)
    addQuery[kSecValueData as String] = data
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw KeychainError.status(status)
    }
  }

  /// 文字列を取得する（未登録はnilを返し，それ以外の失敗はthrow）
  func readString(account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw KeychainError.status(status)
    }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return value
  }

  /// 項目を削除する（存在しない場合は成功扱い）
  func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.status(status)
    }
  }

  /// サービス＋アカウントを指定する共通クエリ
  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
