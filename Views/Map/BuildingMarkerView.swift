//
//  BuildingMarkerView.swift
//  CIT-Campus-3D
//
//  すべての講義棟を示す常設マーカー．
//  目的地のパルスピン（DestinationMarkerView）より控えめな見た目にして，
//  「次の授業の棟」との視覚的な優先順位をつける．
//

import SwiftUI

/// 講義棟の常設マーカー（棟番号入りの小さなバッジ）
struct BuildingMarkerView: View {

  /// マーカーの見た目に関する定数
  private enum MarkerConstants {
    /// バッジの直径
    static let badgeSize: CGFloat = 26
    /// フチの太さ
    static let strokeWidth: CGFloat = 1
    /// 影の半径
    static let shadowRadius: CGFloat = 3
  }

  /// 表示する講義棟
  let building: CampusBuilding

  /// 棟番号の表示文字列（例: "5号館" → "5"）
  private var numberText: String {
    let digits = building.name.prefix(while: { $0.isNumber })
    return digits.isEmpty ? String(building.name.prefix(1)) : String(digits)
  }

  var body: some View {
    Text(numberText)
      .font(.caption.bold())
      .foregroundStyle(.white)
      .frame(width: MarkerConstants.badgeSize, height: MarkerConstants.badgeSize)
      .background(Circle().fill(Color(white: 0.22)))
      .overlay(Circle().stroke(Color.cyan.opacity(0.6), lineWidth: MarkerConstants.strokeWidth))
      // 明るいベース地図（positron）でも輪郭が沈まないよう定義された暗い影を付ける
      .shadow(color: .black.opacity(0.45), radius: MarkerConstants.shadowRadius)
  }
}

/// 棟バッジ＋名称ラベルのアノテーション表示（MapLibreマーカー用）
struct BuildingAnnotationView: View {

  /// 表示する講義棟
  let building: CampusBuilding

  var body: some View {
    VStack(spacing: 2) {
      BuildingMarkerView(building: building)
      Text(building.displayName)
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.black.opacity(0.7), in: Capsule())
        // 明るいベース地図でも縁が分かるよう細い境界線を足す
        .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    HStack(spacing: 12) {
      BuildingAnnotationView(building: .building1)
      BuildingAnnotationView(building: .building5)
    }
  }
}
