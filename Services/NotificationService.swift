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
    /// 課題リマインダーをまとめて予約する最大件数
    static let maxAssignmentReminders = 16
    /// 課題リマインダーの通知ID接頭辞
    static let assignmentReminderPrefix = "assignment-reminder-"
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
    // 常に作り直す方式のため，まず授業・出発の予約だけを消す
    // （課題リマインダーは別系統なので消さない）
    center.removePendingNotificationRequests(withIdentifiers: classReminderIdentifiers())

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

  /// 課題の締切リマインダーを予約し直す（授業リマインダーとは独立に管理する）
  /// - Parameters:
  ///   - assignments: 取り込み済みの課題（未完了・締切が未来のものを対象にする）
  ///   - settings: ユーザー設定
  func rescheduleAssignmentReminders(assignments: [Assignment], settings: AppSettings) {
    // 課題リマインダーの予約だけを消す
    center.removePendingNotificationRequests(withIdentifiers: assignmentReminderIdentifiers())

    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      return
    }
    guard settings.enableAssignmentReminder else { return }

    let now = Date()
    let offsetSeconds = Double(settings.assignmentReminderOffsetHours) * 3600

    // 未完了・締切が未来の課題を，締切の早い順に並べる
    let targets = assignments
      .filter { !$0.isDone }
      .compactMap { assignment -> (Assignment, Date)? in
        guard let due = assignment.dueDate, due > now else { return nil }
        return (assignment, due)
      }
      .sorted { $0.1 < $1.1 }
      .prefix(NotificationConstants.maxAssignmentReminders)

    for (index, pair) in targets.enumerated() {
      let (assignment, due) = pair
      let fireDate = due.addingTimeInterval(-offsetSeconds)
      // 通知時刻がすでに過ぎている課題はスキップする
      guard fireDate > now else { continue }

      let dueText = assignmentDueText(due)
      let courseText = assignment.courseName.isEmpty ? "" : "（\(assignment.courseName)）"
      let body = "課題「\(assignment.title)」\(courseText)の締切は \(dueText) です．"

      scheduleNotification(
        identifier: "\(NotificationConstants.assignmentReminderPrefix)\(index)",
        title: "課題の締切が近づいています",
        body: body,
        fireDate: fireDate
      )
    }
  }

  // MARK: - Private

  /// 授業・出発リマインダーの通知ID一覧（限定削除に使う）
  private func classReminderIdentifiers() -> [String] {
    var identifiers = (0..<NotificationConstants.maxClassReminders)
      .map { "\(NotificationConstants.classReminderPrefix)\($0)" }
    identifiers.append(NotificationConstants.departureReminderID)
    return identifiers
  }

  /// 課題リマインダーの通知ID一覧（限定削除に使う）
  private func assignmentReminderIdentifiers() -> [String] {
    (0..<NotificationConstants.maxAssignmentReminders)
      .map { "\(NotificationConstants.assignmentReminderPrefix)\($0)" }
  }

  /// 課題の締切表示文字列（例: 6/24 17:00）
  private func assignmentDueText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
  }

  /// 授業前リマインダーを予約する
  private func scheduleClassReminders(
    upcoming: [NextLectureResult],
    offsetMinutes: Int,
    now: Date
  ) {
    let offsetSeconds = Double(offsetMinutes) * 60
    // 通知は「開始の offsetMinutes 前」に飛ぶため，発火時点の残り時間は設定値と一致する．
    // それを「あと何分か」としてそのまま本文に使う（0分以下なら「まもなく」とする）
    let startsInText = offsetMinutes > 0 ? "約\(offsetMinutes)分後" : "まもなく"
    for (index, result) in upcoming.prefix(NotificationConstants.maxClassReminders).enumerated() {
      let fireDate = result.startDate.addingTimeInterval(-offsetSeconds)
      // 通知時刻がすでに過ぎている授業はスキップする
      guard fireDate > now else { continue }

      let periodName = result.periodText
      let dayText = result.isToday ? "今日" : "\(result.lecture.weekday.shortName)曜"
      let body = "\(dayText) \(periodName)「\(result.lecture.subjectName)」（\(result.lecture.placeText)）が\(startsInText)始まります．"

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

    // travelTimeは徒歩時間＋教室階までの昇降時間を含む（「教室に着く」までの時間）
    let totalMinutes = max(1, Int(ceil(travelTime / 60)))
    let place = result.lecture.building?.displayName ?? result.lecture.placeText
    let floorText = result.lecture.floor.map { "（\($0)階）" } ?? ""
    let body = "そろそろ出発：\(place)\(floorText)の教室まで約\(totalMinutes)分です．「\(result.lecture.subjectName)」に間に合います．"

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
