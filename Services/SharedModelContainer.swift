//
//  SharedModelContainer.swift
//  CIT-Campus-3D
//
//  アプリ本体とウィジェット拡張で同一のSwiftDataストアを共有するためのヘルパー．
//  App Group コンテナ内にストアを置くことで，両者から同じ時間割データを読めるようにする．
//  このファイルはアプリ・ウィジェット両ターゲットに含める（共有コア）．
//

import Foundation
import SwiftData

/// アプリとウィジェットで共有するSwiftDataコンテナの生成・移行を担う
enum SharedModelContainer {

  /// App Group の識別子（アプリ・ウィジェット両方の Signing & Capabilities で有効化する）
  static let appGroupIdentifier = "group.com.HR.CIT-Campus-3D"

  /// CloudKitコンテナの識別子．iOS版・Mac版で同一にして同じApple IDの端末間で時間割を同期する．
  /// 両アプリの Signing & Capabilities で iCloud(CloudKit) にこのコンテナを追加すること．
  static let cloudKitContainerID = "iCloud.com.HR.CIT-Campus-3D"

  /// 共有ストアのファイル名（旧デフォルトストアと同名にして移行時のファイル対応を単純化する）
  private static let storeFileName = "default.store"

  /// SQLiteストアに付随する補助ファイルの接尾辞（本体・WAL・共有メモリ）
  private static let storeFileSuffixes = ["", "-wal", "-shm"]

  /// App Group コンテナ内の共有ストアURL（App Groupが利用できない場合はnil）
  static var sharedStoreURL: URL? {
    FileManager.default
      .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
      .appending(path: storeFileName)
  }

  /// 共有ストアを指すModelContainerを生成する．
  /// まずCloudKit同期つきで試し，権限・iCloud未設定などで失敗した場合はローカルのみにフォールバックする
  /// （CloudKitが未設定の環境でもアプリが必ず起動するようにするため）．
  /// - Returns: 生成したModelContainer
  /// - Throws: ローカルのコンテナ生成にも失敗した場合
  /// CloudKit同期つきのコンテナを生成できたか（同期インジケータの表示判定に使う）
  static private(set) var isCloudKitEnabled = false

  static func make() throws -> ModelContainer {
    // iCloudが利用可能なとき（アカウントにサインイン済み＋iCloudエンタイトルメントあり）だけCloudKit同期を有効にする．
    // ubiquityIdentityTokenはiCloud未ログイン・権限未設定のいずれでもnilになる．
    // これを満たさない環境（権限未追加のMac・iCloud未サインイン・Simulator等）でCloudKitを有効にすると，
    // ModelContainer生成後にCloudKitのセットアップが非同期でSIGTRAPし，try?では捕捉できずクラッシュするため必ずガードする．
    let isICloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    if isICloudAvailable, let container = try? makeContainer(cloudKitEnabled: true) {
      isCloudKitEnabled = true
      return container
    }
    isCloudKitEnabled = false
    return try makeContainer(cloudKitEnabled: false)
  }

  /// CloudKit同期の有無を指定してModelContainerを生成する．
  /// App Groupが使える場合はその共有ストア（アプリ・ウィジェット共用）を，使えない場合はアプリ既定の場所を用いる．
  /// - Parameter cloudKitEnabled: trueでCloudKitプライベートDBと同期する
  private static func makeContainer(cloudKitEnabled: Bool) throws -> ModelContainer {
    let cloudKitDatabase: ModelConfiguration.CloudKitDatabase =
      cloudKitEnabled ? .private(cloudKitContainerID) : .none
    let configuration: ModelConfiguration
    if let sharedStoreURL {
      // App Group内の共有ストアを使う（アプリ・ウィジェットで同一）
      configuration = ModelConfiguration(url: sharedStoreURL, cloudKitDatabase: cloudKitDatabase)
    } else {
      // App Group未設定時（macOS等）はアプリ既定の場所を使う
      configuration = ModelConfiguration(cloudKitDatabase: cloudKitDatabase)
    }
    return try ModelContainer(
      for: Lecture.self, Assignment.self, ClassChange.self,
      configurations: configuration
    )
  }

  /// 旧デフォルトストア（App Group導入前のアプリ既定の場所）から共有ストアへ一度だけ移行する．
  /// 既に共有ストアが存在する場合や，旧ストアが無い場合（新規インストール）は何もしない．
  /// アプリ本体の起動時に，`make()` より前に呼ぶこと（旧ストアはアプリのサンドボックスにあるため，
  /// ウィジェット側からは移行できない）．
  static func migrateDefaultStoreIfNeeded() {
    let fileManager = FileManager.default

    // App Groupが使えない（権限未設定）なら移行先が無いので何もしない
    guard let sharedStoreURL else { return }

    // 既に共有ストアがある＝移行済み（または既に共有ストアで運用中）なら何もしない
    guard !fileManager.fileExists(atPath: sharedStoreURL.path) else { return }

    // 旧デフォルトストアの場所（Application Support/default.store）
    guard
      let applicationSupport = try? fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: false
      )
    else {
      return
    }
    let oldStoreURL = applicationSupport.appending(path: storeFileName)

    // 旧ストアが無ければ新規インストール扱いで移行不要
    guard fileManager.fileExists(atPath: oldStoreURL.path) else { return }

    // 本体・WAL・共有メモリの3ファイルを共有ストアの場所へコピーする．
    // 失敗しても致命的ではない（空の共有ストアで起動し，必要なら再インポートできる）ため，
    // エラーは握りつぶしつつ可能な範囲で移行する
    let sharedDirectory = sharedStoreURL.deletingLastPathComponent()
    for suffix in storeFileSuffixes {
      let source = applicationSupport.appending(path: "\(storeFileName)\(suffix)")
      let destination = sharedDirectory.appending(path: "\(storeFileName)\(suffix)")
      guard fileManager.fileExists(atPath: source.path) else { continue }
      try? fileManager.copyItem(at: source, to: destination)
    }
  }
}
