//
//  CloudSyncMonitor.swift
//  CIT-Campus-3D
//
//  SwiftData（NSPersistentCloudKitContainer）のCloudKit同期イベントを監視し，
//  同期状態（同期中／完了／エラー）をSwiftUIへ公開する．
//

import CoreData
import Foundation
import Observation

/// CloudKit同期の状態を監視して公開するサービス
@MainActor
@Observable
final class CloudSyncMonitor {

  /// 同期の状態
  enum Status {
    /// アイドル（同期完了・待機中）
    case idle
    /// 同期中（取り込み／書き出し／初期設定のいずれか進行中）
    case syncing
    /// 直近の同期でエラーが発生
    case error
  }

  /// 現在の同期状態
  private(set) var status: Status = .idle

  /// 最後に同期が完了した時刻（未同期ならnil）
  private(set) var lastSyncDate: Date?

  /// 通知監視のトークン（観測対象外）
  @ObservationIgnored private var observer: NSObjectProtocol?

  init() {
    // CloudKitコンテナの同期イベントを購読する．キューを.mainにし，UI更新を主スレッドで行う
    observer = NotificationCenter.default.addObserver(
      forName: NSPersistentCloudKitContainer.eventChangedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      let event = notification.userInfo?[
        NSPersistentCloudKitContainer.eventNotificationUserInfoKey
      ] as? NSPersistentCloudKitContainer.Event
      // .mainキューで届くため主スレッド上．MainActorとして同期状態を更新する
      MainActor.assumeIsolated {
        self?.apply(event)
      }
    }
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  /// 同期イベントを状態へ反映する．
  /// endDateがnilなら進行中，非nilなら完了（errorの有無で成否を判定）．
  private func apply(_ event: NSPersistentCloudKitContainer.Event?) {
    guard let event else { return }
    if event.endDate == nil {
      status = .syncing
    } else if event.error != nil {
      status = .error
    } else {
      status = .idle
      lastSyncDate = event.endDate
    }
  }
}
