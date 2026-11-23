//
//  DestinationMarkerView.swift
//  CIT-Campus-3D
//
//  目的の講義棟を示すカスタムピン．
//  常時発光パルスを排し，単一インディゴアクセントと静かな外周リングで優先度を示す．
//

import SwiftUI

/// 目的地ハイライト用の建築製図風マーカー
struct DestinationMarkerView: View {

  /// マーカーの見た目に関する定数（4ptスケール）
  private enum MarkerConstants {
    static let outerRingSize: CGFloat = 52
    static let coreSize: CGFloat = 40
    static let iconFontSize: CGFloat = 16
    static let strokeWidth: CGFloat = 2
  }

  var body: some View {
    ZStack {
      // 位置の焦点を整える静かな外周ヘアラインリング
      Circle()
        .fill(CampusTheme.accent.opacity(0.14))
        .overlay(
          Circle().stroke(CampusTheme.accent.opacity(0.42), lineWidth: 1)
        )
        .frame(width: MarkerConstants.outerRingSize, height: MarkerConstants.outerRingSize)

      // 中心のピン本体
      Image(systemName: "graduationcap.fill")
        .font(.system(size: MarkerConstants.iconFontSize, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: MarkerConstants.coreSize, height: MarkerConstants.coreSize)
        .background(Circle().fill(CampusTheme.accentFill))
        .overlay(Circle().stroke(.white, lineWidth: MarkerConstants.strokeWidth))
        .shadow(color: .black.opacity(0.24), radius: 6, y: 2)
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    DestinationMarkerView()
  }
}
