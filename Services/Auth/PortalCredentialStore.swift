//
//  PortalCredentialStore.swift
//  CIT-Campus-3D
//
//  CITポータル（UNIVERSAL PASSPORT）連携の認証情報を端末内Keychainに保存・取得する．
//  保存対象は ユーザーID・パスワード・TOTPシークレット の3点．
//
//  セキュリティ方針:
//  - すべて kSecAttrAccessibleWhenUnlockedThisDeviceOnly で保存し，iCloud Keychain同期・
//    別端末へのバックアップ復元の対象から外す（シークレットを端末外へ拡散させない）．
//  - パスワードとTOTPシークレットを同一端末に置くため，2要素が実質1束に集約される点に注意．
//    登録UIでこのリスクを明示する．
//

import Foundation
import Security

/// 保存する認証情報（メモリ上の受け渡し用．長時間保持しないこと）
struct PortalCredentials: Equatable {
  /// ポータルのユーザーID（学籍番号等）
  var userID: String
  /// ポータルのパスワード
  var password: String
  /// 2段階認証のTOTPシークレット（base32）
  var totpSecret: String
}

/// Keychain操作のエラー
enum CredentialStoreError: LocalizedError {
  /// Keychainの読み書きに失敗（OSStatusを保持）
  case keychain(OSStatus)
  /// 入力が空（保存前バリデーション）
  case emptyField(String)

  var errorDescription: String? {
    switch self {
    case .keychain(let status):
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "不明なエラー"
      return "認証情報の保存／取得に失敗しました（\(message)）．"
    case .emptyField(let field):
      return "\(field)を入力してください．"
    }
  }
}

/// ポータル認証情報のKeychainストア（SwiftUIへ登録状態を公開する）
@MainActor
@Observable
final class PortalCredentialStore {

  // MARK: - 公開状態（非機密のみ）

  /// 登録済みのユーザーID（表示用．未登録ならnil）
  private(set) var userID: String?

  /// 認証情報が登録済みか（ユーザーID＋パスワードがあれば登録済み）
  var isRegistered: Bool { userID != nil }

  /// TOTPシークレットが登録済みか（ポータルのOTP自動入力が可能か）
  private(set) var hasTOTPSecret = false

  /// 最終同期時刻（表示用．機密でないためUserDefaultsに保存）
  private(set) var lastSyncDate: Date?

  // MARK: - 定数

  /// Keychainのサービス識別子
  private let service = "com.HR.CIT-Campus-3D.portal"
  /// 各項目のアカウントキー
  private enum Account {
    static let userID = "userID"
    static let password = "password"
    static let totpSecret = "totpSecret"
  }
  /// 最終同期時刻を保存するUserDefaultsキー
  private let lastSyncKey = "portal.lastSyncDate"

  // MARK: - 初期化

  init() {
    // 起動時にKeychainから登録状態を読み込む（ユーザーIDのみメモリ保持．機密は都度取得）
    userID = (try? readString(account: Account.userID)) ?? nil
    hasTOTPSecret = ((try? readString(account: Account.totpSecret)) ?? nil) != nil
    let stored = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    lastSyncDate = stored
  }

  // MARK: - 保存・取得・削除

  /// 認証情報を保存する．
  /// ユーザーID・パスワードは必須．TOTPシークレットは任意（ポータルのOTP自動入力にだけ使う）で，
  /// 空欄ならシークレットを保存しない（manabaはID＋パスワードのみで動くため）．
  func save(_ credentials: PortalCredentials) throws {
    let userID = credentials.userID.trimmingCharacters(in: .whitespacesAndNewlines)
    let password = credentials.password
    let secret = credentials.totpSecret.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !userID.isEmpty else { throw CredentialStoreError.emptyField("ユーザーID") }
    guard !password.isEmpty else { throw CredentialStoreError.emptyField("パスワード") }

    try writeString(userID, account: Account.userID)
    try writeString(password, account: Account.password)

    // シークレットは任意: 入力があれば保存，無ければ既存を削除する
    if secret.isEmpty {
      try delete(account: Account.totpSecret)
      hasTOTPSecret = false
    } else {
      try writeString(secret, account: Account.totpSecret)
      hasTOTPSecret = true
    }

    self.userID = userID
  }

  /// 保存済みパスワードを取得する（未登録ならnil）
  func loadPassword() -> String? {
    (try? readString(account: Account.password)) ?? nil
  }

  /// 保存済みTOTPシークレットを取得する（未登録ならnil）
  func loadTOTPSecret() -> String? {
    (try? readString(account: Account.totpSecret)) ?? nil
  }

  /// 現在時刻のワンタイムコードを生成する（シークレット未登録または生成失敗ならnil）
  func currentOTP() -> String? {
    guard let secret = loadTOTPSecret() else { return nil }
    return try? TOTPGenerator.code(secret: secret)
  }

  /// 最終同期時刻を更新する（同期成功時に呼ぶ）
  func updateLastSyncDate(_ date: Date) {
    lastSyncDate = date
    UserDefaults.standard.set(date, forKey: lastSyncKey)
  }

  /// 登録済みの認証情報をすべて削除する
  func deleteAll() throws {
    try delete(account: Account.userID)
    try delete(account: Account.password)
    try delete(account: Account.totpSecret)
    UserDefaults.standard.removeObject(forKey: lastSyncKey)
    userID = nil
    hasTOTPSecret = false
    lastSyncDate = nil
  }

  // MARK: - Keychainの低レベル操作

  /// 文字列を保存する（既存があれば上書き）
  private func writeString(_ value: String, account: String) throws {
    guard let data = value.data(using: .utf8) else {
      throw CredentialStoreError.emptyField(account)
    }

    // 既存項目を一旦削除してから追加する（更新の取りこぼしを防ぐ）
    let deleteQuery = baseQuery(account: account)
    SecItemDelete(deleteQuery as CFDictionary)

    var addQuery = baseQuery(account: account)
    addQuery[kSecValueData as String] = data
    // 端末ロック解除中のみアクセス可・iCloud同期と別端末復元の対象外にする
    addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    let status = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw CredentialStoreError.keychain(status)
    }
  }

  /// 文字列を取得する（未登録はnilを返し，それ以外の失敗はthrow）
  private func readString(account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)

    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw CredentialStoreError.keychain(status)
    }
    guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
      return nil
    }
    return value
  }

  /// 項目を削除する（存在しない場合は成功扱い）
  private func delete(account: String) throws {
    let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialStoreError.keychain(status)
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
