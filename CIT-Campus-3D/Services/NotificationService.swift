//
//  NotificationService.swift
//  CIT-Campus-3D
//
//  ローカル通知（授業前リマインダー・出発リマインダー・課題締切リマインダー）の許可管理と予約を担う．
//  予約は最新の授業・課題一覧から毎回まとめて作り直す方式とする．
//

import Foundation
import Observation
import UserNotifications

/// 予約予定の課題リマインダー1件（単体テスト可能な純粋計画モデル）
struct PlannedAssignmentReminder: Equatable {
  let assignmentKey: String
  let title: String
  let courseName: String
  let manabaURL: String
  let manabaId: String
  let dueDate: Date
  let fireDate: Date
  let leadTimeText: String
}

/// ローカル通知の管理を担うサービス
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

  /// 通知に関する定数
  private enum NotificationConstants {
    /// 授業前リマインダーをまとめて予約する最大件数（iOSの保留上限64件に対し余裕を持たせる）
    static let maxClassReminders = 16
    /// 授業前リマインダーの通知ID接頭辞
    static let classReminderPrefix = "class-reminder-"
    /// 出発リマインダーの通知ID
    static let departureReminderID = "departure-reminder"
    /// 課題リマインダーをまとめて予約する最大件数（メイン＋直前で最大32件）
    static let maxAssignmentReminders = 32
    /// 課題リマインダーの通知ID接頭辞
    static let assignmentReminderPrefix = "assignment-reminder-"
    /// テスト通知のID
    static let assignmentTestReminderID = "assignment-reminder-test"
  }

  /// 現在の通知許可状態
  private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

  /// 現在予約中の課題リマインダー件数
  private(set) var scheduledAssignmentReminderCount = 0

  /// 課題キーごとの次回通知予定時刻
  private(set) var nextAssignmentReminderByKey: [String: Date] = [:]

  /// 通知タップ時に開くmanaba課題URL（処理後に呼び出し側でnilに戻す）
  var pendingAssignmentURL: URL?

  private let center = UNUserNotificationCenter.current()

  override init() {
    super.init()
    center.delegate = self
  }

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
    scheduledAssignmentReminderCount = 0
    nextAssignmentReminderByKey = [:]
  }

  /// 授業前・出発リマインダーのみ取り消す（課題リマインダーは保持する）
  func cancelClassReminders() {
    center.removePendingNotificationRequests(withIdentifiers: classReminderIdentifiers())
  }

  /// 課題オブジェクトから安定した識別キーを生成する
  static func assignmentKey(for assignment: Assignment) -> String {
    if !assignment.manabaURL.isEmpty { return assignment.manabaURL }
    if !assignment.manabaId.isEmpty { return assignment.manabaId }
    return "\(assignment.courseName)|\(assignment.title)"
  }

  /// 指定課題に対して現在予約済みの最も早い通知時刻を返す
  func nextReminderDate(for assignment: Assignment) -> Date? {
    nextAssignmentReminderByKey[Self.assignmentKey(for: assignment)]
  }

  /// 直近の授業群に対して通知を予約し直す
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
  func rescheduleAssignmentReminders(assignments: [Assignment], settings: AppSettings) {
    // 課題リマインダーの予約だけを消す
    center.removePendingNotificationRequests(withIdentifiers: assignmentReminderIdentifiers())

    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      scheduledAssignmentReminderCount = 0
      nextAssignmentReminderByKey = [:]
      return
    }
    guard settings.enableAssignmentReminder else {
      scheduledAssignmentReminderCount = 0
      nextAssignmentReminderByKey = [:]
      return
    }

    let plan = Self.planAssignmentReminders(
      assignments: assignments,
      enableReminder: settings.enableAssignmentReminder,
      primaryOffsetHours: settings.assignmentReminderOffsetHours,
      finalReminderMinutes: settings.assignmentFinalReminderMinutes,
      now: Date(),
      maxCount: NotificationConstants.maxAssignmentReminders
    )

    var nextDates: [String: Date] = [:]
    for (index, item) in plan.enumerated() {
      let dueText = assignmentDueText(item.dueDate)
      let courseText = item.courseName.isEmpty ? "" : "（\(item.courseName)）"
      let body = "課題「\(item.title)」\(courseText)の締切（\(dueText)）まであと\(item.leadTimeText)です．"

      var userInfo: [AnyHashable: Any] = ["kind": "assignment"]
      if !item.manabaURL.isEmpty {
        userInfo["manabaURL"] = item.manabaURL
      }
      if !item.manabaId.isEmpty {
        userInfo["manabaId"] = item.manabaId
      }

      scheduleNotification(
        identifier: "\(NotificationConstants.assignmentReminderPrefix)\(index)",
        title: "課題の締切まであと\(item.leadTimeText)",
        body: body,
        fireDate: item.fireDate,
        userInfo: userInfo
      )

      if let existing = nextDates[item.assignmentKey] {
        nextDates[item.assignmentKey] = min(existing, item.fireDate)
      } else {
        nextDates[item.assignmentKey] = item.fireDate
      }
    }

    scheduledAssignmentReminderCount = plan.count
    nextAssignmentReminderByKey = nextDates
  }

  /// 5秒後に届く課題テスト通知を送信し，実機で通知が受け取れるか確認できるようにする
  @discardableResult
  func sendTestAssignmentNotification() async -> Bool {
    if authorizationStatus == .notDetermined {
      _ = await requestAuthorization()
    } else {
      await refreshAuthorizationStatus()
    }
    guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
      return false
    }

    center.removePendingNotificationRequests(withIdentifiers: [NotificationConstants.assignmentTestReminderID])

    let content = UNMutableNotificationContent()
    content.title = "課題リマインダーのテスト通知"
    content.body = "manabaから取り込んだ課題の締切前にこの形式で通知が届きます．"
    content.sound = .default
    content.userInfo = ["kind": "assignment-test"]

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
    let request = UNNotificationRequest(
      identifier: NotificationConstants.assignmentTestReminderID,
      content: content,
      trigger: trigger
    )
    try? await center.add(request)
    return true
  }

  /// 課題一覧と設定から予約すべき通知一覧を純粋に算出する（テスト可能）
  static func planAssignmentReminders(
    assignments: [Assignment],
    enableReminder: Bool,
    primaryOffsetHours: Int,
    finalReminderMinutes: Int,
    now: Date = Date(),
    maxCount: Int = NotificationConstants.maxAssignmentReminders
  ) -> [PlannedAssignmentReminder] {
    guard enableReminder, maxCount > 0 else { return [] }

    let primarySeconds = TimeInterval(max(0, primaryOffsetHours)) * 3600
    let finalSeconds = TimeInterval(max(0, finalReminderMinutes)) * 60

    var planned: [PlannedAssignmentReminder] = []

    for assignment in assignments {
      guard !assignment.isDone, let due = assignment.dueDate, due > now else { continue }
      let remaining = due.timeIntervalSince(now)
      let key = assignmentKey(for: assignment)

      // メイン通知・直前通知のオフセット候補（重複は60秒未満なら1つにまとめる）
      var candidateOffsets: [TimeInterval] = []
      if primarySeconds > 0 {
        candidateOffsets.append(primarySeconds)
      }
      if finalSeconds > 0, !candidateOffsets.contains(where: { abs($0 - finalSeconds) < 60 }) {
        candidateOffsets.append(finalSeconds)
      }

      var futureOffsets = candidateOffsets.filter { due.addingTimeInterval(-$0) > now }

      // 設定した通知時刻をすでに過ぎた状態で新規同期された場合でも，締切前なら直前フォローを予約する
      if futureOffsets.isEmpty {
        if remaining > 15 * 60 {
          futureOffsets.append(15 * 60)
        } else if remaining > 5 * 60 {
          futureOffsets.append(5 * 60)
        }
      }

      for offset in futureOffsets {
        let fireDate = due.addingTimeInterval(-offset)
        guard fireDate > now else { continue }
        planned.append(
          PlannedAssignmentReminder(
            assignmentKey: key,
            title: assignment.title,
            courseName: assignment.courseName,
            manabaURL: assignment.manabaURL,
            manabaId: assignment.manabaId,
            dueDate: due,
            fireDate: fireDate,
            leadTimeText: formatLeadTime(seconds: offset)
          )
        )
      }
    }

    return planned
      .sorted {
        if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
        if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
        return $0.title < $1.title
      }
      .prefix(maxCount)
      .map { $0 }
  }

  private static func formatLeadTime(seconds: TimeInterval) -> String {
    let minutes = max(1, Int(round(seconds / 60)))
    if minutes % (24 * 60) == 0 {
      return "\(minutes / (24 * 60))日"
    }
    if minutes % 60 == 0 {
      return "\(minutes / 60)時間"
    }
    return "\(minutes)分"
  }

  // MARK: - UNUserNotificationCenterDelegate

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let urlString = response.notification.request.content.userInfo["manabaURL"] as? String
    guard let urlString, let url = URL(string: urlString) else { return }
    await MainActor.run {
      self.pendingAssignmentURL = url
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
    let startsInText = offsetMinutes > 0 ? "約\(offsetMinutes)分後" : "まもなく"
    for (index, result) in upcoming.prefix(NotificationConstants.maxClassReminders).enumerated() {
      let fireDate = result.startDate.addingTimeInterval(-offsetSeconds)
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
    guard fireDate > now else { return }

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
    fireDate: Date,
    userInfo: [AnyHashable: Any] = [:]
  ) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    if !userInfo.isEmpty {
      content.userInfo = userInfo
    }

    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: fireDate
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    center.add(request)
  }
}
