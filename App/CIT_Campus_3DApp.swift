//
//  CIT_Campus_3DApp.swift
//  CIT-Campus-3D
//
//  アプリのエントリポイント．SwiftDataコンテナの生成・共有サービスの注入・外観設定の適用を担う．
//  コンテナ生成に失敗した場合はクラッシュさせず，フォールバック画面を表示する．
//

import SwiftData
import SwiftUI

@main
struct CIT_Campus_3DApp: App {

  /// SwiftDataのコンテナ（生成失敗時はnil）
  private let modelContainer: ModelContainer?

  /// コンテナ生成失敗時のエラーメッセージ
  private let containerErrorMessage: String?

  /// ユーザー設定（経路表示・通知）
  @State private var appSettings = AppSettings()

  /// 通知サービス（許可管理・予約）
  @State private var notificationService = NotificationService()

  init() {
    do {
      modelContainer = try ModelContainer(for: Lecture.self)
      containerErrorMessage = nil
    } catch {
      modelContainer = nil
      containerErrorMessage = error.localizedDescription
    }
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if let modelContainer {
          ContentView()
            .modelContainer(modelContainer)
        } else {
          StorageErrorView(message: containerErrorMessage ?? "不明なエラーが発生しました．")
        }
      }
      // 共有サービスを全画面へ注入する
      .environment(appSettings)
      .environment(notificationService)
      // 外観設定（システム連動／ライト／ダーク）に従う．
      // .systemのときはnilを渡して端末（スマホ）のダーク／ライト設定に自動で従う
      .preferredColorScheme(appSettings.appearance.colorScheme)
    }
  }
}
