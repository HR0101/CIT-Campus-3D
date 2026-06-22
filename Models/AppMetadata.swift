//
//  AppMetadata.swift
//  CIT-Campus-3D
//
//  アプリ名・バージョン・連絡先・法的リンクなど，画面や法的文書から参照する
//  メタ情報を1か所に集約する．公開前に差し替えるべき項目は placeholder として明示する．
//

import Foundation

/// アプリのメタ情報（法的文書・設定画面で共有する）
enum AppMetadata {

  /// アプリの表示名
  static let displayName = "CIT Campus 3D"

  /// 公開バージョン（CFBundleShortVersionString．例: 1.0）
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
  }

  /// ビルド番号（CFBundleVersion）
  static var build: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
  }

  // MARK: - 公開前に実値へ差し替えるプレースホルダ

  /// 開発者（提供者）名．App Store公開前に実名／屋号へ差し替える
  static let developerName = "（開発者名）"

  /// 問い合わせ先．App Store公開前に実際の連絡先へ差し替える
  static let contactEmail = "（連絡先メール）"

  // MARK: - 日付・リンク

  /// 法的文書の最終更新日（文書を改定したら更新する）
  static let legalLastUpdated = "最終更新日: 2026年6月22日"

  /// 著作権表示（フッタ等で使用）
  static var copyright: String {
    "© 2026 \(developerName)"
  }

  /// OpenStreetMapの著作権ページ（地図データ帰属表示のリンク先）
  static let openStreetMapCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
}
