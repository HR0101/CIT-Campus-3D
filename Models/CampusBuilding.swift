//
//  CampusBuilding.swift
//  CIT-Campus-3D
//
//  講義棟のマスタデータ．座標は実測値（2026-06-12 ユーザー提供）．
//

import CoreLocation

/// 講義棟を表すモデル（マップ表示用）
struct CampusBuilding: Identifiable, Hashable {
  /// 一意な識別子
  let id: String
  /// 棟名（例: 2号館．時間割の教室番号との対応に使うため「N号館」形式で統一）
  let name: String
  /// 緯度
  let latitude: CLLocationDegrees
  /// 経度
  let longitude: CLLocationDegrees
  /// 建物の高さ（メートル．3D押し出し表示に使用）
  /// ⚠️ 6号館（OSMの5階建て×4m）以外は構内図からの推定値．実際の階数に合わせて調整してください
  let heightMeters: Double
  /// 付帯施設の説明（例: 図書館．ない場合はnil）
  let facilityNote: String?

  init(
    id: String,
    name: String,
    latitude: CLLocationDegrees,
    longitude: CLLocationDegrees,
    heightMeters: Double,
    facilityNote: String? = nil
  ) {
    self.id = id
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

extension CampusBuilding {

  /// 津田沼キャンパスの中心座標（全棟の重心．初期カメラ位置に使用）
  static let campusCenter = CLLocationCoordinate2D(
    latitude: 35.68867,
    longitude: 140.02080
  )

  static let building1 = CampusBuilding(
    id: "bldg-1", name: "1号館",
    latitude: 35.68922691016782, longitude: 140.02080340038157,
    heightMeters: 80
  )
  // 2号館は高層タワー＋低層棟の複合形状．heightMetersはタワー部の高さで，
  // 低層棟（東側20m）はCampusBuildings.geojson内のheightプロパティで定義している
  static let building2 = CampusBuilding(
    id: "bldg-2", name: "2号館",
    latitude: 35.68812680741046, longitude: 140.02013459558546,
    heightMeters: 75
  )
  static let building3 = CampusBuilding(
    id: "bldg-3", name: "3号館",
    latitude: 35.688425626788934, longitude: 140.0216374382655,
    heightMeters: 20,
    facilityNote: "食堂・購買"
  )
  static let building4 = CampusBuilding(
    id: "bldg-4", name: "4号館",
    latitude: 35.68825243815841, longitude: 140.02105162021704,
    heightMeters: 15,
    facilityNote: "部室棟"
  )
  static let building5 = CampusBuilding(
    id: "bldg-5", name: "5号館",
    latitude: 35.68991717704099, longitude: 140.02067560458983,
    heightMeters: 35,
    facilityNote: "図書館"
  )
  static let building6 = CampusBuilding(
    id: "bldg-6", name: "6号館",
    latitude: 35.68879206852663, longitude: 140.02048520598552,
    heightMeters: 20
  )
  static let building7 = CampusBuilding(
    id: "bldg-7", name: "7号館",
    latitude: 35.68878154618239, longitude: 140.02177066212877,
    heightMeters: 50
  )
  static let building8 = CampusBuilding(
    id: "bldg-8", name: "8号館",
    latitude: 35.687828799177346, longitude: 140.0198429667657,
    heightMeters: 25
  )

  /// 津田沼キャンパスの全講義棟
  static let tsudanumaBuildings: [CampusBuilding] = [
    building1, building2, building3, building4,
    building5, building6, building7, building8,
  ]

  /// 棟名から講義棟を検索する（例: "2号館"．見つからない場合はnil）
  static func building(named name: String) -> CampusBuilding? {
    tsudanumaBuildings.first { $0.name == name }
  }

  /// 教室番号から講義棟を推定する（例: "731" → 7号館）
  /// 時間割表の教室名は「先頭の数字＝棟番号」の規則に従っている
  static func building(forRoomNumber roomNumber: String) -> CampusBuilding? {
    guard let firstDigit = roomNumber.first(where: { $0.isNumber }) else {
      return nil
    }
    return building(named: "\(firstDigit)号館")
  }
}
