//
//  StorageErrorView.swift
//  CIT-Campus-3D
//
//  SwiftDataの初期化に失敗した場合のフォールバック画面．
//  白画面やクラッシュではなく，状況と対処法を必ずユーザーへ伝える．
//

import SwiftUI

/// データ保存領域の初期化失敗を伝える画面
struct StorageErrorView: View {

  /// 失敗の詳細メッセージ
  let message: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: "externaldrive.badge.exclamationmark")
        .font(.system(size: 48))
        .foregroundStyle(.orange)

      Text("データの保存領域を初期化できませんでした")
        .font(.headline)
        .multilineTextAlignment(.center)

      Text(message)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      Text("アプリを再起動しても解決しない場合は，再インストールをお試しください．")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
  }
}

#Preview {
  StorageErrorView(message: "ModelContainerの生成に失敗しました．")
    .preferredColorScheme(.dark)
}
