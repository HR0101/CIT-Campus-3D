//
//  ClassPeriod.swift
//  CIT-Campus-3D
//
//  時限（1限・2限…）の開始・終了時刻の定義．
//  「次の授業」判定はこの定義と現在時刻の比較で行う．
//

import Foundation

/// 時限の定義（開始・終了時刻つき）
struct ClassPeriod: Identifiable, Hashable {
  /// 時限番号（1〜10）
  let number: Int
  /// 開始時（24時間制）
  let startHour: Int
  /// 開始分
  let startMinute: Int
  /// 終了時（24時間制）
  let endHour: Int
  /// 終了分
  let endMinute: Int

  var id: Int { number }

  /// 表示名（例: 1限）
  var displayName: String { "\(number)限" }

  /// 時間帯の表示文字列（例: 9:00〜10:00）
  var timeRangeText: String {
    String(format: "%d:%02d〜%d:%02d", startHour, startMinute, endHour, endMinute)
  }

  /// 指定した日付におけるこの時限の開始時刻
  func startDate(on date: Date, calendar: Calendar = .current) -> Date? {
    calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: date)
  }

  /// 指定した日付におけるこの時限の終了時刻
  func endDate(on date: Date, calendar: Calendar = .current) -> Date? {
    calendar.date(bySettingHour: endHour, minute: endMinute, second: 0, of: date)
  }
}

extension ClassPeriod {

  // 公式の時間割表（PDF/Excel）の脚注に記載されている津田沼キャンパスの時限:
  // 「1限 09:00〜10:00／2限 10:00〜11:00／…／10限 18:00〜19:00」（各60分・10限制）

  /// 時限体系の定数
  private enum ScheduleConstants {
    /// 1日の時限数
    static let periodCount = 10
    /// 1限の開始時刻（時）
    static let firstPeriodStartHour = 9
    /// 1時限の長さ（時間）
    static let periodDurationHours = 1
  }

  /// 全時限の定義（1〜10限，各60分）
  static let allPeriods: [ClassPeriod] = (1...ScheduleConstants.periodCount).map { number in
    let startHour = ScheduleConstants.firstPeriodStartHour
      + (number - 1) * ScheduleConstants.periodDurationHours
    return ClassPeriod(
      number: number,
      startHour: startHour,
      startMinute: 0,
      endHour: startHour + ScheduleConstants.periodDurationHours,
      endMinute: 0
    )
  }

  /// 時限番号から定義を取得する（存在しない番号はnil）
  static func period(number: Int) -> ClassPeriod? {
    allPeriods.first { $0.number == number }
  }
}
