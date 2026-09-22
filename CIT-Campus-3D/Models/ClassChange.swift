//
//  ClassChange.swift
//  CIT-Campus-3D
//
//  ポータル（UNIVERSAL PASSPORT）の「時間割変更」＝休講・補講・教室変更を表すSwiftDataモデル．
//  掲示の本文（科目名／教員名／日時／教室）を解析して生成する．
//  CloudKit同期に対応するため，全プロパティに既定値を持たせ，ユニーク制約・リレーションは持たない
//  （重複排除は取り込み時に changeKey で行う）．
//

import Foundation
import SwiftData

/// 時間割変更の種別
enum ClassChangeType: String, CaseIterable {
  /// 休講
  case canceled
  /// 補講
  case supplementary
  /// 教室変更
  case roomChange
  /// その他（判別不能）
  case other

  /// 掲示の件名・本文から種別を判定する
  static func detect(from text: String) -> ClassChangeType {
    if text.contains("休講") { return .canceled }
    if text.contains("補講") { return .supplementary }
    if text.contains("教室変更") { return .roomChange }
    return .other
  }

  /// 表示名
  var displayName: String {
    switch self {
    case .canceled: return "休講"
    case .supplementary: return "補講"
    case .roomChange: return "教室変更"
    case .other: return "変更"
    }
  }

  /// 表示色のためのSF Symbol（休講＝赤系・補講＝青系のイメージ）
  var iconName: String {
    switch self {
    case .canceled: return "xmark.circle.fill"
    case .supplementary: return "plus.circle.fill"
    case .roomChange: return "arrow.triangle.swap"
    case .other: return "info.circle.fill"
    }
  }
}

/// 時間割変更（休講・補講・教室変更）の1件
@Model
final class ClassChange {
  /// 種別の生値（ClassChangeType.rawValue）
  var typeRawValue: String = ClassChangeType.other.rawValue
  /// 科目名
  var subjectName: String = ""
  /// 教員名
  var teacherName: String = ""
  /// 実施日（休講日・補講日．不明な場合はnil）
  var date: Date? = nil
  /// 開始時限（不明な場合は0）
  var startPeriod: Int = 0
  /// 終了時限（単一コマなら開始と同じ．不明な場合は0）
  var endPeriod: Int = 0
  /// 教室（例: 731．不明な場合は空文字）
  var room: String = ""
  /// 掲示の件名（元タイトル）
  var noticeTitle: String = ""
  /// 掲載日（不明な場合はnil）
  var postedDate: Date? = nil
  /// 重複排除キー（種別＋科目＋日付＋時限など本文から組み立てる）
  var changeKey: String = ""
  /// 取り込んだ日時
  var importedAt: Date = Date.distantPast

  init(
    type: ClassChangeType,
    subjectName: String,
    teacherName: String,
    date: Date?,
    startPeriod: Int,
    endPeriod: Int,
    room: String,
    noticeTitle: String,
    postedDate: Date?,
    changeKey: String,
    importedAt: Date = Date()
  ) {
    self.typeRawValue = type.rawValue
    self.subjectName = subjectName
    self.teacherName = teacherName
    self.date = date
    self.startPeriod = startPeriod
    self.endPeriod = endPeriod
    self.room = room
    self.noticeTitle = noticeTitle
    self.postedDate = postedDate
    self.changeKey = changeKey
    self.importedAt = importedAt
  }

  /// 種別（enumとしてのアクセサ）
  var type: ClassChangeType {
    get { ClassChangeType(rawValue: typeRawValue) ?? .other }
    set { typeRawValue = newValue.rawValue }
  }

  /// 対象の時限（startPeriod〜endPeriod）の配列
  var periods: [Int] {
    guard startPeriod > 0 else { return [] }
    let upper = max(startPeriod, endPeriod)
    return Array(startPeriod...upper)
  }

  /// 時限の表示文字列（例: 4・5限／4限）
  var periodText: String {
    let list = periods
    guard !list.isEmpty else { return "" }
    if list.count == 1 { return "\(list[0])限" }
    return list.map(String.init).joined(separator: "・") + "限"
  }
}
