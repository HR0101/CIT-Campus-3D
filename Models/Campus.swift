//
//  Campus.swift
//  CIT-Campus-3D
//
//  キャンパス（津田沼・新習志野）の定義．
//  時間割の場所表記（例: ７３１講義室／津田沼キャンパス）の判別と，
//  マップの初期カメラ位置・建物マスタの絞り込みに使う．
//

import CoreLocation

/// キャンパス（津田沼・新習志野）
enum Campus: Int, CaseIterable, Identifiable, Codable, Hashable {
  /// 津田沼キャンパス（3〜4年）
  case tsudanuma = 1
  /// 新習志野キャンパス（1〜2年）
  case shinNarashino = 2

  var id: Int { rawValue }

  /// 表示名
  var displayName: String {
    switch self {
    case .tsudanuma: return "津田沼"
    case .shinNarashino: return "新習志野"
    }
  }

  /// GeoJSONのcampusプロパティと対応するキー
  var geoJSONKey: String {
    switch self {
    case .tsudanuma: return "tsudanuma"
    case .shinNarashino: return "shinNarashino"
    }
  }

  /// 時間割の場所表記からキャンパスを判別するための識別語
  var locationKeyword: String {
    switch self {
    case .tsudanuma: return "津田沼"
    case .shinNarashino: return "新習志野"
    }
  }

  /// キャンパス中心座標（全棟の重心．初期カメラ位置に使用）
  var center: CLLocationCoordinate2D {
    switch self {
    case .tsudanuma:
      return CLLocationCoordinate2D(latitude: 35.68867, longitude: 140.02080)
    case .shinNarashino:
      return CLLocationCoordinate2D(latitude: 35.66180, longitude: 140.01450)
    }
  }

  /// 「大学周辺」とみなす中心からの半径（メートル）．
  /// WiFiが使えないときの在校判定（受講中の推定）フォールバックに使うため広めに取る
  static let vicinityRadiusMeters: CLLocationDistance = 1_500

  /// 経路（次の授業までの徒歩時間）表示を有効にする，中心からの半径（メートル）．
  /// 「教室まで約N分」は実際にキャンパスへ近づいたときだけ意味があるため，在校判定の半径より狭く取る．
  /// これにより，中心から1.5km圏内でも少し離れた自宅などでは授業前から徒歩時間を表示しない
  static let routeVicinityRadiusMeters: CLLocationDistance = 500

  /// 指定座標がこのキャンパスの周辺（vicinityRadiusMeters以内）にあるか判定する
  func isWithinVicinity(of coordinate: CLLocationCoordinate2D) -> Bool {
    distanceMeters(from: coordinate) <= Self.vicinityRadiusMeters
  }

  /// 指定座標が経路表示の対象範囲（routeVicinityRadiusMeters以内）にあるか判定する
  func isWithinRouteVicinity(of coordinate: CLLocationCoordinate2D) -> Bool {
    distanceMeters(from: coordinate) <= Self.routeVicinityRadiusMeters
  }

  /// 指定座標からキャンパス中心までの距離（メートル）
  func distanceMeters(from coordinate: CLLocationCoordinate2D) -> CLLocationDistance {
    let centerLocation = CLLocation(latitude: center.latitude, longitude: center.longitude)
    let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return centerLocation.distance(from: target)
  }

  /// GeoJSONのキーからキャンパスを判別する（不明な場合はnil）
  init?(geoJSONKey: String) {
    guard let campus = Campus.allCases.first(where: { $0.geoJSONKey == geoJSONKey }) else {
      return nil
    }
    self = campus
  }

  /// 時間割の場所テキストからキャンパスを判別する（既定は津田沼）
  static func detect(fromLocationText text: String) -> Campus {
    if text.contains(Campus.shinNarashino.locationKeyword) {
      return .shinNarashino
    }
    return .tsudanuma
  }
}
