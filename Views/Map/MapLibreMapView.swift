//
//  MapLibreMapView.swift
//  CIT-Campus-3D
//
//  MapLibre（OpenFreeMapの無料OSMタイル）による3Dキャンパスマップ．
//  構成は3層:
//    1. ベース地図: OpenFreeMapのdarkスタイル（OSMベクタータイル）
//    2. 周辺市街の3Dビル: タイルのbuildingレイヤをfill-extrusionで押し出し
//    3. キャンパス8棟: OSM実測の外形ポリゴン（同梱GeoJSON）＋自前の高さデータで
//       周辺よりも高忠実な3D表示にする
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
    static let styleURL = URL(string: "https://tiles.openfreemap.org/styles/dark")
    /// タイル側ベクターソースのID（OpenFreeMapのスタイル定義に合わせる）
    static let vectorSourceID = "openmaptiles"
    /// タイル側のビルレイヤ名（OpenMapTilesスキーマ）
    static let buildingSourceLayer = "building"
    /// 周辺市街の3DビルレイヤのID
    static let cityBuildingsLayerID = "city-3d-buildings"
    /// キャンパス棟のGeoJSONソースのID
    static let campusSourceID = "campus-buildings-source"
    /// キャンパス棟の3DレイヤのID
    static let campusLayerID = "campus-3d-buildings"
    /// 経路ソースのID
    static let routeSourceID = "route-source"
    /// 経路レイヤのID
    static let routeLayerID = "route-layer"
    /// 同梱GeoJSONのファイル名
    static let campusGeoJSONName = "CampusBuildings"
    /// カメラ移動アニメーションの秒数
    static let cameraAnimationDuration: TimeInterval = 1.2
    /// 周辺市街ビルの色（ベース地図に馴染む暗いグレー）
    static let cityBuildingColor = UIColor(white: 0.30, alpha: 1.0)
    /// 周辺市街ビルの不透明度（透過すると視認性が落ちるため完全不透明にする）
    static let cityBuildingOpacity: Float = 1.0
    /// キャンパス棟の色（市街よりわずかに明るいグレーで控えめに区別する）
    static let campusBuildingColor = UIColor(white: 0.42, alpha: 1.0)
    /// キャンパス棟の不透明度（完全不透明）
    static let campusBuildingOpacity: Float = 1.0
    /// 経路線の色
    static let routeColor = UIColor.systemCyan
    /// 経路線の太さ
    static let routeWidth: CGFloat = 5.0
  }

  /// 目的地の講義棟（パルスピンの表示対象）
  let destinationBuilding: CampusBuilding?

  /// 描画する徒歩経路
  let route: MKRoute?

  /// カメラ移動指示
  let cameraCommand: CameraCommand?

  func makeUIView(context: Context) -> MLNMapView {
    let mapView = MLNMapView(frame: .zero, styleURL: MapConstants.styleURL)
    mapView.delegate = context.coordinator
    mapView.showsUserLocation = true
    context.coordinator.mapView = mapView

    // 初期カメラ（アニメーションなしで即適用）
    if let command = cameraCommand {
      mapView.setCamera(Coordinator.makeCamera(from: command), animated: false)
      context.coordinator.markCameraApplied(command)
    }

    context.coordinator.apply(
      destination: destinationBuilding,
      route: route,
      cameraCommand: cameraCommand
    )
    return mapView
  }

  func updateUIView(_ mapView: MLNMapView, context: Context) {
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

    /// スタイルの読み込みが完了したか
    private var isStyleLoaded = false

    /// 適用済みのカメラ指示ID（二重適用の防止）
    private var appliedCameraCommandID: UUID?

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

    /// カメラ指示を適用済みとして記録する（初期カメラ用）
    func markCameraApplied(_ command: CameraCommand) {
      appliedCameraCommandID = command.id
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
      addCityBuildingsLayer(to: style)
      addCampusBuildingsLayer(to: style)
      setupRouteLayer(in: style)

      // スタイル読み込み前に届いていた経路を反映する
      if let pendingRoute {
        self.pendingRoute = nil
        appliedRoute = nil
        applyRoute(pendingRoute)
      }
    }

    // MARK: - Private（レイヤ構築）

    /// 周辺市街の3Dビルレイヤ（タイルのbuildingレイヤを押し出し）を追加する
    private func addCityBuildingsLayer(to style: MLNStyle) {
      guard let source = style.source(withIdentifier: MapConstants.vectorSourceID) else {
        return
      }
      let layer = MLNFillExtrusionStyleLayer(
        identifier: MapConstants.cityBuildingsLayerID,
        source: source
      )
      layer.sourceLayerIdentifier = MapConstants.buildingSourceLayer
      layer.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
      layer.fillExtrusionBase = NSExpression(forKeyPath: "render_min_height")
      layer.fillExtrusionColor = NSExpression(forConstantValue: MapConstants.cityBuildingColor)
      layer.fillExtrusionOpacity = NSExpression(
        forConstantValue: MapConstants.cityBuildingOpacity
      )

      // ラベル（シンボルレイヤ）の下に挿入して地名の視認性を保つ
      if let firstSymbolLayer = style.layers.first(where: { $0 is MLNSymbolStyleLayer }) {
        style.insertLayer(layer, below: firstSymbolLayer)
      } else {
        style.addLayer(layer)
      }
    }

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
      // なければマスタの高さ（heightMeters）を使う
      for case let polygon as MLNPolygonFeature in collection.shapes {
        let name = polygon.attribute(forKey: "name") as? String ?? ""
        let explicitHeight = polygon.attribute(forKey: "height") as? Double
        let height = explicitHeight
          ?? CampusBuilding.building(named: name)?.heightMeters
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

      let layer = MLNFillExtrusionStyleLayer(
        identifier: MapConstants.campusLayerID,
        source: source
      )
      layer.fillExtrusionHeight = NSExpression(forKeyPath: "height")
      layer.fillExtrusionBase = NSExpression(forConstantValue: 0)
      layer.fillExtrusionColor = NSExpression(forConstantValue: MapConstants.campusBuildingColor)
      layer.fillExtrusionOpacity = NSExpression(
        forConstantValue: MapConstants.campusBuildingOpacity
      )

      if let cityLayer = style.layer(withIdentifier: MapConstants.cityBuildingsLayerID) {
        style.insertLayer(layer, above: cityLayer)
      } else {
        style.addLayer(layer)
      }
    }

    /// 経路描画用のソースとレイヤを準備する
    private func setupRouteLayer(in style: MLNStyle) {
      let source = MLNShapeSource(identifier: MapConstants.routeSourceID, shape: nil, options: nil)
      style.addSource(source)
      routeSource = source

      let layer = MLNLineStyleLayer(identifier: MapConstants.routeLayerID, source: source)
      layer.lineColor = NSExpression(forConstantValue: MapConstants.routeColor)
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
      guard destination?.id != appliedDestinationID || !hasAddedAnnotations else { return }
      appliedDestinationID = destination?.id
      hasAddedAnnotations = true

      mapView.removeAnnotations(buildingAnnotations)
      buildingAnnotations = CampusBuilding.tsudanumaBuildings.map { building in
        let annotation = CampusPointAnnotation()
        annotation.coordinate = building.coordinate
        annotation.building = building
        annotation.isDestination = building.id == destination?.id
        return annotation
      }
      mapView.addAnnotations(buildingAnnotations)
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
          anchorToBottom: true
        )
      }
      return HostedAnnotationView(
        rootView: AnyView(BuildingAnnotationView(building: building)),
        anchorToBottom: false
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
  init(rootView: AnyView, anchorToBottom: Bool) {
    hostingController = UIHostingController(rootView: rootView)
    super.init(reuseIdentifier: nil)

    hostingController.view.backgroundColor = .clear
    hostingController.view.clipsToBounds = false
    clipsToBounds = false

    let size = hostingController.sizeThatFits(in: CGSize(width: 240, height: 240))
    frame = CGRect(origin: .zero, size: size)
    hostingController.view.frame = bounds
    addSubview(hostingController.view)

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
