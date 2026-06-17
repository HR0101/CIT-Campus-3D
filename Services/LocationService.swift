//
//  LocationService.swift
//  CIT-Campus-3D
//
//  CoreLocationをラップし，現在地と取得状態をSwiftUIへ公開するサービス．
//

import CoreLocation
import Network
import NetworkExtension
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
    /// 採用する水平精度の上限（メートル．これより誤差の大きい測位は捨てて精度を保つ）
    static let acceptableHorizontalAccuracy: CLLocationDistance = 65
    /// 採用する測位の古さの上限（秒．これより古いキャッシュ測位は捨てる）
    static let maxLocationAge: TimeInterval = 15
  }

  /// 最新の現在地（未取得の場合はnil）
  private(set) var currentLocation: CLLocation?

  /// 現在の取得状態
  private(set) var fetchState: LocationFetchState = .idle

  /// 「おおよその位置情報」（低精度）許可かどうか．
  /// trueのとき現在地が数百m〜数kmずれるため，正確な経路を出せない旨を案内する．
  private(set) var isReducedAccuracy: Bool = false

  /// WiFiに接続中か（NWPathMonitorで判定．SSID権限は不要）
  private(set) var isConnectedToWiFi = false

  /// 接続中のWiFiのSSID（取得には Access WiFi Information 権限＝有料アカウントが必要．無料アカウントではnil）
  private(set) var currentSSID: String?

  /// 大学のWiFiとみなすSSIDの集合（実機の優先ネットワーク一覧で確認した千葉工大の構内SSID）．
  /// CIT-ap1x はWPA2 Enterprise(802.1X)の本格構内網，CIT_Wi-Fi も構内網．
  /// eduroamはCITの一覧に無く，他大学のeduroamを誤って在校判定しないため含めない．
  /// 権限が無くSSIDが取れない環境では使われず，WiFi接続＋GPSキャンパス圏内で代替判定する
  static let universitySSIDs: Set<String> = ["CIT_Wi-Fi", "CIT-ap1x"]

  private let locationManager = CLLocationManager()

  /// WiFi接続状態の監視（権限不要でインターフェース種別のみ判定）
  private let pathMonitor = NWPathMonitor()
  private let pathMonitorQueue = DispatchQueue(label: "campus.wifi.path-monitor")

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
    startWiFiMonitoring()
  }

  deinit {
    pathMonitor.cancel()
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

  /// 指定キャンパスの構内にいるか（WiFiを用いた在校判定）．
  /// SSIDが取得できる環境（権限あり）では大学SSIDとの照合を正とし，
  /// 取得できない環境（無料アカウント等）はWiFi接続＋直近GPSのキャンパス圏内で代替判定する．
  /// - Parameter campus: 判定対象のキャンパス
  /// - Returns: 構内にいるとみなせるか
  func isOnCampus(of campus: Campus) -> Bool {
    if let ssid = currentSSID, !ssid.isEmpty {
      // SSIDが取れる環境ではSSID照合を正とする（自宅WiFi等を確実に除外できる）
      return Self.universitySSIDs.contains(ssid)
    }
    // フォールバック: WiFi接続中かつ直近GPSがキャンパス圏内なら在校とみなす
    guard isConnectedToWiFi, let location = currentLocation else { return false }
    return campus.isWithinVicinity(of: location.coordinate)
  }

  // MARK: - Private

  /// WiFi接続状態の監視を開始する
  private func startWiFiMonitoring() {
    pathMonitor.pathUpdateHandler = { [weak self] path in
      let onWiFi = path.usesInterfaceType(.wifi)
      Task { @MainActor in
        self?.handleWiFiPathChange(onWiFi: onWiFi)
      }
    }
    pathMonitor.start(queue: pathMonitorQueue)
  }

  /// WiFi接続状態の変化を反映し，可能ならSSIDを取得する
  private func handleWiFiPathChange(onWiFi: Bool) {
    isConnectedToWiFi = onWiFi
    guard onWiFi else {
      currentSSID = nil
      return
    }
    // SSID取得は権限が必要．取れない（無料アカウント等）場合はnilのままフォールバック判定に委ねる
    NEHotspotNetwork.fetchCurrent { [weak self] network in
      let ssid = network?.ssid
      Task { @MainActor in
        self?.currentSSID = ssid
      }
    }
  }

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
    // 精度が良く新しい測位だけを採用する（誤差の大きい点・古いキャッシュ点を弾いて精度を保つ）
    let now = Date()
    let acceptable = locations.last { location in
      location.horizontalAccuracy >= 0
        && location.horizontalAccuracy <= LocationConstants.acceptableHorizontalAccuracy
        && now.timeIntervalSince(location.timestamp) <= LocationConstants.maxLocationAge
    }
    guard let acceptable else { return }
    Task { @MainActor in
      self.currentLocation = acceptable
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
