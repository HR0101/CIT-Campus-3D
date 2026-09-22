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

  /// 文字サイズ設定（特大サイズではボタンを下段へ折り返す）
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize, actionTitle != nil {
        // 特大文字サイズ: メッセージとボタンが横で取り合って切れないよう縦に積む
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 12) {
            iconView
            messageView
          }
          actionButton
        }
      } else {
        HStack(spacing: 12) {
          iconView
          messageView
          actionButton
        }
      }
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
  }

  /// 先頭アイコン
  private var iconView: some View {
    Image(systemName: systemImageName)
      .font(.system(size: BannerConstants.iconSize, weight: .semibold))
      .foregroundStyle(accentColor)
  }

  /// メッセージ本文（常に全文を折り返して表示する）
  private var messageView: some View {
    Text(message)
      .font(.footnote)
      .foregroundStyle(.primary)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// アクションボタン（タイトルと処理がある場合のみ）
  @ViewBuilder
  private var actionButton: some View {
    if let actionTitle, let action {
      Button(action: action) {
        Text(actionTitle)
          .font(.footnote.bold())
          .foregroundStyle(accentColor)
      }
    }
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
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BannerConstants.cornerRadius))
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
