//
//  Semester.swift
//  CIT-Campus-3D
//
//  学期（前期・後期）の定義．時間割は学期ごとに別の内容を持つ．
//

import Foundation

/// 学期（前期・後期）
enum Semester: Int, CaseIterable, Identifiable, Codable, Hashable {
  /// 前期（期間は学年暦で判定）
  case firstHalf = 1
  /// 後期（期間は学年暦で判定）
  case secondHalf = 2

  var id: Int { rawValue }

  /// 表示名（例: 前期）
  var displayName: String {
    switch self {
    case .firstHalf: return "前期"
    case .secondHalf: return "後期"
    }
  }

  /// 学期判定の定数
  private enum SemesterConstants {
    /// 前期とみなす月（4〜9月）
    static let firstHalfMonths = 4...9
  }

  /// 学年暦を優先し，未登録の年度のみ月単位で判定する．
  static func current(
    on date: Date, calendar: Calendar = .current,
    academicCalendar: AcademicCalendar = .current
  ) -> Semester {
    if let semester = academicCalendar.displaySemester(on: date, calendar: calendar) {
      return semester
    }
    let month = calendar.component(.month, from: date)
    return SemesterConstants.firstHalfMonths.contains(month) ? .firstHalf : .secondHalf
  }
}
