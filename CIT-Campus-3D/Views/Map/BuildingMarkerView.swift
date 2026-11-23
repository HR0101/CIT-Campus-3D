//
//  BuildingMarkerView.swift
//  CIT-Campus-3D
//
//  すべての講義棟を示す常設マーカー．
//  目的地のピン（DestinationMarkerView）より控えめな設計図風マークにして，
//  「次の授業の棟」との視覚的な優先順位をつける．
//

import SwiftUI

/// 講義棟の常設マーカー（棟番号入りの小さなバッジ）
struct BuildingMarkerView: View {

  /// マーカーの見た目に関する定数（4ptスケール）
  private enum MarkerConstants {
    static let badgeSize: CGFloat = 24
    static let strokeWidth: CGFloat = 1
    static let shadowRadius: CGFloat = 2
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
      .font(.caption2.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(.white)
      .frame(width: MarkerConstants.badgeSize, height: MarkerConstants.badgeSize)
      .background(Circle().fill(Color(red: 0.102, green: 0.118, blue: 0.157)))
      .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: MarkerConstants.strokeWidth))
      .shadow(color: .black.opacity(0.30), radius: MarkerConstants.shadowRadius, y: 1)
  }
}

/// 棟バッジ＋名称ラベルのアノテーション表示（MapLibreマーカー用）
struct BuildingAnnotationView: View {

  /// 表示する講義棟
  let building: CampusBuilding

  var body: some View {
    VStack(spacing: 4) {
      BuildingMarkerView(building: building)
      Text(building.displayName)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(
          Color(red: 0.067, green: 0.078, blue: 0.110).opacity(0.86),
          in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
        )
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
