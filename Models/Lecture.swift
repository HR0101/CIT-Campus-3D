//
//  Lecture.swift
//  CIT-Campus-3D
//
//  時間割の1コマ（授業）を表すSwiftDataモデル．
//  ファイルインポート・手動追加のどちらからも生成される．
//

import Foundation
import SwiftData

/// 教室へのアクセス時間の推定に関する定数
private enum ClassroomAccessConstants {
  /// 階段で1フロア上るのにかかる推定時間（秒）．エレベーターは使わず階段で上る前提とする
  static let secondsPerFloor: TimeInterval = 25
}

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

  /// 教室の階数（教室番号の棟番号の次の桁から推定．例: 731→3階，1024（10号館）→2階．判定できなければnil）
  /// 千葉工大の教室番号は「棟番号＋階＋部屋番号」の規則．棟番号は通常1桁だが，
  /// 新習志野の10〜12号館は2桁のため，building(forRoomNumber:)と同じ規則で棟番号桁を読み飛ばす
  var floor: Int? {
    // 先頭から連続する数字（棟番号＋階＋部屋番号）を取り出す
    let lead = String(roomNumber.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber }))
    guard !lead.isEmpty else { return nil }
    // 棟番号が2桁（実在する10〜12号館）ならその分，なければ1桁を棟番号として読み飛ばす
    let prefixLength = (lead.count >= 2
      && CampusBuilding.building(named: "\(lead.prefix(2))号館", campus: campus) != nil) ? 2 : 1
    let rest = lead.dropFirst(prefixLength)
    guard let floorDigit = rest.first?.wholeNumberValue, floorDigit >= 1 else { return nil }
    return floorDigit
  }

  /// 建物入口（1階）から教室階まで階段で上るのにかかる推定時間（秒）．
  /// 1階分ごとに一定時間を加算するため，上の階ほど時間が増える．
  /// 1階・地下・不明の場合は0とする．
  var floorClimbSeconds: TimeInterval {
    guard let floor, floor > 1 else { return 0 }
    return TimeInterval(floor - 1) * ClassroomAccessConstants.secondsPerFloor
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
