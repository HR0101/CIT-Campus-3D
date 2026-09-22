//
//  CloudSyncIndicator.swift
//  CIT-Campus-3D
//
//  iCloud（CloudKit）同期の状態を示す小さなインジケータ．
//  同期中はスピナー＋「iCloud同期中」，完了はチェッククラウド，エラーは警告，
//  CloudKit未設定（ローカルのみ）はスラッシュ付きクラウドを表示する．
//

import SwiftUI

/// iCloud同期の状態インジケータ（ツールバー等に置く想定）
struct CloudSyncIndicator: View {

  @Environment(CloudSyncMonitor.self) private var monitor

  var body: some View {
    Group {
      if !SharedModelContainer.isCloudKitEnabled {
        // iCloud未設定・未ログイン等でローカル保存のみ
        Image(systemName: "icloud.slash")
          .foregroundStyle(.secondary)
          .help("iCloud同期は無効です（この端末にのみ保存）")
          .accessibilityLabel("iCloud同期は無効")
      } else {
        switch monitor.status {
        case .syncing:
          HStack(spacing: 4) {
            ProgressView()
              .controlSize(.small)
            Text("iCloud同期中")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .accessibilityLabel("iCloud同期中")
        case .error:
          Image(systemName: "exclamationmark.icloud")
            .foregroundStyle(.orange)
            .help("iCloud同期でエラーが発生しました")
            .accessibilityLabel("iCloud同期エラー")
        case .idle:
          Image(systemName: "checkmark.icloud")
            .foregroundStyle(.secondary)
            .help(lastSyncHelpText)
            .accessibilityLabel("iCloud同期済み")
        }
      }
    }
  }

  /// 最終同期時刻のツールチップ文言
  private var lastSyncHelpText: String {
    guard let date = monitor.lastSyncDate else { return "iCloud同期済み" }
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return "最終同期 \(formatter.string(from: date))"
  }
}
