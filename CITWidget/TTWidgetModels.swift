//
//  TTWidgetModels.swift
//  CITWidget
//
//  ウィジェットのタイムラインで扱うデータ型．
//  SwiftDataの@Model（Lecture）をそのままタイムラインに保持するのは避け，
//  取得時に値型（このファイルの構造体）へ変換して扱う．
//

import Foundation
import WidgetKit

/// ウィジェットに表示する授業1コマ（連続コマは1ブロックにまとめた代表）．
/// SwiftDataのLectureから値だけを取り出した不変の値型．
struct WidgetLectureItem: Identifiable, Hashable {
  let id: String
  /// 科目名
  let subjectName: String
  /// 講義棟名（例: 7号館．不明なら空）
  let buildingName: String
  /// 教室番号（例: 731．不明なら空）
  let roomNumber: String
  /// 曜日
  let weekday: Weekday
  /// 先頭コマの時限
  let startPeriod: Int
  /// 末尾コマの時限（単一コマならstartPeriodと同じ）
  let endPeriod: Int
  /// ブロックの開始時刻
  let startDate: Date
  /// ブロックの終了時刻
  let endDate: Date
  /// 今日の授業か（次の授業表示で「今日／曜日」を出し分けるため）
  let isToday: Bool

  /// 時限の表示文字列（例: 2限／1〜2限）
  var periodText: String {
    startPeriod == endPeriod ? "\(startPeriod)限" : "\(startPeriod)〜\(endPeriod)限"
  }

  /// 時間帯の表示文字列（例: 9:00〜11:00）
  var timeRangeText: String {
    guard
      let start = ClassPeriod.period(number: startPeriod),
      let end = ClassPeriod.period(number: endPeriod)
    else {
      return ""
    }
    return String(
      format: "%d:%02d〜%d:%02d",
      start.startHour, start.startMinute, end.endHour, end.endMinute
    )
  }

  /// 曜日ラベル（今日なら「今日」，それ以外は「月曜」など）
  var dayLabel: String {
    isToday ? "今日" : "\(weekday.shortName)曜"
  }

  /// 場所の短い表示（例: 7号館 731／731教室／教室未定）
  var shortPlace: String {
    if !buildingName.isEmpty && !roomNumber.isEmpty {
      return "\(buildingName) \(roomNumber)"
    }
    if !roomNumber.isEmpty {
      return "\(roomNumber)教室"
    }
    return buildingName.isEmpty ? "教室未定" : buildingName
  }

  /// NextLectureResult（連続コマ統合済みのブロック）から生成する
  init(block: NextLectureResult) {
    let lecture = block.lecture
    self.id = "\(lecture.weekdayRawValue)-\(block.startPeriod)-\(lecture.subjectName)"
    self.subjectName = lecture.subjectName
    self.buildingName = lecture.buildingName
    self.roomNumber = lecture.roomNumber
    self.weekday = lecture.weekday
    self.startPeriod = block.startPeriod
    self.endPeriod = block.endPeriod
    self.startDate = block.startDate
    self.endDate = block.endDate
    self.isToday = block.isToday
  }
}

/// 週間グリッドの1セル（曜日×時限の1コマ分．グリッドは各時限を別セルで描く）
struct WidgetGridCell: Hashable {
  /// 曜日
  let weekday: Weekday
  /// 時限
  let period: Int
  /// 科目名
  let subjectName: String
  /// 教室番号（空のことあり）
  let roomNumber: String
}

/// ウィジェットのタイムラインの1時点分のデータ
struct TimetableEntry: TimelineEntry {
  /// この時点（タイムラインの基準時刻）
  let date: Date
  /// 今日の授業ブロック（終了済みも含む，時限順）
  let todayItems: [WidgetLectureItem]
  /// 次に来る授業（曜日をまたいで探した1件．今日終了後は翌日以降を指す）
  let nextUp: WidgetLectureItem?
  /// 現在学期の全コマ（週間グリッド用）
  let weekCells: [WidgetGridCell]
  /// グリッドに描く最大時限（行数）
  let maxPeriod: Int
  /// 今日の曜日（グリッドの当日列をハイライトするため）
  let todayWeekday: Weekday
  /// 学期名（例: 前期）
  let semesterName: String
  /// 授業日でない場合のメッセージ（休講・期間外・休日など．通常授業日はnil）
  let statusMessage: String?
}
