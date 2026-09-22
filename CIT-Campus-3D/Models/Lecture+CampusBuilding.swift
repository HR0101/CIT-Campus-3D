//
//  Lecture+CampusBuilding.swift
//  CIT-Campus-3D
//
//  Lecture のうち，講義棟マスタ（CampusBuilding）や階数・昇降時間に依存する部分を
//  アプリ専用の拡張として切り出したもの．
//  ウィジェットターゲットには CampusBuilding（GeoJSON依存）を持ち込まないよう，
//  このファイルはアプリターゲットのみに含める（ウィジェットのメンバーシップには加えない）．
//

import Foundation

/// 教室へのアクセス時間の推定に関する定数
private enum ClassroomAccessConstants {
  /// 階段で1フロア上るのにかかる推定時間（秒）．エレベーターは使わず階段で上る前提とする
  static let secondsPerFloor: TimeInterval = 25
}

extension Lecture {

  /// 対応する講義棟（マスタに存在しない棟名の場合はnil）
  var building: CampusBuilding? {
    CampusBuilding.building(named: buildingName, campus: campus)
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
}
