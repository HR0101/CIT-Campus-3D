//
//  TTTimetableLoader.swift
//  CITWidget
//
//  App Group 共有ストアから時間割を読み込み，ウィジェットのタイムライン（複数時点のエントリ）を組み立てる．
//  @Modelオブジェクトはこの中で値型（WidgetLectureItem / WidgetGridCell）へ変換し，外へ持ち出さない．
//

import Foundation
import SwiftData
import WidgetKit

/// 時間割の読み込みとタイムライン生成を担う
enum TTTimetableLoader {

  /// グリッドに最低限確保する時限数（授業が少なくても枠が小さくなりすぎないように）
  private static let minimumGridPeriods = 5

  // MARK: - タイムライン生成

  /// 現在時刻を起点に，複数時点のエントリ（毎正時＋翌日0:01）を生成する．
  /// 授業は毎正時区切りのため，毎正時にエントリを置くと「現在の授業」のハイライトが正確に更新される．
  /// - Parameter now: 起点の時刻
  /// - Returns: 時刻順のエントリ配列
  static func timelineEntries(now: Date) -> [TimetableEntry] {
    let calendar = Calendar.current
    let lectures = fetchLectures()
    let refreshDates = refreshDates(now: now, calendar: calendar)
    return refreshDates.map { entry(at: $0, lectures: lectures, calendar: calendar) }
  }

  /// 単一時点のエントリを生成する（スナップショット用）
  /// - Parameter date: 対象時刻
  /// - Returns: その時点のエントリ
  static func singleEntry(at date: Date) -> TimetableEntry {
    entry(at: date, lectures: fetchLectures(), calendar: Calendar.current)
  }

  // MARK: - Private

  /// 共有ストアから全授業を取得する（取得できなければ空配列）
  private static func fetchLectures() -> [Lecture] {
    guard let container = try? SharedModelContainer.make() else { return [] }
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<Lecture>()
    return (try? context.fetch(descriptor)) ?? []
  }

  /// エントリを置く時刻の一覧（now＋当日の残り毎正時＋翌日0:01）を返す
  private static func refreshDates(now: Date, calendar: Calendar) -> [Date] {
    var dates: [Date] = [now]
    let startOfNextDay = calendar.startOfDay(for: now).addingTimeInterval(24 * 60 * 60)

    // 次の正時から当日の終わりまで，1時間刻みでエントリを置く
    if var hour = calendar.nextDate(
      after: now,
      matching: DateComponents(minute: 0, second: 0),
      matchingPolicy: .nextTime
    ) {
      while hour < startOfNextDay {
        dates.append(hour)
        guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
        hour = next
      }
    }
    // 翌日0:01（日付が変わって「今日」を更新する）
    dates.append(startOfNextDay.addingTimeInterval(60))
    return dates
  }

  /// 指定時刻のエントリを，取得済みの授業から組み立てる
  private static func entry(at date: Date, lectures: [Lecture], calendar: Calendar) -> TimetableEntry {
    let resolver = NextLectureResolver()

    // 今日の授業ブロック（終了済みも含む）
    let todayBlocks = resolver.blocks(on: date, from: lectures, now: date, calendar: calendar)
    let todayItems = todayBlocks.map { WidgetLectureItem(block: $0) }

    // 次に来る授業（曜日をまたいで1件）
    let nextUp = resolver.resolveNextLecture(from: lectures, now: date, calendar: calendar)
      .map { WidgetLectureItem(block: $0) }

    // 週間グリッド用: 現在学期の全コマを曜日×時限のセルに変換
    let semester = resolver.currentSemester(on: date, calendar: calendar)
    let semesterLectures = lectures.filter { $0.semesterRawValue == semester.rawValue }
    let weekCells = semesterLectures.map {
      WidgetGridCell(
        weekday: $0.weekday,
        period: $0.period,
        subjectName: $0.subjectName,
        roomNumber: $0.roomNumber
      )
    }
    let maxPeriod = max(minimumGridPeriods, weekCells.map(\.period).max() ?? minimumGridPeriods)

    let todayWeekday = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday

    return TimetableEntry(
      date: date,
      todayItems: todayItems,
      nextUp: nextUp,
      weekCells: weekCells,
      maxPeriod: maxPeriod,
      todayWeekday: todayWeekday,
      semesterName: semester.displayName,
      statusMessage: statusMessage(for: date, hasTodayItems: !todayItems.isEmpty, calendar: calendar)
    )
  }

  /// 授業日でない・授業が無い場合のメッセージ（通常授業日で授業があればnil）
  private static func statusMessage(
    for date: Date,
    hasTodayItems: Bool,
    calendar: Calendar
  ) -> String? {
    // 土日など授業のない曜日
    let weekdayValue = calendar.component(.weekday, from: date)
    if let weekday = Weekday(rawValue: weekdayValue), !Weekday.lectureDays.contains(weekday) {
      return "今日は授業はありません"
    }
    // 学年暦上の休講・期間外
    switch AcademicCalendar.current.scheduleStatus(on: date, calendar: calendar) {
    case .closureDay(let reason):
      return "本日は休講（\(reason)）"
    case .breakUntil:
      return "授業期間外です"
    case .afterAllTerms:
      return "今年度の授業は終了しました"
    case .classDay, .unknownYear:
      // 授業日だが登録された授業が無い場合
      return hasTodayItems ? nil : "今日の授業はありません"
    }
  }
}

// MARK: - プレースホルダ・プレビュー用のサンプル

extension TimetableEntry {

  /// ウィジェットギャラリー／読み込み中に表示するサンプルデータ
  static var sample: TimetableEntry {
    // 固定の基準時刻は使えない（Date()のみ）ため，サンプルは現在時刻基準で組み立てる
    let now = Date()
    let calendar = Calendar.current
    let today = Weekday(rawValue: calendar.component(.weekday, from: now)) ?? .monday

    func makeItem(subject: String, building: String, room: String, start: Int, end: Int) -> WidgetLectureItem {
      let startDate = calendar.date(bySettingHour: 8 + start, minute: 0, second: 0, of: now) ?? now
      let endDate = calendar.date(bySettingHour: 8 + end, minute: 0, second: 0, of: now) ?? now
      return WidgetLectureItem(
        id: "\(today.rawValue)-\(start)-\(subject)",
        subjectName: subject,
        buildingName: building,
        roomNumber: room,
        weekday: today,
        startPeriod: start,
        endPeriod: end,
        startDate: startDate,
        endDate: endDate,
        isToday: true
      )
    }

    let items = [
      makeItem(subject: "プログラミング", building: "7号館", room: "731", start: 1, end: 2),
      makeItem(subject: "線形代数", building: "2号館", room: "201", start: 3, end: 4),
    ]
    let cells = [
      WidgetGridCell(weekday: .monday, period: 1, subjectName: "英語", roomNumber: "601"),
      WidgetGridCell(weekday: .tuesday, period: 2, subjectName: "物理", roomNumber: "311"),
      WidgetGridCell(weekday: today, period: 1, subjectName: "プログラミング", roomNumber: "731"),
    ]
    return TimetableEntry(
      date: now,
      todayItems: items,
      nextUp: items.first,
      weekCells: cells,
      maxPeriod: 5,
      todayWeekday: today,
      semesterName: "前期",
      statusMessage: nil
    )
  }

  /// 「授業なし」を表す空のエントリ
  static func empty(at date: Date) -> TimetableEntry {
    let calendar = Calendar.current
    let today = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    return TimetableEntry(
      date: date,
      todayItems: [],
      nextUp: nil,
      weekCells: [],
      maxPeriod: 5,
      todayWeekday: today,
      semesterName: "前期",
      statusMessage: "時間割を読み込めません"
    )
  }
}

private extension WidgetLectureItem {

  /// サンプル生成用の明示イニシャライザ
  init(
    id: String,
    subjectName: String,
    buildingName: String,
    roomNumber: String,
    weekday: Weekday,
    startPeriod: Int,
    endPeriod: Int,
    startDate: Date,
    endDate: Date,
    isToday: Bool
  ) {
    self.id = id
    self.subjectName = subjectName
    self.buildingName = buildingName
    self.roomNumber = roomNumber
    self.weekday = weekday
    self.startPeriod = startPeriod
    self.endPeriod = endPeriod
    self.startDate = startDate
    self.endDate = endDate
    self.isToday = isToday
  }
}
