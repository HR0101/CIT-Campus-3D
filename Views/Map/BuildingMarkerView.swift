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
      .shadow(radius: MarkerConstants.shadowRadius)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    HStack(spacing: 12) {
      BuildingMarkerView(building: .building1)
      BuildingMarkerView(building: .building5)
    }
  }
}
