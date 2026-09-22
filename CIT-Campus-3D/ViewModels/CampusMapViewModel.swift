//
//  CampusMapViewModel.swift
//  CIT-Campus-3D
//
//  マップ画面の状態（カメラ・経路・進行フェーズ）を管理するViewModel．
//  目的地は「次の授業」の判定結果に応じて動的に切り替わる．
//  「大学周辺でのみ経路を表示」設定が有効な場合，範囲外では経路を描かない．
//  カメラ操作はCameraCommandとして発行し，MapLibreビューが適用する．
//

import CoreLocation
import Foundation
import MapKit
import Observation

/// ナビゲーションの進行状態
enum NavigationPhase: Equatable {
  /// 初期状態（目的地なしを含む）
  case idle
  /// 現在地の取得待ち
  case waitingForLocation
  /// 大学の周辺ではないため経路を表示していない
  case outsideCampus
  /// 経路を探索中
  case calculatingRoute
  /// 経路の表示中
  case showingRoute
  /// 経路探索に失敗
  case failed(message: String)
}

/// マップカメラへの移動指示（MapLibreビューが受け取って適用する）
struct CameraCommand: Equatable {
  /// 指示の識別子（同じ指示を二重適用しないために使う）
  let id: UUID
  /// 注視点の緯度
  let centerLatitude: CLLocationDegrees
  /// 注視点の経度
  let centerLongitude: CLLocationDegrees
  /// 注視点からカメラまでの距離（メートル）
  let distance: CLLocationDistance
  /// 方位角（北を0°とした時計回りの度数）
  let heading: CLLocationDirection
  /// 3D視点の傾き（度）
  let pitch: CGFloat

  init(
    center: CLLocationCoordinate2D,
    distance: CLLocationDistance,
    heading: CLLocationDirection,
    pitch: CGFloat
  ) {
    self.id = UUID()
    self.centerLatitude = center.latitude
    self.centerLongitude = center.longitude
    self.distance = distance
    self.heading = heading
    self.pitch = pitch
  }

  /// 注視点の座標
  var center: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: centerLatitude, longitude: centerLongitude)
  }

  static func == (lhs: CameraCommand, rhs: CameraCommand) -> Bool {
    lhs.id == rhs.id
  }
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
    /// 経路表示時，出発地〜目的地の直線距離に対してどれだけ引いた視点にするかの倍率
    /// （迂回経路でも両端が画面内に収まるよう余裕を持たせる）
    static let routeDistanceMultiplier: Double = 2.4
    /// 経路が極端に短い場合でも確保するカメラ距離（メートル）
    static let minimumRouteCameraDistance: CLLocationDistance = 400
    /// 現在地フォーカス時のカメラ距離（メートル）
    static let userFocusDistance: CLLocationDistance = 500
  }

  /// 経路の再計算に関する定数
  private enum RouteConstants {
    /// 経路を再計算する出発地の移動しきい値（メートル．これ未満の移動では再計算しない）．
    /// 5m間隔の位置更新ごとに毎回MKDirectionsを呼ばないための間引き
    static let recalculationThresholdMeters: CLLocationDistance = 75
  }

  /// マップへのカメラ移動指示（MapLibreビューが監視する）
  private(set) var cameraCommand: CameraCommand?

  /// 探索済みの徒歩経路
  private(set) var route: MKRoute?

  /// 現在表示中の経路を計算したときの出発地（移動量に応じた再計算の判定に使う）
  private var routeSourceCoordinate: CLLocationCoordinate2D?

  /// 経路計算（MKDirections）が進行中か．多重実行の防止に使う（表示phaseとは独立）
  private var isCalculatingRoute = false

  /// 計算中に届いた最新のリフレッシュ要求（完了後に1回だけ再評価し，取りこぼしを防ぐ）
  private var pendingRefresh: (location: CLLocation?, restrictToCampus: Bool)?

  /// 現在の進行フェーズ
  private(set) var phase: NavigationPhase = .idle

  /// 目的地の講義棟（次の授業の講義棟が不明な場合はnil）
  private(set) var destinationBuilding: CampusBuilding?

  private let routeService = RouteService()

  init(destinationBuilding: CampusBuilding?) {
    self.destinationBuilding = destinationBuilding
    // 起動直後は目的地のキャンパス（未定なら津田沼）の中心を3D視点で見渡す
    let initialCenter = destinationBuilding?.campus.center ?? Campus.tsudanuma.center
    self.cameraCommand = CameraCommand(
      center: initialCenter,
      distance: CameraConstants.initialDistance,
      heading: 0,
      pitch: CameraConstants.pitchDegrees
    )
  }

  /// 目的地を切り替える（次の授業が変わったときに呼ばれる）．
  /// 実際の経路探索はこの後のrefreshRouteで行う．
  func setDestination(_ building: CampusBuilding?) {
    guard building?.id != destinationBuilding?.id else { return }
    destinationBuilding = building
    route = nil
    routeSourceCoordinate = nil
    pendingRefresh = nil
    // 計算中に目的地が変わっても進行表示（探索中バナー）が残らないよう初期化する．
    // この直後にrefreshRouteが呼ばれ，新しい目的地で正しいphaseに再評価される
    phase = .idle
  }

  /// 現在地・設定をもとに，経路の表示状態を更新する．
  /// 現在地の更新・目的地の変更・設定変更のいずれでも呼ばれる中心的なメソッド．
  /// - Parameters:
  ///   - currentLocation: 現在地（未取得ならnil）
  ///   - restrictToCampus: 大学周辺でのみ経路を表示する設定
  func refreshRoute(currentLocation: CLLocation?, restrictToCampus: Bool) async {
    // 経路計算中に来た要求は最新の1件だけ退避し，完了後に再評価する（取りこぼし防止）
    if isCalculatingRoute {
      pendingRefresh = (currentLocation, restrictToCampus)
      return
    }

    // 目的地が未定なら何も表示しない
    guard let building = destinationBuilding else {
      route = nil
      routeSourceCoordinate = nil
      phase = .idle
      return
    }

    // 現在地が未取得なら取得待ち
    guard let location = currentLocation else {
      if route == nil {
        phase = .waitingForLocation
      }
      return
    }

    // 経路表示の範囲判定（制限が無効なら常に範囲内とみなす）．
    // 在校判定より狭い routeVicinityRadius を使い，少し離れた自宅などでは徒歩時間を出さない
    let isWithinCampus = !restrictToCampus
      || building.campus.isWithinRouteVicinity(of: location.coordinate)
    guard isWithinCampus else {
      // 範囲外では経路を出さない
      route = nil
      routeSourceCoordinate = nil
      phase = .outsideCampus
      return
    }

    // 範囲内: 経路が未取得なら探索する．
    // 取得済みでも，出発地から十分移動したらETA・経路を更新する（歩行中の鮮度維持）
    if route == nil || hasMovedEnoughToRecalculate(from: location.coordinate) {
      await calculateRoute(from: location.coordinate, to: building)
    } else {
      phase = .showingRoute
    }
  }

  /// 表示中の経路の出発地から，再計算しきい値を超えて移動したか
  private func hasMovedEnoughToRecalculate(from coordinate: CLLocationCoordinate2D) -> Bool {
    guard let source = routeSourceCoordinate else { return true }
    let from = CLLocation(latitude: source.latitude, longitude: source.longitude)
    let to = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    return from.distance(from: to) > RouteConstants.recalculationThresholdMeters
  }

  /// 経路探索を再試行する（エラーバナーのリトライ用）
  func retryRoute(currentLocation: CLLocation?, restrictToCampus: Bool) async {
    route = nil
    routeSourceCoordinate = nil
    pendingRefresh = nil
    await refreshRoute(currentLocation: currentLocation, restrictToCampus: restrictToCampus)
  }

  /// 現在地を中心にカメラを移動する（現在地ボタン用）
  func focusOnUserLocation(_ location: CLLocation?) {
    guard let location else { return }
    cameraCommand = CameraCommand(
      center: location.coordinate,
      distance: CameraConstants.userFocusDistance,
      heading: 0,
      pitch: CameraConstants.pitchDegrees
    )
  }

  /// 指定した建物へカメラを寄せる（場所一覧から選んだときの即時フィードバック用）
  func focusOnBuilding(_ building: CampusBuilding) {
    cameraCommand = CameraCommand(
      center: building.coordinate,
      distance: CameraConstants.userFocusDistance,
      heading: 0,
      pitch: CameraConstants.pitchDegrees
    )
  }

  // MARK: - Private

  /// 徒歩経路を探索し，成功したらカメラを経路全体へ移動する
  private func calculateRoute(from source: CLLocationCoordinate2D, to building: CampusBuilding) async {
    // 既存経路の更新（歩行中の再計算）か，初回探索かを区別する．
    // 再計算中は探索バナーを出さず既存のカード・経路を表示し続け，カメラも動かさない
    let isRecompute = route != nil
    isCalculatingRoute = true
    if !isRecompute {
      phase = .calculatingRoute
    }

    do {
      let walkingRoute = try await routeService.calculateWalkingRoute(
        from: source,
        to: building.coordinate
      )
      // 探索中に目的地が変わっていなければ結果を反映する（変わっていれば破棄）
      if building.id == destinationBuilding?.id {
        route = walkingRoute
        routeSourceCoordinate = source
        phase = .showingRoute
        if !isRecompute {
          moveCameraToRoute(from: source, to: building.coordinate)
        }
      }
    } catch {
      if building.id == destinationBuilding?.id {
        if isRecompute {
          // 再計算の失敗は既存経路を残す（一時的な失敗で表示を壊さない）
          phase = .showingRoute
        } else {
          route = nil
          routeSourceCoordinate = nil
          phase = .failed(message: error.localizedDescription)
        }
      }
    }

    isCalculatingRoute = false
    // 計算中に届いた最新のリフレッシュ要求を1回だけ再評価する（目的地変更・移動の取りこぼし防止）
    if let pending = pendingRefresh {
      pendingRefresh = nil
      await refreshRoute(currentLocation: pending.location, restrictToCampus: pending.restrictToCampus)
    }
  }

  /// 出発地と目的地の中間にカメラを移し，進行方向を向いた3D視点にする
  private func moveCameraToRoute(
    from source: CLLocationCoordinate2D,
    to destination: CLLocationCoordinate2D
  ) {
    let centerCoordinate = CLLocationCoordinate2D(
      latitude: (source.latitude + destination.latitude) / 2,
      longitude: (source.longitude + destination.longitude) / 2
    )
    // ズームは出発地〜目的地の直線距離（実際にフレームへ収める範囲）で決める．
    // 経路長（迂回で直線の1.5〜2倍になりうる）を使うと引きすぎて両端が小さくなるため
    let span = CLLocation(latitude: source.latitude, longitude: source.longitude)
      .distance(
        from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)
      )
    let cameraDistance = max(
      CameraConstants.minimumRouteCameraDistance,
      span * CameraConstants.routeDistanceMultiplier
    )
    cameraCommand = CameraCommand(
      center: centerCoordinate,
      distance: cameraDistance,
      heading: bearing(from: source, to: destination),
      pitch: CameraConstants.pitchDegrees
    )
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
