//
//  NotificationService.swift
//  CIT-Campus-3D
//
//  ローカル通知（授業前リマインダー・出発リマインダー）の許可管理と予約を担う．
//  予約は「次の授業を中心とした直近の授業群」へ毎回まとめて作り直す方式とする．
//

import Foundation
import Observation
import UserNotifications

/// ローカル通知の管理を担うサービス
@MainActor
@Observable
final class NotificationService {

  /// 通知に関する定数
  private enum NotificationConstants {
    /// 授業前リマインダーをまとめて予約する最大件数（iOSの保留上限64件に対し余裕を持たせる）
    static let maxClassReminders = 16
    /// 授業前リマインダーの通知ID接頭辞
    static let classReminderPrefix = "class-reminder-"
    /// 出発リマインダーの通知ID
    static let departureReminderID = "departure-reminder"
  }

  /// 現在の通知許可状態
  private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

  private let center = UNUserNotificationCenter.current()

  /// 現在の許可状態を取得して反映する
  func refreshAuthorizationStatus() async {
    let settings = await center.notificationSettings()
    authorizationStatus = settings.authorizationStatus
  }

  /// 通知の許可をリクエストする（初回のみダイアログが表示される）
  /// - Returns: 許可されたかどうか
  @discardableResult
  func requestAuthorization() async -> Bool {
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      await refreshAuthorizationStatus()
      return granted
    } catch {
      await refreshAuthorizationStatus()
      return false
    }
  }

  /// 予約済みの通知をすべて取り消す
  func cancelAll() {
    center.removeAllPendingNotificationRequests()
  }

  /// 直近の授業群に対して通知を予約し直す
  /// - Parameters:
  ///   - upcoming: これから始まる授業（時刻の早い順）
  ///   - departureTravelTime: 次の授業の講義棟までの徒歩所要時間（秒．不明ならnil）
  ///   - settings: ユーザー設定
  func reschedule(
    upcoming: [NextLectureResult],
    departureTravelTime: TimeInterval?,
    settings: AppSettings
  ) {
    // 常に作り直す方式のため，まず既存の予約を消す
    center.removeAllPendingNotificationRequests()

    // 許可されていない場合は何も予約しない
    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      return
    }

    let now = Date()

    // 授業前リマインダー: 直近の複数授業へまとめて予約する
    if settings.enableClassReminder {
      scheduleClassReminders(upcoming: upcoming, offsetMinutes: settings.classReminderOffsetMinutes, now: now)
    }

    // 出発リマインダー: 次の授業1件のみ（徒歩時間が判明している場合）
    if settings.enableDepartureReminder, let travelTime = departureTravelTime, let next = upcoming.first {
      scheduleDepartureReminder(
        for: next,
        travelTime: travelTime,
        bufferMinutes: settings.departureBufferMinutes,
        now: now
      )
    }
  }

  // MARK: - Private

  /// 授業前リマインダーを予約する
  private func scheduleClassReminders(
    upcoming: [NextLectureResult],
    offsetMinutes: Int,
    now: Date
  ) {
    let offsetSeconds = Double(offsetMinutes) * 60
    for (index, result) in upcoming.prefix(NotificationConstants.maxClassReminders).enumerated() {
      let fireDate = result.startDate.addingTimeInterval(-offsetSeconds)
      // 通知時刻がすでに過ぎている授業はスキップする
      guard fireDate > now else { continue }

      let periodName = result.lecture.classPeriod?.displayName ?? "\(result.lecture.period)限"
      let dayText = result.isToday ? "今日" : "\(result.lecture.weekday.shortName)曜"
      let body = "\(dayText) \(periodName)「\(result.lecture.subjectName)」（\(result.lecture.placeText)）がまもなく始まります．"

      scheduleNotification(
        identifier: "\(NotificationConstants.classReminderPrefix)\(index)",
        title: "まもなく授業です",
        body: body,
        fireDate: fireDate
      )
    }
  }

  /// 出発リマインダーを予約する
  private func scheduleDepartureReminder(
    for result: NextLectureResult,
    travelTime: TimeInterval,
    bufferMinutes: Int,
    now: Date
  ) {
    let bufferSeconds = Double(bufferMinutes) * 60
    let fireDate = result.startDate.addingTimeInterval(-travelTime - bufferSeconds)
    // 出発時刻がすでに過ぎている場合はスキップする
    guard fireDate > now else { return }

    let walkMinutes = max(1, Int(ceil(travelTime / 60)))
    let place = result.lecture.building?.displayName ?? result.lecture.placeText
    let body = "そろそろ出発：\(place)まで徒歩約\(walkMinutes)分です．「\(result.lecture.subjectName)」に間に合います．"

    scheduleNotification(
      identifier: NotificationConstants.departureReminderID,
      title: "出発の時間です",
      body: body,
      fireDate: fireDate
    )
  }

  /// 指定時刻に発火するローカル通知を予約する
  private func scheduleNotification(
    identifier: String,
    title: String,
    body: String,
    fireDate: Date
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute],
      from: fireDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    center.add(request)
  }
}
