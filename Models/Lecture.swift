//
//  Lecture.swift
//  CIT-Campus-3D
//
//  時間割の1コマ（授業）を表すSwiftDataモデル．
//  ファイルインポート・手動追加のどちらからも生成される．
//

import Foundation
import SwiftData

/// 時間割の1コマ（授業）
@Model
final class Lecture {
  /// 学期の生値（Semester.rawValue．クエリの単純化のためIntで保持）
  var semesterRawValue: Int = Semester.firstHalf.rawValue
  /// 曜日の生値（Calendar.weekdayと同じ1=日曜〜7=土曜．クエリの単純化のためIntで保持）
  var weekdayRawValue: Int = Weekday.monday.rawValue
  /// 時限（1〜10．ClassPeriod.numberと対応）
  var period: Int = 1
  /// 科目名
  var subjectName: String = ""
  /// 教員名
  var teacherName: String = ""
  /// キャンパスの生値（Campus.rawValue．クエリの単純化のためIntで保持）
  var campusRawValue: Int = Campus.tsudanuma.rawValue
  /// 講義棟名（例: 7号館．CampusBuildingのnameと一致させる．不明の場合は空文字）
  var buildingName: String = ""
  /// 教室番号（例: 731．不明の場合は空文字）
  var roomNumber: String = ""

  init(
    semester: Semester,
    weekday: Weekday,
    period: Int,
    subjectName: String,
    teacherName: String,
    campus: Campus,
    buildingName: String,
    roomNumber: String
  ) {
    self.semesterRawValue = semester.rawValue
    self.weekdayRawValue = weekday.rawValue
    self.period = period
    self.subjectName = subjectName
    self.teacherName = teacherName
    self.campusRawValue = campus.rawValue
    self.buildingName = buildingName
    self.roomNumber = roomNumber
  }

  /// 学期（enumとしてのアクセサ．不正値の場合は前期にフォールバック）
  var semester: Semester {
    get { Semester(rawValue: semesterRawValue) ?? .firstHalf }
    set { semesterRawValue = newValue.rawValue }
  }

  /// 曜日（enumとしてのアクセサ．不正値の場合は月曜にフォールバック）
  var weekday: Weekday {
    get { Weekday(rawValue: weekdayRawValue) ?? .monday }
    set { weekdayRawValue = newValue.rawValue }
  }

  /// キャンパス（enumとしてのアクセサ．不正値の場合は津田沼にフォールバック）
  var campus: Campus {
    get { Campus(rawValue: campusRawValue) ?? .tsudanuma }
    set { campusRawValue = newValue.rawValue }
  }

  /// 対応する講義棟（マスタに存在しない棟名の場合はnil）
  var building: CampusBuilding? {
    CampusBuilding.building(named: buildingName, campus: campus)
  }

  /// 時限の定義（開始・終了時刻つき．不正な時限番号の場合はnil）
  var classPeriod: ClassPeriod? {
    ClassPeriod.period(number: period)
  }

  /// 場所の表示文字列（例: 津田沼 7号館 731教室．不明の場合は「津田沼・教室未定」）
  var placeText: String {
    let campusName = campus.displayName
    if buildingName.isEmpty && roomNumber.isEmpty {
      return "\(campusName)・教室未定"
    }
    if roomNumber.isEmpty {
      return "\(campusName) \(buildingName)"
    }
    if buildingName.isEmpty {
      return "\(campusName) \(roomNumber)教室"
    }
    return "\(campusName) \(buildingName) \(roomNumber)教室"
  }
}
