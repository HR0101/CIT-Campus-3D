//
//  MapLibreMapView.swift
//  CIT-Campus-3D
//
//  MapLibre（OpenFreeMapの無料OSMタイル）による3Dキャンパスマップ．
//  構成は2層:
//    1. ベース地図: OpenFreeMapのスタイル（OSMベクタータイル．道路・ラベルなど）
//    2. キャンパスの建物: OSM実測の外形ポリゴン（同梱GeoJSON）＋自前の高さデータで3D表示する
//  周辺市街のビルは，OSMタイルの建物とキャンパス棟がほぼ同一形状で二重に押し出されて
//  Z-fighting（視点移動時のちらつき）を起こすため，あえて描画せず大学の建物だけを3Dにする．
//

import MapKit
import MapLibre
import SwiftUI
import UIKit

/// MapLibreベースの3DマップのSwiftUIラッパ
struct MapLibreMapView: UIViewRepresentable {

  /// スタイル・レイヤに関する定数
  enum MapConstants {
    /// OpenFreeMapのダークスタイル（APIキー不要・無料）
    static let darkStyleURL = URL(string: "https://tiles.openfreemap.org/styles/dark")
    /// OpenFreeMapのライトスタイル．positronはCarto Positron系統の低彩度な明るいグレー基調で，
    /// 中立的な背景と控えめな道路色がfill-extrusionのビル塊と経路線を引き立てる（darkの明るい対応物）
    static let lightStyleURL = URL(string: "https://tiles.openfreemap.org/styles/positron")

    /// カラースキームに応じたベース地図スタイルURLを返す
    static func styleURL(for colorScheme: ColorScheme) -> URL? {
      colorScheme == .dark ? darkStyleURL : lightStyleURL
    }
    /// キャンパス棟のGeoJSONソースのID
    static let campusSourceID = "campus-buildings-source"
    /// キャンパス棟の3DレイヤのID
    static let campusLayerID = "campus-3d-buildings"
    /// 運動場など平面施設（kind=ground）のフラット塗りレイヤのID
    static let campusGroundLayerID = "campus-ground"
    /// 経路ソースのID
    static let routeSourceID = "route-source"
    /// 経路レイヤのID
    static let routeLayerID = "route-layer"
    /// 同梱GeoJSONのファイル名
    static let campusGeoJSONName = "CampusBuildings"
    /// カメラ移動アニメーションの秒数
    static let cameraAnimationDuration: TimeInterval = 1.2
    // ベース地図の明暗に合わせて建物・経路の色を切り替える（ライト/ダークの2系統）．
    // ダークは暗いグレー基調，ライトはpositronの淡い背景でも塊が分かる明るめのグレーにする．
    /// キャンパス棟の色（ダーク: ベース地図から浮く明るめのグレー）
    static let campusBuildingColorDark = UIColor(white: 0.34, alpha: 1.0)
    /// キャンパス棟の色（ライト: 淡い背景の上でも塊が分かる中明度のグレー）
    static let campusBuildingColorLight = UIColor(white: 0.62, alpha: 1.0)
    /// キャンパス棟の不透明度（完全不透明）
    static let campusBuildingOpacity: Float = 1.0
    /// 運動場など平面施設の色（ダーク: 芝を思わせる落ち着いた緑）
    static let groundColorDark = UIColor(red: 0.16, green: 0.32, blue: 0.22, alpha: 1.0)
    /// 運動場など平面施設の色（ライト: 淡い背景に馴染む明るめの緑）
    static let groundColorLight = UIColor(red: 0.55, green: 0.74, blue: 0.58, alpha: 1.0)
    /// 平面施設の不透明度
    static let groundOpacity: Float = 1.0
    /// 経路線の色（ダーク: シアン）
    static let routeColorDark = UIColor.systemCyan
    /// 経路線の色（ライト: 淡い背景でもコントラストが出る濃いめの青）
    static let routeColorLight = UIColor(red: 0.0, green: 0.42, blue: 0.78, alpha: 1.0)
    /// 経路線の太さ
    static let routeWidth: CGFloat = 5.0
  }

  /// 目的地の講義棟（パルスピンの表示対象）
  let destinationBuilding: CampusBuilding?

  /// 描画する徒歩経路
  let route: MKRoute?

  /// カメラ移動指示
  let cameraCommand: CameraCommand?

  /// 現在のカラースキーム（ライト/ダークでベース地図スタイルと建物・経路色を切り替える）
  let colorScheme: ColorScheme

  func makeUIView(context: Context) -> MLNMapView {
    context.coordinator.colorScheme = colorScheme
    context.coordinator.appliedColorScheme = colorScheme
    let mapView = MLNMapView(
      frame: .zero,
      styleURL: MapConstants.styleURL(for: colorScheme)
    )
    mapView.delegate = context.coordinator
    mapView.showsUserLocation = true
    context.coordinator.mapView = mapView

    // カメラはビューのサイズ確定前に設定しても効かないため，
    // マップ読み込み完了後にCoordinatorが保留分を適用する
    context.coordinator.apply(
      destination: destinationBuilding,
      route: route,
      cameraCommand: cameraCommand
    )
    return mapView
  }

  func updateUIView(_ mapView: MLNMapView, context: Context) {
    context.coordinator.colorScheme = colorScheme
    // 外観（ライト/ダーク）が変わったらベース地図スタイルを差し替える．
    // スタイル再読込後にdidFinishLoading→configureStyleが3Dビル・経路レイヤを再構築する
    if context.coordinator.appliedColorScheme != colorScheme {
      context.coordinator.appliedColorScheme = colorScheme
      context.coordinator.prepareForStyleReload()
      if let url = MapConstants.styleURL(for: colorScheme) {
        mapView.styleURL = url
      }
    }
    context.coordinator.apply(
      destination: destinationBuilding,
      route: route,
      cameraCommand: cameraCommand
    )
  }

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }
}

// MARK: - Coordinator

extension MapLibreMapView {

  /// MapLibreビューの状態管理とデリゲート処理
  @MainActor
  final class Coordinator: NSObject {

    weak var mapView: MLNMapView?

    /// 現在のカラースキーム（レイヤ色の選択に使う．updateUIViewから設定される）
    var colorScheme: ColorScheme = .dark

    /// スタイルへ適用済みのカラースキーム（変化検知用）
    var appliedColorScheme: ColorScheme?

    /// スタイルの読み込みが完了したか
    private var isStyleLoaded = false

    /// 適用済みのカメラ指示ID（二重適用の防止）
    private var appliedCameraCommandID: UUID?

    /// マップ読み込み前に受け取ったカメラ指示の退避先
    private var pendingCameraCommand: CameraCommand?

    /// 表示済みの経路（オブジェクト同一性で差分判定）
    private var appliedRoute: MKRoute?

    /// 表示済みの目的地ID
    private var appliedDestinationID: String?

    /// 棟マーカーを一度でも追加したか
    private var hasAddedAnnotations = false

    /// 経路描画用のソース（スタイル読み込み後に生成）
    private var routeSource: MLNShapeSource?

    /// スタイル読み込み前に受け取った経路の退避先
    private var pendingRoute: MKRoute?

    /// 追加済みの棟アノテーション
    private var buildingAnnotations: [CampusPointAnnotation] = []

    // MARK: - SwiftUIからの状態反映

    /// 最新の状態（目的地・経路・カメラ）をマップへ反映する
    func apply(
      destination: CampusBuilding?,
      route: MKRoute?,
      cameraCommand: CameraCommand?
    ) {
      applyCamera(cameraCommand)
      applyRoute(route)
      applyAnnotations(destination: destination)
    }

    /// スタイル差し替え（ライト/ダーク切り替え）の直前に，スタイルへ紐づく状態をリセットする．
    /// 新スタイル読み込み後のconfigureStyleで3Dビル・経路レイヤが再構築され，
    /// 直後のapply(...)で現在の経路が再描画される．
    /// カメラとアノテーションはスタイル変更後も保持されるためリセットしない．
    func prepareForStyleReload() {
      isStyleLoaded = false
      routeSource = nil
      appliedRoute = nil
    }

    /// CameraCommandからMapLibreのカメラを生成する
    static func makeCamera(from command: CameraCommand) -> MLNMapCamera {
      // MapKitのdistance（視線方向の距離）をMapLibreのaltitude（高度）へ換算する
      let pitchRadians = Double(command.pitch) * .pi / 180
      let altitude = command.distance * cos(pitchRadians)
      return MLNMapCamera(
        lookingAtCenter: command.center,
        altitude: altitude,
        pitch: command.pitch,
        heading: command.heading
      )
    }

    // MARK: - スタイル構築（デリゲートから呼ばれる）

    /// スタイル読み込み完了後に3Dビル・経路レイヤを構築する
    func configureStyle(_ style: MLNStyle) {
      isStyleLoaded = true
      addCampusBuildingsLayer(to: style)
      setupRouteLayer(in: style)

      // スタイル読み込み前に届いていた経路を反映する
      if let pendingRoute {
        self.pendingRoute = nil
        appliedRoute = nil
        applyRoute(pendingRoute)
      }
      // 保留中のカメラ指示を即時適用する（初期表示用）
      if let pendingCameraCommand, let mapView {
        self.pendingCameraCommand = nil
        appliedCameraCommandID = pendingCameraCommand.id
        mapView.setCamera(Self.makeCamera(from: pendingCameraCommand), animated: false)
      }
    }

    // MARK: - Private（カラースキームに応じた色）

    /// キャンパス棟の色（現在のカラースキームに対応）
    private var campusBuildingColor: UIColor {
      colorScheme == .dark
        ? MapConstants.campusBuildingColorDark : MapConstants.campusBuildingColorLight
    }

    /// 平面施設（運動場など）の色（現在のカラースキームに対応）
    private var groundColor: UIColor {
      colorScheme == .dark ? MapConstants.groundColorDark : MapConstants.groundColorLight
    }

    /// 経路線の色（現在のカラースキームに対応）
    private var routeColor: UIColor {
      colorScheme == .dark ? MapConstants.routeColorDark : MapConstants.routeColorLight
    }

    // MARK: - Private（レイヤ構築）

    /// キャンパス8棟の高忠実3Dレイヤ（同梱GeoJSON＋自前の高さ）を追加する
    private func addCampusBuildingsLayer(to style: MLNStyle) {
      guard
        let url = Bundle.main.url(
          forResource: MapConstants.campusGeoJSONName,
          withExtension: "geojson"
        ),
        let data = try? Data(contentsOf: url),
        let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue),
        let collection = shape as? MLNShapeCollectionFeature
      else {
        // GeoJSONが読めない場合は市街レイヤのみで描画を続行する
        return
      }

      // 各ポリゴンへ高さを付与する．
      // GeoJSON側にheightが明示されていればそれを優先し（複合形状の低層部など），
      // なければキャンパス＋棟名でマスタの高さ（heightMeters）を引く
      for case let polygon as MLNPolygonFeature in collection.shapes {
        let name = polygon.attribute(forKey: "name") as? String ?? ""
        let campusKey = polygon.attribute(forKey: "campus") as? String ?? ""
        let campus = Campus(geoJSONKey: campusKey) ?? .tsudanuma
        let explicitHeight = polygon.attribute(forKey: "height") as? Double
        let height = explicitHeight
          ?? CampusBuilding.building(named: name, campus: campus)?.heightMeters
          ?? 0
        var attributes = polygon.attributes
        attributes["height"] = height
        polygon.attributes = attributes
      }

      let source = MLNShapeSource(
        identifier: MapConstants.campusSourceID,
        shape: collection,
        options: nil
      )
      style.addSource(source)

      // 運動場など平面施設（kind=ground）はフラットな塗りで表示する（押し出さない）
      let groundLayer = MLNFillStyleLayer(
        identifier: MapConstants.campusGroundLayerID,
        source: source
      )
      groundLayer.predicate = NSPredicate(format: "kind == %@", "ground")
      groundLayer.fillColor = NSExpression(forConstantValue: groundColor)
      groundLayer.fillOpacity = NSExpression(forConstantValue: MapConstants.groundOpacity)
      // 道路など地物の上・ラベルの下に挿入する（街路名などのラベルが建物に隠れないようにする）
      if let lastGeometryLayer = style.layers.last(where: { !($0 is MLNSymbolStyleLayer) }) {
        style.insertLayer(groundLayer, above: lastGeometryLayer)
      } else {
        style.addLayer(groundLayer)
      }

      // 講義棟などの建物（kind != ground）は高さに応じて3D押し出しで表示する
      let layer = MLNFillExtrusionStyleLayer(
        identifier: MapConstants.campusLayerID,
        source: source
      )
      layer.predicate = NSPredicate(format: "kind == nil OR kind != %@", "ground")
      layer.fillExtrusionHeight = NSExpression(forKeyPath: "height")
      layer.fillExtrusionBase = NSExpression(forConstantValue: 0)
      layer.fillExtrusionColor = NSExpression(forConstantValue: campusBuildingColor)
      layer.fillExtrusionOpacity = NSExpression(
        forConstantValue: MapConstants.campusBuildingOpacity
      )
      style.insertLayer(layer, above: groundLayer)
    }

    /// 経路描画用のソースとレイヤを準備する
    private func setupRouteLayer(in style: MLNStyle) {
      let source = MLNShapeSource(identifier: MapConstants.routeSourceID, shape: nil, options: nil)
      style.addSource(source)
      routeSource = source

      let layer = MLNLineStyleLayer(identifier: MapConstants.routeLayerID, source: source)
      layer.lineColor = NSExpression(forConstantValue: routeColor)
      layer.lineWidth = NSExpression(forConstantValue: MapConstants.routeWidth)
      layer.lineCap = NSExpression(forConstantValue: "round")
      layer.lineJoin = NSExpression(forConstantValue: "round")
      style.addLayer(layer)
    }

    // MARK: - Private（状態反映）

    /// カメラ指示を適用する（未適用の指示のみ）
    private func applyCamera(_ command: CameraCommand?) {
      guard
        let command,
        command.id != appliedCameraCommandID,
        let mapView
      else {
        return
      }
      // マップ読み込み前はビューのサイズが未確定でカメラ計算が効かないため退避する
      guard isStyleLoaded else {
        pendingCameraCommand = command
        return
      }
      appliedCameraCommandID = command.id
      mapView.fly(
        to: Self.makeCamera(from: command),
        withDuration: MapConstants.cameraAnimationDuration,
        completionHandler: nil
      )
    }

    /// 経路の表示を更新する
    private func applyRoute(_ route: MKRoute?) {
      guard route !== appliedRoute else { return }

      guard isStyleLoaded, let routeSource else {
        // スタイル読み込み前は退避しておき，読み込み完了後に反映する
        pendingRoute = route
        return
      }
      appliedRoute = route

      guard let route else {
        routeSource.shape = nil
        return
      }
      let polyline = route.polyline
      var coordinates = [CLLocationCoordinate2D](
        repeating: kCLLocationCoordinate2DInvalid,
        count: polyline.pointCount
      )
      polyline.getCoordinates(
        &coordinates,
        range: NSRange(location: 0, length: polyline.pointCount)
      )
      routeSource.shape = MLNPolylineFeature(
        coordinates: &coordinates,
        count: UInt(coordinates.count)
      )
    }

    /// 棟マーカー（全棟バッジ＋目的地パルスピン）を更新する
    private func applyAnnotations(destination: CampusBuilding?) {
      guard let mapView else { return }
      let newDestinationID = destination?.id

      // 初回のみ全棟マーカーを追加する
      guard hasAddedAnnotations else {
        hasAddedAnnotations = true
        appliedDestinationID = newDestinationID
        buildingAnnotations = CampusBuilding.allBuildings.map { building in
          let annotation = CampusPointAnnotation()
          annotation.coordinate = building.coordinate
          annotation.building = building
          annotation.isDestination = building.id == newDestinationID
          return annotation
        }
        mapView.addAnnotations(buildingAnnotations)
        return
      }

      // 2回目以降は目的地が変わったマーカー（旧・新）だけを差し替える．
      // 全消し再追加は24個のUIHostingControllerを毎回作り直して全バッジがちらつくため避ける．
      // MapLibreは追加時のみviewForを再問い合わせるので，対象だけremove→addする
      guard newDestinationID != appliedDestinationID else { return }
      let changedIDs = Set([appliedDestinationID, newDestinationID].compactMap { $0 })
      appliedDestinationID = newDestinationID
      let changedAnnotations = buildingAnnotations.filter { annotation in
        guard let id = annotation.building?.id else { return false }
        return changedIDs.contains(id)
      }
      guard !changedAnnotations.isEmpty else { return }
      for annotation in changedAnnotations {
        annotation.isDestination = annotation.building?.id == newDestinationID
      }
      mapView.removeAnnotations(changedAnnotations)
      mapView.addAnnotations(changedAnnotations)
    }
  }
}

// MARK: - MLNMapViewDelegate

extension MapLibreMapView.Coordinator: MLNMapViewDelegate {

  /// スタイルの読み込みが完了したときに呼ばれる
  nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    MainActor.assumeIsolated {
      self.configureStyle(style)
    }
  }

  /// アノテーションの表示ビューを返す
  nonisolated func mapView(
    _ mapView: MLNMapView,
    viewFor annotation: MLNAnnotation
  ) -> MLNAnnotationView? {
    MainActor.assumeIsolated {
      guard
        let campusAnnotation = annotation as? CampusPointAnnotation,
        let building = campusAnnotation.building
      else {
        // 現在地などはMapLibre標準の表示に任せる
        return nil
      }
      if campusAnnotation.isDestination {
        // 目的地はパルスアニメーション付きピン（座標が底辺中央に来るよう上へずらす）
        return HostedAnnotationView(
          rootView: AnyView(DestinationMarkerView()),
          anchorToBottom: true,
          accessibilityLabel: "目的地: \(building.displayName)、次の授業の棟"
        )
      }
      return HostedAnnotationView(
        rootView: AnyView(BuildingAnnotationView(building: building)),
        anchorToBottom: false,
        accessibilityLabel: building.displayName
      )
    }
  }

  /// コールアウト（吹き出し）は使わない（ラベルはマーカー内に常時表示）
  nonisolated func mapView(
    _ mapView: MLNMapView,
    annotationCanShowCallout annotation: MLNAnnotation
  ) -> Bool {
    false
  }
}

// MARK: - アノテーション

/// 講義棟のアノテーション（対象の棟と目的地フラグを保持）
final class CampusPointAnnotation: MLNPointAnnotation {
  var building: CampusBuilding?
  var isDestination = false
}

/// SwiftUIビューを埋め込むアノテーションビュー
final class HostedAnnotationView: MLNAnnotationView {

  /// 埋め込んだSwiftUIビューのホスト（生存期間の保持用）
  private let hostingController: UIHostingController<AnyView>

  /// - Parameters:
  ///   - rootView: 表示するSwiftUIビュー
  ///   - anchorToBottom: trueの場合，座標がビューの底辺中央に来るよう配置する（ピン用）
  ///   - accessibilityLabel: VoiceOverで読み上げるマーカーの説明（棟名など）
  init(rootView: AnyView, anchorToBottom: Bool, accessibilityLabel: String) {
    hostingController = UIHostingController(rootView: rootView)
    super.init(reuseIdentifier: nil)

    hostingController.view.backgroundColor = .clear
    hostingController.view.clipsToBounds = false
    clipsToBounds = false

    let size = hostingController.sizeThatFits(in: CGSize(width: 240, height: 240))
    frame = CGRect(origin: .zero, size: size)
    hostingController.view.frame = bounds
    addSubview(hostingController.view)

    // VoiceOver: 内部のSwiftUI要素を個別に読まず，このマーカー全体を1要素として読み上げる
    hostingController.view.accessibilityElementsHidden = true
    isAccessibilityElement = true
    self.accessibilityLabel = accessibilityLabel

    if anchorToBottom {
      centerOffset = CGVector(dx: 0, dy: -size.height / 2)
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    // Storyboardからの生成は想定しない
    fatalError("init(coder:) is not supported")
  }
}
