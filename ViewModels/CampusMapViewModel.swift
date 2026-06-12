//
//  CampusMapViewModel.swift
//  CIT-Campus-3D
//
//  マップ画面の状態（カメラ・経路・進行フェーズ）を管理するViewModel．
//  目的地は「次の授業」の判定結果に応じて動的に切り替わる．
//

import MapKit
import Observation
import SwiftUI

/// ナビゲーションの進行状態
enum NavigationPhase: Equatable {
  /// 初期状態（目的地なしを含む）
  case idle
  /// 現在地の取得待ち
  case waitingForLocation
  /// 経路を探索中
  case calculatingRoute
  /// 経路の表示中
  case showingRoute
  /// 経路探索に失敗
  case failed(message: String)
}

/// 3Dマップ画面のViewModel
@MainActor
@Observable
final class CampusMapViewModel {

  /// カメラ演出に関する定数
  private enum CameraConstants {
    /// 起動直後にキャンパス全体を見渡す距離（メートル）
    static let initialDistance: CLLocationDistance = 1_200
    /// 3D視点の傾き（度）．60°でビルの立体感が出る
    static let pitchDegrees: CGFloat = 60
    /// 経路表示時，経路長に対してどれだけ引いた視点にするかの倍率
    static let routeDistanceMultiplier: Double = 2.2
    /// 経路が極端に短い場合でも確保するカメラ距離（メートル）
    static let minimumRouteCameraDistance: CLLocationDistance = 400
    /// カメラ移動アニメーションの秒数
    static let cameraAnimationDuration: Double = 1.0
  }

  /// マップのカメラ位置（Viewとバインドする）
  var cameraPosition: MapCameraPosition

  /// 探索済みの徒歩経路
  private(set) var route: MKRoute?

  /// 現在の進行フェーズ
  private(set) var phase: NavigationPhase = .idle

  /// 目的地の講義棟（次の授業の講義棟が不明な場合はnil）
  private(set) var destinationBuilding: CampusBuilding?

  private let routeService = RouteService()

  init(destinationBuilding: CampusBuilding?) {
    self.destinationBuilding = destinationBuilding
    // 起動直後はキャンパス中心を3D視点（pitch付き）で見渡す
    self.cameraPosition = .camera(
      MapCamera(
        centerCoordinate: CampusBuilding.campusCenter,
        distance: CameraConstants.initialDistance,
        heading: 0,
        pitch: CameraConstants.pitchDegrees
      )
    )
  }

  /// 現在地の更新を受け取り，未探索なら経路を探索する
  /// （探索失敗後はユーザーの「再試行」操作まで自動では再探索しない）
  func handleLocationUpdate(_ location: CLLocation?) async {
    guard
      let location,
      destinationBuilding != nil,
      route == nil,
      phase == .idle || phase == .waitingForLocation
    else {
      return
    }
    await calculateRoute(from: location.coordinate)
  }

  /// 目的地を切り替える（次の授業が変わったときに呼ばれる）
  func updateDestination(
    _ building: CampusBuilding?,
    currentLocation: CLLocation?
  ) async {
    guard building?.id != destinationBuilding?.id else { return }
    destinationBuilding = building
    route = nil

    guard building != nil else {
      phase = .idle
      return
    }
    if let currentLocation {
      await calculateRoute(from: currentLocation.coordinate)
    } else {
      phase = .waitingForLocation
    }
  }

  /// 経路探索を再試行する（エラーバナーのリトライ用）
  func retryRoute(from location: CLLocation?) async {
    guard destinationBuilding != nil else { return }
    guard let location else {
      phase = .waitingForLocation
      return
    }
    await calculateRoute(from: location.coordinate)
  }

  // MARK: - Private

  /// 徒歩経路を探索し，成功したらカメラを経路全体へ移動する
  private func calculateRoute(from source: CLLocationCoordinate2D) async {
    guard let destination = destinationBuilding else { return }
    phase = .calculatingRoute
    do {
      let walkingRoute = try await routeService.calculateWalkingRoute(
        from: source,
        to: destination.coordinate
      )
      route = walkingRoute
      phase = .showingRoute
      moveCameraToRoute(
        from: source,
        to: destination.coordinate,
        routeDistance: walkingRoute.distance
      )
    } catch {
      route = nil
      phase = .failed(message: error.localizedDescription)
    }
  }

  /// 出発地と目的地の中間にカメラを移し，進行方向を向いた3D視点にする
  private func moveCameraToRoute(
    from source: CLLocationCoordinate2D,
    to destination: CLLocationCoordinate2D,
    routeDistance: CLLocationDistance
  ) {
    let centerCoordinate = CLLocationCoordinate2D(
      latitude: (source.latitude + destination.latitude) / 2,
      longitude: (source.longitude + destination.longitude) / 2
    )
    let cameraDistance = max(
      CameraConstants.minimumRouteCameraDistance,
      routeDistance * CameraConstants.routeDistanceMultiplier
    )
    let cameraHeading = bearing(from: source, to: destination)

    withAnimation(.easeInOut(duration: CameraConstants.cameraAnimationDuration)) {
      cameraPosition = .camera(
        MapCamera(
          centerCoordinate: centerCoordinate,
          distance: cameraDistance,
          heading: cameraHeading,
          pitch: CameraConstants.pitchDegrees
        )
      )
    }
  }

  /// 2点間の方位角（北を0°とした時計回りの度数）を計算する
  private func bearing(
    from source: CLLocationCoordinate2D,
    to destination: CLLocationCoordinate2D
  ) -> CLLocationDirection {
    let sourceLatitude = source.latitude * .pi / 180
    let sourceLongitude = source.longitude * .pi / 180
    let destinationLatitude = destination.latitude * .pi / 180
    let destinationLongitude = destination.longitude * .pi / 180
    let deltaLongitude = destinationLongitude - sourceLongitude

    let y = sin(deltaLongitude) * cos(destinationLatitude)
    let x = cos(sourceLatitude) * sin(destinationLatitude)
      - sin(sourceLatitude) * cos(destinationLatitude) * cos(deltaLongitude)
    let degrees = atan2(y, x) * 180 / .pi

    // atan2は-180°〜180°を返すため，0°〜360°に正規化する
    return (degrees + 360).truncatingRemainder(dividingBy: 360)
  }
}
