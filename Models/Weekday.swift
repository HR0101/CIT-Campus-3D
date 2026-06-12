//
//  Weekday.swift
//  CIT-Campus-3D
//
//  曜日の定義．Calendar.component(.weekday)と同じ値体系（1=日曜〜7=土曜）に
//  揃えることで，「次の授業」判定時の現在日時との比較を単純にする．
//

import Foundation

/// 曜日（1=日曜〜7=土曜．Calendarのweekdayと同一の値体系）
enum Weekday: Int, CaseIterable, Identifiable, Codable, Hashable {
  case sunday = 1
  case monday = 2
  case tuesday = 3
  case wednesday = 4
  case thursday = 5
  case friday = 6
  case saturday = 7

  var id: Int { rawValue }

  /// 表示用の短い曜日名（例: 月）
  var shortName: String {
    switch self {
    case .sunday: return "日"
    case .monday: return "月"
    case .tuesday: return "火"
    case .wednesday: return "水"
    case .thursday: return "木"
    case .friday: return "金"
    case .saturday: return "土"
    }
  }

  /// 授業が開講される曜日（月〜土）
  static let lectureDays: [Weekday] = [
    .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
  ]
}
