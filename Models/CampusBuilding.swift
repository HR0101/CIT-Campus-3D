//
//  CampusBuilding.swift
//  CIT-Campus-3D
//
//  講義棟のマスタデータ．
//  津田沼の座標は実測値（2026-06-12 ユーザー提供），新習志野はOSMの建物重心．
//

import CoreLocation

/// 講義棟を表すモデル（マップ表示用）
struct CampusBuilding: Identifiable, Hashable {
  /// 一意な識別子
  let id: String
  /// 所属キャンパス
  let campus: Campus
  /// 棟名（例: 2号館．時間割の教室番号との対応に使うため「N号館」形式で統一）
  let name: String
  /// 緯度
  let latitude: CLLocationDegrees
  /// 経度
  let longitude: CLLocationDegrees
  /// 建物の高さ（メートル．3D押し出し表示に使用）
  /// OSMに実測値がある棟はその値，ない棟は構内図からの推定値（要調整）
  let heightMeters: Double
  /// 付帯施設の説明（例: 図書館．ない場合はnil）
  let facilityNote: String?

  init(
    id: String,
    campus: Campus,
    name: String,
    latitude: CLLocationDegrees,
    longitude: CLLocationDegrees,
    heightMeters: Double,
    facilityNote: String? = nil
  ) {
    self.id = id
    self.campus = campus
    self.name = name
    self.latitude = latitude
    self.longitude = longitude
    self.heightMeters = heightMeters
    self.facilityNote = facilityNote
  }

  /// MapKitで扱うための座標
  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  /// マップ表示用の名称（例: 5号館（図書館））
  var displayName: String {
    guard let facilityNote else { return name }
    return "\(name)（\(facilityNote)）"
  }
}

// MARK: - 津田沼キャンパス

extension CampusBuilding {

  static let building1 = CampusBuilding(
    id: "bldg-1", campus: .tsudanuma, name: "1号館",
    latitude: 35.68922691016782, longitude: 140.02080340038157,
    heightMeters: 80
  )
  // 2号館は高層タワー＋低層棟の複合形状．heightMetersはタワー部の高さで，
  // 低層棟（南側20m）はCampusBuildings.geojson内のheightプロパティで定義している
  static let building2 = CampusBuilding(
    id: "bldg-2", campus: .tsudanuma, name: "2号館",
    latitude: 35.68812680741046, longitude: 140.02013459558546,
    heightMeters: 75
  )
  static let building3 = CampusBuilding(
    id: "bldg-3", campus: .tsudanuma, name: "3号館",
    latitude: 35.688425626788934, longitude: 140.0216374382655,
    heightMeters: 20,
    facilityNote: "食堂・購買"
  )
  static let building4 = CampusBuilding(
    id: "bldg-4", campus: .tsudanuma, name: "4号館",
    latitude: 35.68825243815841, longitude: 140.02105162021704,
    heightMeters: 15,
    facilityNote: "部室棟"
  )
  static let building5 = CampusBuilding(
    id: "bldg-5", campus: .tsudanuma, name: "5号館",
    latitude: 35.68991717704099, longitude: 140.02067560458983,
    heightMeters: 35,
    facilityNote: "図書館"
  )
  static let building6 = CampusBuilding(
    id: "bldg-6", campus: .tsudanuma, name: "6号館",
    latitude: 35.68879206852663, longitude: 140.02048520598552,
    heightMeters: 20
  )
  static let building7 = CampusBuilding(
    id: "bldg-7", campus: .tsudanuma, name: "7号館",
    latitude: 35.68878154618239, longitude: 140.02177066212877,
    heightMeters: 50
  )
  static let building8 = CampusBuilding(
    id: "bldg-8", campus: .tsudanuma, name: "8号館",
    latitude: 35.687828799177346, longitude: 140.0198429667657,
    heightMeters: 25
  )

  /// 津田沼キャンパスの全講義棟
  static let tsudanumaBuildings: [CampusBuilding] = [
    building1, building2, building3, building4,
    building5, building6, building7, building8,
  ]
}

// MARK: - 新習志野キャンパス

extension CampusBuilding {

  // 座標はOSMの建物重心．高さはOSM実測値（コメントなし）または構内図からの推定値（「推定」と記載）

  static let snBuilding1 = CampusBuilding(
    id: "sn-bldg-1", campus: .shinNarashino, name: "1号館",
    latitude: 35.6625549, longitude: 140.0140636,
    heightMeters: 25  // 推定
  )
  static let snBuilding2 = CampusBuilding(
    id: "sn-bldg-2", campus: .shinNarashino, name: "2号館",
    latitude: 35.6622836, longitude: 140.0142846,
    heightMeters: 16  // 推定
  )
  static let snBuilding3 = CampusBuilding(
    id: "sn-bldg-3", campus: .shinNarashino, name: "3号館",
    latitude: 35.6622248, longitude: 140.0145993,
    heightMeters: 15,  // 推定
    facilityNote: "物理・化学実験室"
  )
  static let snBuilding5 = CampusBuilding(
    id: "sn-bldg-5", campus: .shinNarashino, name: "5号館",
    latitude: 35.6618038, longitude: 140.0140413,
    heightMeters: 12,
    facilityNote: "講義棟"
  )
  static let snBuilding6 = CampusBuilding(
    id: "sn-bldg-6", campus: .shinNarashino, name: "6号館",
    latitude: 35.6618197, longitude: 140.015155,
    heightMeters: 20,  // 推定
    facilityNote: "図書館"
  )
  static let snBuilding7 = CampusBuilding(
    id: "sn-bldg-7", campus: .shinNarashino, name: "7号館",
    latitude: 35.6611073, longitude: 140.0141416,
    heightMeters: 10
  )
  static let snBuilding8 = CampusBuilding(
    id: "sn-bldg-8", campus: .shinNarashino, name: "8号館",
    latitude: 35.6615343, longitude: 140.0133995,
    heightMeters: 11,
    facilityNote: "講義棟・PC演習室"
  )
  static let snBuilding9 = CampusBuilding(
    id: "sn-bldg-9", campus: .shinNarashino, name: "9号館",
    latitude: 35.6612553, longitude: 140.0150201,
    heightMeters: 15  // 推定
  )
  static let snBuilding10 = CampusBuilding(
    id: "sn-bldg-10", campus: .shinNarashino, name: "10号館",
    latitude: 35.6608317, longitude: 140.0145554,
    heightMeters: 15  // 推定
  )
  static let snBuilding11 = CampusBuilding(
    id: "sn-bldg-11", campus: .shinNarashino, name: "11号館",
    latitude: 35.6627511, longitude: 140.0151702,
    heightMeters: 13
  )
  static let snBuilding12 = CampusBuilding(
    id: "sn-bldg-12", campus: .shinNarashino, name: "12号館",
    latitude: 35.6629354, longitude: 140.0132335,
    heightMeters: 28,
    facilityNote: "事務室・ジム"
  )
  static let snCafeteria = CampusBuilding(
    id: "sn-cafeteria", campus: .shinNarashino, name: "食堂棟",
    latitude: 35.662131, longitude: 140.012676,
    heightMeters: 11
  )
  static let snGym = CampusBuilding(
    id: "sn-gym", campus: .shinNarashino, name: "体育館",
    latitude: 35.661496, longitude: 140.015735,
    heightMeters: 18
  )
  static let snDormSouyou = CampusBuilding(
    id: "sn-dorm-souyou", campus: .shinNarashino, name: "桑蓬寮",
    latitude: 35.661011, longitude: 140.016419,
    heightMeters: 36,
    facilityNote: "学生寮"
  )
  static let snDormTsubaki = CampusBuilding(
    id: "sn-dorm-tsubaki", campus: .shinNarashino, name: "椿寮",
    latitude: 35.660398, longitude: 140.017099,
    heightMeters: 28,
    facilityNote: "学生寮"
  )

  /// 新習志野キャンパスの全建物（4号館は存在しない）
  static let shinNarashinoBuildings: [CampusBuilding] = [
    snBuilding1, snBuilding2, snBuilding3, snBuilding5,
    snBuilding6, snBuilding7, snBuilding8, snBuilding9,
    snBuilding10, snBuilding11, snBuilding12,
    snCafeteria, snGym, snDormSouyou, snDormTsubaki,
  ]
}

// MARK: - 検索

extension CampusBuilding {

  /// 全キャンパスの全建物
  static let allBuildings: [CampusBuilding] = tsudanumaBuildings + shinNarashinoBuildings

  /// キャンパスと棟名から講義棟を検索する（例: 津田沼の"2号館"．見つからない場合はnil）
  static func building(named name: String, campus: Campus) -> CampusBuilding? {
    allBuildings.first { $0.campus == campus && $0.name == name }
  }

  /// キャンパスと教室番号から講義棟を推定する（例: "731" → 7号館）
  /// 時間割表の教室名は「先頭の数字＝棟番号」の規則に従っている
  static func building(forRoomNumber roomNumber: String, campus: Campus) -> CampusBuilding? {
    guard let firstDigit = roomNumber.first(where: { $0.isNumber }) else {
      return nil
    }
    return building(named: "\(firstDigit)号館", campus: campus)
  }
}
