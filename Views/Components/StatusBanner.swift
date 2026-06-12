//
//  StatusBanner.swift
//  CIT-Campus-3D
//
//  位置情報・経路探索の状態をユーザーへ伝える共通バナー．
//  「いま何が起きていて，次に何をすればよいか」を必ず示すことで信頼性を担保する．
//

import SwiftUI

/// 状態通知バナー（エラー時はアクションボタン付き）
struct StatusBanner: View {

  /// バナーの見た目に関する定数
  private enum BannerConstants {
    static let cornerRadius: CGFloat = 14
    static let iconSize: CGFloat = 20
  }

  /// 先頭に表示するSF Symbols名
  let systemImageName: String
  /// 通知メッセージ
  let message: String
  /// アクセントカラー（情報: シアン，警告: オレンジなど）
  let accentColor: Color
  /// アクションボタンのタイトル（nilならボタン非表示）
  var actionTitle: String?
  /// アクションボタンの処理
  var action: (() -> Void)?

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImageName)
        .font(.system(size: BannerConstants.iconSize, weight: .semibold))
        .foregroundStyle(accentColor)

      Text(message)
        .font(.footnote)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)

      if let actionTitle, let action {
        Button(action: action) {
          Text(actionTitle)
            .font(.footnote.bold())
            .foregroundStyle(accentColor)
        }
      }
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
    .environment(\.colorScheme, .dark)
  }
}

/// 進行中処理を示すバナー（スピナー付き）
struct ProgressBanner: View {

  /// バナーの見た目に関する定数
  private enum BannerConstants {
    static let cornerRadius: CGFloat = 14
  }

  /// 進行中メッセージ
  let message: String

  var body: some View {
    HStack(spacing: 12) {
      ProgressView()
        .tint(.cyan)

      Text(message)
        .font(.footnote)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
    .environment(\.colorScheme, .dark)
  }
}

#Preview("エラーバナー") {
  ZStack {
    Color.black.ignoresSafeArea()
    VStack(spacing: 12) {
      StatusBanner(
        systemImageName: "location.slash.fill",
        message: "位置情報の利用が許可されていません．",
        accentColor: .orange,
        actionTitle: "設定を開く",
        action: {}
      )
      ProgressBanner(message: "経路を探索しています…")
    }
    .padding()
  }
}
