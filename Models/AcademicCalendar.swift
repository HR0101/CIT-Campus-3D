//
//  AcademicCalendar.swift
//  CIT-Campus-3D
//
//  学年暦（授業期間・休講日）．「次の授業」判定で，長期休業・試験期間・休講日を
//  正しく除外するために使う．日付は yyyymmdd の整数キーで保持し，比較を単純化する．
//

import Foundation

/// 学年暦（授業期間・休講日・主な行事）
struct AcademicCalendar {

  /// 授業期間（前期・後期）
  struct Term {
    /// 学期
    let semester: Semester
    /// 授業開始日（yyyymmdd）
    let startKey: Int
    /// 授業終了日（yyyymmdd）
    let endKey: Int
  }

  /// 休講日（授業期間内だが授業がない日）
  struct ClosureDay: Identifiable {
    /// 日付（yyyymmdd）
    let key: Int
    /// 理由（例: 津田沼祭）
    let reason: String
    var id: Int { key }
  }

  /// 主な行事（表示用）
  struct NotableDay: Identifiable {
    /// 日付（yyyymmdd）
    let key: Int
    /// 行事名
    let label: String
    var id: Int { key }
  }

  /// 学年暦が示す，ある日付の状態
  enum ScheduleStatus: Equatable {
    /// 授業実施日（学期つき）
    case classDay(Semester)
    /// 授業期間内の休講日（理由つき）
    case closureDay(reason: String)
    /// 授業期間外（次に始まる学期と開始日つき）
    case breakUntil(nextSemester: Semester, startKey: Int)
    /// 本年度の全授業が終了
    case afterAllTerms
    /// この学年暦の対象外の年
    case unknownYear
  }

  /// 対象年度（西暦の開始年．2026年度＝2026）
  let academicYear: Int
  /// 学年暦が扱う全期間の開始日（yyyymmdd）．この範囲外はunknownYear扱い
  let spanStartKey: Int
  /// 学年暦が扱う全期間の終了日（yyyymmdd）
  let spanEndKey: Int
  /// 授業期間（前期・後期）
  let terms: [Term]
  /// 休講日（授業期間内だが授業がない日）
  let closureDays: [ClosureDay]
  /// 主な行事（表示用）
  let notableDays: [NotableDay]

  /// 休講日の高速参照用（key→理由）
  private let closureLookup: [Int: String]

  init(
    academicYear: Int,
    spanStartKey: Int,
    spanEndKey: Int,
    terms: [Term],
    closureDays: [ClosureDay],
    notableDays: [NotableDay]
  ) {
    self.academicYear = academicYear
    self.spanStartKey = spanStartKey
    self.spanEndKey = spanEndKey
    self.terms = terms
    self.closureDays = closureDays
    self.notableDays = notableDays
    self.closureLookup = Dictionary(
      closureDays.map { ($0.key, $0.reason) },
      uniquingKeysWith: { first, _ in first }
    )
  }

  // MARK: - 日付キー

  /// 年月日をキー（yyyymmdd）に変換する
  static func dayKey(year: Int, month: Int, day: Int) -> Int {
    year * 10_000 + month * 100 + day
  }

  /// Dateをキー（yyyymmdd）に変換する
  func dayKey(for date: Date, calendar: Calendar) -> Int {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return Self.dayKey(
      year: components.year ?? 0,
      month: components.month ?? 0,
      day: components.day ?? 0
    )
  }

  /// キー（yyyymmdd）からその日の0時のDateを得る
  func date(forKey key: Int, calendar: Calendar) -> Date? {
    var components = DateComponents()
    components.year = key / 10_000
    components.month = (key / 100) % 100
    components.day = key % 100
    return calendar.date(from: components)
  }

  // MARK: - 判定

  /// この学年暦が対象とする期間に含まれる日付か
  func covers(_ date: Date, calendar: Calendar) -> Bool {
    let key = dayKey(for: date, calendar: calendar)
    return key >= spanStartKey && key <= spanEndKey
  }

  /// その日が属する授業期間（無ければnil）
  func term(on date: Date, calendar: Calendar) -> Term? {
    let key = dayKey(for: date, calendar: calendar)
    return terms.first { key >= $0.startKey && key <= $0.endKey }
  }

  /// その日が授業実施日か（授業期間内 かつ 休講日でない）
  /// 注: 日曜などの曜日判定は時間割側（Weekday）で行うため，ここでは見ない
  func isClassDay(_ date: Date, calendar: Calendar) -> Bool {
    guard term(on: date, calendar: calendar) != nil else { return false }
    return closureLookup[dayKey(for: date, calendar: calendar)] == nil
  }

  /// その日の学年暦上の状態を返す
  func scheduleStatus(on date: Date, calendar: Calendar) -> ScheduleStatus {
    guard covers(date, calendar: calendar) else { return .unknownYear }
    let key = dayKey(for: date, calendar: calendar)
    if let term = terms.first(where: { key >= $0.startKey && key <= $0.endKey }) {
      if let reason = closureLookup[key] {
        return .closureDay(reason: reason)
      }
      return .classDay(term.semester)
    }
    // 授業期間外: これから始まる学期を探す
    if let next = terms.filter({ $0.startKey > key }).min(by: { $0.startKey < $1.startKey }) {
      return .breakUntil(nextSemester: next.semester, startKey: next.startKey)
    }
    return .afterAllTerms
  }

  // MARK: - 表示用フォーマット

  /// キー（yyyymmdd）を「M月D日」に整形する
  static func monthDayText(fromKey key: Int) -> String {
    let month = (key / 100) % 100
    let day = key % 100
    return "\(month)月\(day)日"
  }

  /// キー（yyyymmdd）を「M月D日(曜)」に整形する
  func monthDayWeekdayText(fromKey key: Int, calendar: Calendar = .current) -> String {
    let base = Self.monthDayText(fromKey: key)
    guard
      let date = date(forKey: key, calendar: calendar),
      let weekday = Weekday(rawValue: calendar.component(.weekday, from: date))
    else {
      return base
    }
    return "\(base)（\(weekday.shortName)）"
  }
}

// MARK: - 2026年度の学年暦

extension AcademicCalendar {

  /// 現在使用する学年暦（現時点では2026年度のみ）
  static let current = academicYear2026

  /// 2026年度の学年暦（千葉工業大学 津田沼／新習志野キャンパス）
  /// 出典: 2026年度 学年暦（前期・後期）
  static let academicYear2026 = AcademicCalendar(
    academicYear: 2026,
    spanStartKey: dayKey(year: 2026, month: 4, day: 1),
    spanEndKey: dayKey(year: 2027, month: 3, day: 31),
    terms: [
      // 前期: 4/11(土) 〜 7/17(金)
      Term(
        semester: .firstHalf,
        startKey: dayKey(year: 2026, month: 4, day: 11),
        endKey: dayKey(year: 2026, month: 7, day: 17)
      ),
      // 後期: 9/18(金) 〜 12/21(月)
      Term(
        semester: .secondHalf,
        startKey: dayKey(year: 2026, month: 9, day: 18),
        endKey: dayKey(year: 2026, month: 12, day: 21)
      ),
    ],
    closureDays: [
      // 前期の休講日（祝日でも授業実施の日は含めない）
      ClosureDay(key: dayKey(year: 2026, month: 4, day: 30), reason: "自学自習の日"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 1), reason: "開学記念日の振替"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 2), reason: "自学自習の日"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 4), reason: "みどりの日"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 5), reason: "こどもの日"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 6), reason: "振替休日"),
      ClosureDay(key: dayKey(year: 2026, month: 5, day: 23), reason: "成田山詣行脚"),
      // 後期の休講日
      ClosureDay(key: dayKey(year: 2026, month: 11, day: 20), reason: "津田沼祭準備"),
      ClosureDay(key: dayKey(year: 2026, month: 11, day: 21), reason: "津田沼祭"),
      ClosureDay(key: dayKey(year: 2026, month: 11, day: 23), reason: "津田沼祭後片付け"),
    ],
    notableDays: [
      NotableDay(key: dayKey(year: 2026, month: 4, day: 5), label: "入学式"),
      NotableDay(key: dayKey(year: 2026, month: 4, day: 11), label: "前期授業開始"),
      NotableDay(key: dayKey(year: 2026, month: 4, day: 29), label: "祝日授業日（昭和の日）"),
      NotableDay(key: dayKey(year: 2026, month: 5, day: 15), label: "開学記念日（授業日）"),
      NotableDay(key: dayKey(year: 2026, month: 7, day: 17), label: "前期授業終了"),
      NotableDay(key: dayKey(year: 2026, month: 7, day: 18), label: "共通試験日（前期）"),
      NotableDay(key: dayKey(year: 2026, month: 9, day: 18), label: "後期授業開始"),
      NotableDay(key: dayKey(year: 2026, month: 9, day: 21), label: "祝日授業日（敬老の日）"),
      NotableDay(key: dayKey(year: 2026, month: 10, day: 12), label: "祝日授業日（スポーツの日）"),
      NotableDay(key: dayKey(year: 2026, month: 11, day: 3), label: "祝日授業日（文化の日）"),
      NotableDay(key: dayKey(year: 2026, month: 11, day: 21), label: "津田沼祭"),
      NotableDay(key: dayKey(year: 2026, month: 12, day: 21), label: "後期授業終了"),
      NotableDay(key: dayKey(year: 2026, month: 12, day: 22), label: "共通試験日（後期）"),
      NotableDay(key: dayKey(year: 2027, month: 3, day: 22), label: "学位記授与式"),
    ]
  )
}
