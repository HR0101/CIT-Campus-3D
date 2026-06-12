//
//  RouteSummaryCard.swift
//  CIT-Campus-3D
//
//  探索した徒歩経路の所要時間・距離を表示するカード．
//

import MapKit
import SwiftUI

/// 経路サマリー（目的地名・徒歩時間・距離）の表示カード
struct RouteSummaryCard: View {

  /// 表示フォーマットに関する定数
  private enum FormatConstants {
    /// 1分あたりの秒数
    static let secondsPerMinute: Double = 60
    /// km表示に切り替える境界（メートル）
    static let metersPerKilometer: Double = 1_000
    /// カードの角丸半径
    static let cornerRadius: CGFloat = 14
  }

  /// 目的地の棟名
  let destinationName: String
  /// 探索済みの経路
  let route: MKRoute

  /// 所要時間の表示文字列（例: 徒歩約5分）
  private var travelTimeText: String {
    let minutes = Int(ceil(route.expectedTravelTime / FormatConstants.secondsPerMinute))
    return "徒歩約\(minutes)分"
  }

  /// 距離の表示文字列（例: 320m / 1.2km）
  private var distanceText: String {
    if route.distance >= FormatConstants.metersPerKilometer {
      return String(format: "%.1fkm", route.distance / FormatConstants.metersPerKilometer)
    }
    return "\(Int(route.distance))m"
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "figure.walk")
        .font(.title2)
        .foregroundStyle(.cyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(destinationName)
          .font(.headline)
          .foregroundStyle(.white)
        Text("\(travelTimeText)・\(distanceText)")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FormatConstants.cornerRadius))
    .environment(\.colorScheme, .dark)
  }
}
