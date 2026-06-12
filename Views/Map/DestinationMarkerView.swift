//
//  DestinationMarkerView.swift
//  CIT-Campus-3D
//
//  目的の講義棟を示すカスタムピン．パルスアニメーションで視線を誘導する．
//

import SwiftUI

/// 目的地ハイライト用のパルスアニメーション付きマーカー
struct DestinationMarkerView: View {

  /// マーカーの見た目に関する定数
  private enum MarkerConstants {
    /// 中心円の直径
    static let coreSize: CGFloat = 44
    /// パルスの最大拡大率
    static let pulseMaxScale: CGFloat = 2.4
    /// パルス1周期の秒数
    static let pulseDuration: Double = 1.6
    /// アイコンのフォントサイズ
    static let iconFontSize: CGFloat = 18
    /// 白フチの太さ
    static let strokeWidth: CGFloat = 2
    /// 発光シャドウの半径
    static let glowRadius: CGFloat = 10
  }

  /// パルスアニメーションの進行フラグ
  @State private var isPulsing = false

  var body: some View {
    ZStack {
      // 外側へ広がって消えるパルス
      Circle()
        .fill(Color.cyan.opacity(0.35))
        .frame(width: MarkerConstants.coreSize, height: MarkerConstants.coreSize)
        .scaleEffect(isPulsing ? MarkerConstants.pulseMaxScale : 1.0)
        .opacity(isPulsing ? 0 : 0.8)

      // 中心のピン本体
      Image(systemName: "graduationcap.fill")
        .font(.system(size: MarkerConstants.iconFontSize, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: MarkerConstants.coreSize, height: MarkerConstants.coreSize)
        .background(Circle().fill(Color.cyan))
        .overlay(Circle().stroke(.white, lineWidth: MarkerConstants.strokeWidth))
        .shadow(color: .cyan.opacity(0.8), radius: MarkerConstants.glowRadius)
    }
    .onAppear {
      withAnimation(
        .easeOut(duration: MarkerConstants.pulseDuration)
        .repeatForever(autoreverses: false)
      ) {
        isPulsing = true
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    DestinationMarkerView()
  }
}
