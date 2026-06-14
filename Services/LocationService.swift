//
//  LocationService.swift
//  CIT-Campus-3D
//
//  CoreLocationをラップし，現在地と取得状態をSwiftUIへ公開するサービス．
//

import CoreLocation
import Observation

/// 位置情報の取得状態を表す列挙型
enum LocationFetchState: Equatable {
  /// 未開始
  case idle
  /// 許可リクエスト中または位置取得中
  case locating
  /// 取得成功（最新の位置はcurrentLocationを参照）
  case available
  /// ユーザーが許可を拒否
  case denied
  /// ペアレンタルコントロール等による利用制限
  case restricted
  /// 取得失敗（GPS不調・機内モードなど）
  case failed(reason: String)
}

/// 現在地の取得と許可状態の管理を担うサービス
@MainActor
@Observable
final class LocationService: NSObject {

  /// 位置情報の精度・更新頻度に関する定数
  private enum LocationConstants {
    /// ナビ用途のため最高精度を要求する
    static let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    /// 5m以上移動した場合のみ更新を受け取る（バッテリー消費対策）
    static let distanceFilter: CLLocationDistance = 5.0
  }

  /// 最新の現在地（未取得の場合はnil）
  private(set) var currentLocation: CLLocation?

  /// 現在の取得状態
  private(set) var fetchState: LocationFetchState = .idle

  /// 「おおよその位置情報」（低精度）許可かどうか．
  /// trueのとき現在地が数百m〜数kmずれるため，正確な経路を出せない旨を案内する．
  private(set) var isReducedAccuracy: Bool = false

  private let locationManager = CLLocationManager()

  /// 位置更新を稼働中か（多重start/stopの抑止）
  private var isUpdating = false

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = LocationConstants.desiredAccuracy
    locationManager.distanceFilter = LocationConstants.distanceFilter
    // 徒歩キャンパスナビ用途に最適化する
    locationManager.activityType = .fitness
    // 静止検知による自動一時停止を無効化し，立ち止まり後の現在地が古くならないようにする
    // （バックグラウンドではstopUpdating()で明示的に停止するため常時稼働にはならない）
    locationManager.pausesLocationUpdatesAutomatically = false
    updateAccuracy()
  }

  /// 位置情報の利用許可を確認し，現在地の取得を開始する（多重呼び出しに対して冪等）
  func startUpdating() {
    switch locationManager.authorizationStatus {
    case .notDetermined:
      // 初回起動時: 許可ダイアログを表示する．
      // 結果はlocationManagerDidChangeAuthorizationで受け取る．
      fetchState = .locating
      locationManager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      beginUpdatingIfNeeded()
    case .denied:
      fetchState = .denied
    case .restricted:
      fetchState = .restricted
    @unknown default:
      fetchState = .failed(reason: "不明な許可状態です")
    }
  }

  /// 現在地の取得を停止する（画面離脱時に呼ぶ）
  func stopUpdating() {
    isUpdating = false
    locationManager.stopUpdatingLocation()
    // 最初の測位前に画面を離れた場合，「取得中」表示が残らないよう初期状態へ戻す．
    // 取得済み(.available)・拒否(.denied)などの確定状態は維持する
    if fetchState == .locating {
      fetchState = .idle
    }
  }

  // MARK: - Private

  /// 位置更新を開始する（稼働中なら何もしない）
  private func beginUpdatingIfNeeded() {
    guard !isUpdating else { return }
    isUpdating = true
    fetchState = .locating
    locationManager.startUpdatingLocation()
  }

  /// 現在の精度許可（正確／おおよそ）を反映する
  private func updateAccuracy() {
    isReducedAccuracy = locationManager.accuracyAuthorization == .reducedAccuracy
  }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {

  /// 許可状態が変化したときに呼ばれる
  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in
      // 設定アプリでの「正確な位置情報」切り替えもこのデリゲートで通知されるため反映する
      self.updateAccuracy()
      switch status {
      case .authorizedWhenInUse, .authorizedAlways:
        self.beginUpdatingIfNeeded()
      case .denied:
        self.fetchState = .denied
      case .restricted:
        self.fetchState = .restricted
      case .notDetermined:
        // 許可ダイアログの応答待ち．何もしない．
        break
      @unknown default:
        self.fetchState = .failed(reason: "不明な許可状態です")
      }
    }
  }

  /// 新しい位置情報を受信したときに呼ばれる
  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didUpdateLocations locations: [CLLocation]
  ) {
    guard let latestLocation = locations.last else { return }
    Task { @MainActor in
      self.currentLocation = latestLocation
      self.fetchState = .available
    }
  }

  /// 位置情報の取得に失敗したときに呼ばれる
  nonisolated func locationManager(
    _ manager: CLLocationManager,
    didFailWithError error: Error
  ) {
    // locationUnknownは一時的なエラーのため，無視して取得を継続する
    if let clError = error as? CLError, clError.code == .locationUnknown {
      return
    }
    let message = error.localizedDescription
    Task { @MainActor in
      // すでに有効な現在地を取得済みなら，一時的な失敗で「失敗」状態に落とさない
      // （キャッシュした現在地で経路表示を継続できるため）
      guard self.currentLocation == nil else { return }
      self.fetchState = .failed(reason: message)
    }
  }
}
