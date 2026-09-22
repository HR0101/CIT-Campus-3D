//
//  AttendanceCredentialStore.swift
//  CIT-Campus-3D
//
//  出席システム（attendance.is.chibatech.ac.jp）専用の認証情報を端末内Keychainに保存・取得する．
//  CITポータルとID・パスワードが同じ学生と，異なる学生の双方がいるため，
//  「ポータルと同じ認証情報を使う」か「出席システム専用の認証情報を使う」かを切り替えられるようにする．
//

import Foundation

/// 出席システム認証情報のKeychainストア（SwiftUIへ登録状態を公開する）
@MainActor
@Observable
final class AttendanceCredentialStore {

  // MARK: - 公開状態

  /// ポータルと同じID・パスワードを使うか．trueなら`PortalCredentialStore`の認証情報をそのまま使い，
  /// falseならこのストアに専用登録した認証情報を使う（デフォルトはtrue）
  var useSamePortalCredentials: Bool {
    didSet {
      UserDefaults.standard.set(useSamePortalCredentials, forKey: useSameKey)
    }
  }

  /// 専用に登録済みのユーザーID（表示用．未登録ならnil）
  private(set) var userID: String?

  /// 専用の認証情報が登録済みか
  var isRegistered: Bool { userID != nil }

  // MARK: - 定数

  /// Keychainストア
  private let keychain = KeychainStore(service: "com.HR.CIT-Campus-3D.attendance")
  /// 各項目のアカウントキー
  private enum Account {
    static let userID = "userID"
    static let password = "password"
  }
  /// 「ポータルと同じを使うか」を保存するUserDefaultsキー
  private let useSameKey = "attendance.useSamePortalCredentials"

  // MARK: - 初期化

  init() {
    useSamePortalCredentials = (UserDefaults.standard.object(forKey: useSameKey) as? Bool) ?? true
    userID = (try? keychain.readString(account: Account.userID)) ?? nil
  }

  // MARK: - 専用登録の保存・取得・削除

  /// 出席システム専用の認証情報を保存する
  func save(userID: String, password: String) throws {
    let trimmedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedID.isEmpty else { throw CredentialStoreError.emptyField("ユーザーID") }
    guard !password.isEmpty else { throw CredentialStoreError.emptyField("パスワード") }

    try keychain.writeString(trimmedID, account: Account.userID)
    try keychain.writeString(password, account: Account.password)
    self.userID = trimmedID
  }

  /// 保存済みパスワードを取得する（未登録ならnil）
  func loadPassword() -> String? {
    (try? keychain.readString(account: Account.password)) ?? nil
  }

  /// 専用登録した認証情報をすべて削除する（「ポータルと同じ」設定はそのまま残す）
  func deleteAll() throws {
    try keychain.delete(account: Account.userID)
    try keychain.delete(account: Account.password)
    userID = nil
  }

  // MARK: - 出席システムへ実際に使う認証情報の解決

  /// 出席システムへのログインに実際に使うユーザーID．
  /// 「ポータルと同じ」ならポータルのID，そうでなければ専用登録したIDを返す
  func effectiveUserID(portalStore: PortalCredentialStore) -> String? {
    useSamePortalCredentials ? portalStore.userID : userID
  }

  /// 出席システムへのログインに実際に使うパスワード
  func effectivePassword(portalStore: PortalCredentialStore) -> String? {
    useSamePortalCredentials ? portalStore.loadPassword() : loadPassword()
  }

  /// 出席システムへログインするための認証情報が揃っているか
  func isReady(portalStore: PortalCredentialStore) -> Bool {
    effectiveUserID(portalStore: portalStore) != nil && effectivePassword(portalStore: portalStore) != nil
  }
}
