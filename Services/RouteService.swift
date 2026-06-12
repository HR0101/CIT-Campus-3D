//
//  RouteService.swift
//  CIT-Campus-3D
//
//  MKDirectionsを用いて徒歩経路を取得するサービス．
//

import CoreLocation
import MapKit

/// 経路探索で発生しうるエラー
enum RouteError: LocalizedError {
  /// 経路が見つからなかった
  case routeNotFound
  /// 通信エラーなどMapKit側の失敗
  case calculationFailed(reason: String)

  var errorDescription: String? {
    switch self {
    case .routeNotFound:
      return "徒歩ルートが見つかりませんでした．目的地の座標を確認してください．"
    case .calculationFailed(let reason):
      return "経路の取得に失敗しました（\(reason)）"
    }
  }
}

/// 徒歩経路の探索を担うサービス
struct RouteService {

  /// 出発地から目的地までの徒歩経路を取得する
  /// - Parameters:
  ///   - source: 出発地点の座標（通常は現在地）
  ///   - destination: 目的地の座標（講義棟）
  /// - Returns: 候補のうち先頭の徒歩経路
  func calculateWalkingRoute(
    from source: CLLocationCoordinate2D,
    to destination: CLLocationCoordinate2D
  ) async throws -> MKRoute {
    let request = MKDirections.Request()
    request.source = MKMapItem(
      location: CLLocation(latitude: source.latitude, longitude: source.longitude),
      address: nil
    )
    request.destination = MKMapItem(
      location: CLLocation(latitude: destination.latitude, longitude: destination.longitude),
      address: nil
    )
    request.transportType = .walking

    do {
      let response = try await MKDirections(request: request).calculate()
      guard let route = response.routes.first else {
        throw RouteError.routeNotFound
      }
      return route
    } catch let error as RouteError {
      throw error
    } catch {
      throw RouteError.calculationFailed(reason: error.localizedDescription)
    }
  }
}
