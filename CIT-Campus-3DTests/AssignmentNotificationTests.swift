//
//  AssignmentNotificationTests.swift
//  CIT-Campus-3DTests
//

import Foundation
import Testing
@testable import CIT_Campus_3D

struct AssignmentNotificationTests {

  private var tokyoCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }

  @Test @MainActor func schedulesPrimaryAndFinalRemindersBeforeDeadline() {
    let now = Date(timeIntervalSince1970: 1_794_880_000)
    let due = now.addingTimeInterval(48 * 3600)
    let assignment = makeAssignment(id: "101", title: "レポート1", due: due)

    let plan = NotificationService.planAssignmentReminders(
      assignments: [assignment],
      enableReminder: true,
      primaryOffsetHours: 24,
      finalReminderMinutes: 60,
      now: now
    )

    #expect(plan.count == 2)
    #expect(plan[0].fireDate == due.addingTimeInterval(-24 * 3600))
    #expect(plan[0].leadTimeText == "1日")
    #expect(plan[1].fireDate == due.addingTimeInterval(-60 * 60))
    #expect(plan[1].leadTimeText == "1時間")
  }

  @Test @MainActor func schedulesFinalOrFallbackReminderWhenPrimaryOffsetAlreadyPassed() {
    let now = Date(timeIntervalSince1970: 1_794_880_000)
    // 10時間後締切：24時間前（デフォルト）を過ぎていても1時間前は必ず予約される
    let tenHours = makeAssignment(id: "201", title: "小テストA", due: now.addingTimeInterval(10 * 3600))
    // 35分後締切：1時間前を過ぎていても15分前の直前フォローが予約される
    let thirtyFiveMinutes = makeAssignment(id: "202", title: "小テストB", due: now.addingTimeInterval(35 * 60))

    let plan = NotificationService.planAssignmentReminders(
      assignments: [tenHours, thirtyFiveMinutes],
      enableReminder: true,
      primaryOffsetHours: 24,
      finalReminderMinutes: 60,
      now: now
    )

    #expect(plan.count == 2)
    #expect(plan[0].manabaId == "202")
    #expect(plan[0].leadTimeText == "15分")
    #expect(plan[0].fireDate == thirtyFiveMinutes.dueDate!.addingTimeInterval(-15 * 60))
    #expect(plan[1].manabaId == "201")
    #expect(plan[1].leadTimeText == "1時間")
    #expect(plan[1].fireDate == tenHours.dueDate!.addingTimeInterval(-60 * 60))
  }

  @Test @MainActor func deduplicatesSameLeadTimeAndSkipsDoneOrExpiredAssignments() {
    let now = Date(timeIntervalSince1970: 1_794_880_000)
    let active = makeAssignment(id: "301", title: "有効課題", due: now.addingTimeInterval(5 * 3600))
    let done = makeAssignment(id: "302", title: "提出済み", due: now.addingTimeInterval(5 * 3600), isDone: true)
    let overdue = makeAssignment(id: "303", title: "期限切れ", due: now.addingTimeInterval(-60))
    let noDue = makeAssignment(id: "304", title: "期限なし", due: nil)

    let plan = NotificationService.planAssignmentReminders(
      assignments: [active, done, overdue, noDue],
      enableReminder: true,
      primaryOffsetHours: 1,
      finalReminderMinutes: 60,
      now: now
    )

    // 1時間前 と 60分前 は同一時刻のため1件に集約される
    #expect(plan.count == 1)
    #expect(plan[0].manabaId == "301")

    let disabledPlan = NotificationService.planAssignmentReminders(
      assignments: [active],
      enableReminder: false,
      primaryOffsetHours: 24,
      finalReminderMinutes: 60,
      now: now
    )
    #expect(disabledPlan.isEmpty)
  }

  @Test func parsesManabaDueDateVariantsInTokyoTimezone() throws {
    let expected = try #require(
      tokyoCalendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 23, minute: 59))
    )

    #expect(ManabaAssignmentMapper.parseDate("2026-11-18 23:59") == expected)
    #expect(ManabaAssignmentMapper.parseDate("2026-11-18 23:59:00") == expected)
    #expect(ManabaAssignmentMapper.parseDate("2026/11/18 23:59") == expected)
    #expect(ManabaAssignmentMapper.parseDate("2026-11-18 23:59 まで") == expected)
    #expect(ManabaAssignmentMapper.parseDate("") == nil)
  }

  @Test @MainActor func appSettingsPersistsAssignmentFinalReminderAndFormatsLabels() {
    let suiteName = "AssignmentNotificationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(userDefaults: defaults)
    #expect(settings.enableAssignmentReminder == true)
    #expect(settings.assignmentReminderOffsetHours == 24)
    #expect(settings.assignmentFinalReminderMinutes == 60)

    settings.assignmentFinalReminderMinutes = 30
    let reloaded = AppSettings(userDefaults: defaults)
    #expect(reloaded.assignmentFinalReminderMinutes == 30)

    #expect(AppSettings.assignmentOffsetLabel(hours: 1) == "1時間前")
    #expect(AppSettings.assignmentOffsetLabel(hours: 24) == "1日前")
    #expect(AppSettings.assignmentFinalReminderLabel(minutes: 0) == "なし")
    #expect(AppSettings.assignmentFinalReminderLabel(minutes: 60) == "1時間前")
    #expect(AppSettings.assignmentFinalReminderLabel(minutes: 30) == "30分前")
  }

  private func makeAssignment(
    id: String,
    title: String,
    due: Date?,
    isDone: Bool = false
  ) -> Assignment {
    Assignment(
      type: "レポート",
      title: title,
      courseName: "2026後期_情報工学実験",
      dueDate: due,
      startDate: nil,
      manabaURL: "https://cit.manaba.jp/ct/course_1_report_\(id)",
      courseURL: "https://cit.manaba.jp/ct/course_1",
      manabaId: id,
      isDone: isDone
    )
  }
}
