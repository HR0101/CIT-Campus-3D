//
//  CampusTheme.swift
//  CIT-Campus-3D
//
//  アプリ全体で共有する配色（Ink ニュートラルランプ＋単一インディゴ・インクアクセント）・
//  4ptスペーシング・角丸・マップ上カードの共通スタイル定義．
//

import SwiftUI
import UIKit

/// 構内マップ・製図インクの世界観に基づく統一デザインシステム
enum CampusTheme {

  // MARK: - 単一アクセント（Indigo Ink）

  /// メインアクセント（Light: #3730A3 / Dark: #818CF8）
  static let accent = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.506, green: 0.549, blue: 0.973, alpha: 1.0)
      : UIColor(red: 0.216, green: 0.188, blue: 0.639, alpha: 1.0)
  })

  /// バッジ・ピル塗り用の深いインディゴインク（白文字で 4.5:1 以上を確保）
  static let accentFill = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.310, green: 0.275, blue: 0.898, alpha: 1.0)
      : UIColor(red: 0.216, green: 0.188, blue: 0.639, alpha: 1.0)
  })

  /// 控えめなハイライト面
  static let accentTint = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.506, green: 0.549, blue: 0.973, alpha: 0.16)
      : UIColor(red: 0.216, green: 0.188, blue: 0.639, alpha: 0.10)
  })

  // MARK: - Ink ニュートラルランプ

  static let cardSurface = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.067, green: 0.078, blue: 0.110, alpha: 0.92)
      : UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 0.94)
  })

  static let raisedSurface = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.102, green: 0.118, blue: 0.157, alpha: 1.0)
      : UIColor(red: 0.925, green: 0.937, blue: 0.957, alpha: 1.0)
  })

  static let textPrimary = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.933, green: 0.941, blue: 0.961, alpha: 1.0)
      : UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 1.0)
  })

  static let textSecondary = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.639, green: 0.663, blue: 0.722, alpha: 1.0)
      : UIColor(red: 0.294, green: 0.333, blue: 0.396, alpha: 1.0)
  })

  static let textMuted = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.478, green: 0.510, blue: 0.588, alpha: 1.0)
      : UIColor(red: 0.420, green: 0.455, blue: 0.529, alpha: 1.0)
  })

  /// ニュートラルテキスト色の 8% ヘアライン境界
  static let hairline = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.933, green: 0.941, blue: 0.961, alpha: 0.10)
      : UIColor(red: 0.067, green: 0.094, blue: 0.153, alpha: 0.08)
  })

  // MARK: - セマンティックカラー（ランプ調和トーン）

  static let positive = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.298, green: 0.765, blue: 0.541, alpha: 1.0)
      : UIColor(red: 0.086, green: 0.639, blue: 0.290, alpha: 1.0)
  })

  static let warning = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.961, green: 0.620, blue: 0.043, alpha: 1.0)
      : UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1.0)
  })

  static let danger = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0.898, green: 0.282, blue: 0.302, alpha: 1.0)
      : UIColor(red: 0.863, green: 0.149, blue: 0.149, alpha: 1.0)
  })

  // MARK: - 4pt スケール定数

  static let cardRadius: CGFloat = 12
  static let controlRadius: CGFloat = 8
  static let tagRadius: CGFloat = 4
}

extension View {
  /// 地図上に浮かぶ情報カード共通の静かなサーフェス・ヘアライン装飾
  func campusFloatingCard(cornerRadius: CGFloat = CampusTheme.cardRadius) -> some View {
    background(CampusTheme.cardSurface, in: RoundedRectangle(cornerRadius: cornerRadius))
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(CampusTheme.hairline, lineWidth: 1)
      )
      .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
  }
}
