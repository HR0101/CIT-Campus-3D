//
//  RouteSummaryCard.swift
//  CIT-Campus-3D
//
//  探索した徒歩経路の所要時間・距離を表示するカード．
//  次の授業の場合は，教室の階数分の昇降時間を加えた「教室までの時間」を示す．
//

import MapKit
import SwiftUI

/// 経路サマリー（目的地名・所要時間・距離）の表示カード
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
  /// 徒歩以外に加える時間（秒）．教室階までの昇降時間など．既定は0
  var extraSeconds: TimeInterval = 0
  /// 階数などの補足（例: 3階．無ければnil）
  var floorNote: String?

  /// 教室までの合計所要時間（徒歩＋昇降）
  private var totalSeconds: Double {
    route.expectedTravelTime + extraSeconds
  }

  /// 所要時間の表示文字列．昇降時間を含む場合は「教室まで」と明示する
  private var travelTimeText: String {
    let minutes = Int(ceil(totalSeconds / FormatConstants.secondsPerMinute))
    return extraSeconds > 0 ? "教室まで約\(minutes)分" : "徒歩約\(minutes)分"
  }

  /// 距離の表示文字列（例: 320m / 1.2km）
  private var distanceText: String {
    if route.distance >= FormatConstants.metersPerKilometer {
      return String(format: "%.1fkm", route.distance / FormatConstants.metersPerKilometer)
    }
    return "\(Int(route.distance))m"
  }

  /// タイトル（棟名＋階数）
  private var titleText: String {
    guard let floorNote else { return destinationName }
    return "\(destinationName)（\(floorNote)）"
  }

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: "figure.walk")
        .font(.title2)
        .foregroundStyle(.cyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(titleText)
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
