//
//  CIT_Campus_3DApp.swift
//  CIT-Campus-3D
//
//  アプリのエントリポイント．SwiftDataコンテナの生成とダークモード固定を担う．
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
      // ダークモード基調のデザイン要件のため，常にダーク表示に固定する
      .preferredColorScheme(.dark)
    }
  }
}
