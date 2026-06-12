//
//  CampusMapView.swift
//  CIT-Campus-3D
//
//  3Dキャンパスマップ画面．
//  「次の授業」の講義棟を目的地として，現在地からの徒歩経路をpitch付き3D視点で描画する．
//

import MapKit
import SwiftUI
import UIKit

/// マップの表示スタイル（標準3D／衛星写真3D）
enum CampusMapStyle: String, CaseIterable, Identifiable {
  /// 標準マップ（Appleの3Dビルモデル）
  case standard
  /// 衛星写真＋ラベル（実際の建物の見た目に近い）
  case hybrid

  var id: String { rawValue }

  /// 切り替えボタンの表示名
  var displayName: String {
    switch self {
    case .standard: return "標準"
    case .hybrid: return "衛星"
    }
  }

  /// MapKitへ渡すスタイル
  var mapStyle: MapStyle {
    switch self {
    case .standard:
      return .standard(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
    case .hybrid:
      return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll, showsTraffic: false)
    }
  }
}

/// 3Dマップとナビゲーション状態を統合した画面
struct CampusMapView: View {

  /// 経路線の描画スタイルに関する定数
  private enum RouteStyleConstants {
    /// 経路線の太さ
    static let lineWidth: CGFloat = 6
  }

  /// 目的地の講義棟（次の授業の講義棟．不明な場合はnil）
  private let destinationBuilding: CampusBuilding?

  /// 次の授業の判定結果（登録授業がない場合はnil）
  private let nextLecture: NextLectureResult?

  /// 現在地サービス（画面の生存期間と同じライフサイクル）
  @State private var locationService = LocationService()

  /// マップ状態のViewModel
  @State private var viewModel: CampusMapViewModel

  /// 選択中のマップスタイル（次回起動時も保持する）
  @AppStorage("campusMapStyle") private var mapStyleRawValue = CampusMapStyle.standard.rawValue

  /// 選択中のマップスタイル（enumとしてのアクセサ）
  private var selectedMapStyle: CampusMapStyle {
    CampusMapStyle(rawValue: mapStyleRawValue) ?? .standard
  }

  init(destinationBuilding: CampusBuilding?, nextLecture: NextLectureResult?) {
    self.destinationBuilding = destinationBuilding
    self.nextLecture = nextLecture
    _viewModel = State(initialValue: CampusMapViewModel(destinationBuilding: destinationBuilding))
  }

  var body: some View {
    ZStack(alignment: .top) {
      campusMap
      statusOverlay
        .padding(.horizontal)
        .padding(.top, 8)
    }
    .overlay(alignment: .bottomLeading) {
      mapStylePicker
        .padding(.leading)
        .padding(.bottom, 8)
    }
    .onAppear {
      locationService.startUpdating()
    }
    .onDisappear {
      locationService.stopUpdating()
    }
    .onChange(of: locationService.currentLocation) { _, newLocation in
      // 現在地が確定したタイミングで経路探索を自動開始する
      Task {
        await viewModel.handleLocationUpdate(newLocation)
      }
    }
    .onChange(of: destinationBuilding?.id) { _, _ in
      // 「次の授業」が変わったら目的地と経路を更新する
      Task {
        await viewModel.updateDestination(
          destinationBuilding,
          currentLocation: locationService.currentLocation
        )
      }
    }
    .preferredColorScheme(.dark)
  }

  // MARK: - マップ本体

  private var campusMap: some View {
    Map(position: $viewModel.cameraPosition) {
      // 現在地（青い点）
      UserAnnotation()

      // すべての講義棟の常設マーカー（目的地はパルスピンで別表示するため除外）
      ForEach(CampusBuilding.tsudanumaBuildings) { building in
        if building.id != viewModel.destinationBuilding?.id {
          Annotation(building.displayName, coordinate: building.coordinate, anchor: .center) {
            BuildingMarkerView(building: building)
          }
        }
      }

      // 目的の講義棟のハイライトピン
      if let building = viewModel.destinationBuilding {
        Annotation(building.displayName, coordinate: building.coordinate, anchor: .bottom) {
          DestinationMarkerView()
        }
      }

      // 徒歩経路のポリライン
      if let route = viewModel.route {
        MapPolyline(route.polyline)
          .stroke(
            LinearGradient(
              colors: [.cyan, .blue],
              startPoint: .leading,
              endPoint: .trailing
            ),
            style: StrokeStyle(
              lineWidth: RouteStyleConstants.lineWidth,
              lineCap: .round,
              lineJoin: .round
            )
          )
      }
    }
    // realistic指定で3D表示（建物・地形の立体表示）を有効化．
    // POI（飲食店等のアイコン）は除外し，没入感のあるミニマルな画面にする．
    .mapStyle(selectedMapStyle.mapStyle)
    .mapControls {
      MapUserLocationButton()
      MapCompass()
      MapPitchToggle()
      MapScaleView()
    }
    .ignoresSafeArea(edges: .bottom)
  }

  // MARK: - マップスタイル切り替え

  /// 標準3D／衛星3Dの切り替えコントロール
  private var mapStylePicker: some View {
    HStack(spacing: 0) {
      ForEach(CampusMapStyle.allCases) { style in
        Button {
          mapStyleRawValue = style.rawValue
        } label: {
          Text(style.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
              selectedMapStyle == style ? Color.cyan.opacity(0.3) : Color.clear,
              in: Capsule()
            )
            .foregroundStyle(selectedMapStyle == style ? .cyan : .secondary)
        }
      }
    }
    .padding(4)
    .background(.ultraThinMaterial, in: Capsule())
    .environment(\.colorScheme, .dark)
  }

  // MARK: - 状態オーバーレイ（信頼性の担保）

  /// 次の授業カード・位置情報・経路探索の状態に応じたバナー群
  @ViewBuilder
  private var statusOverlay: some View {
    VStack(spacing: 10) {
      nextLectureBanner
      locationStateBanner
      navigationStateBanner
    }
  }

  /// 次の授業の情報カード（未登録時は案内バナー）
  @ViewBuilder
  private var nextLectureBanner: some View {
    if let nextLecture {
      NextLectureCard(result: nextLecture)
      if destinationBuilding == nil {
        StatusBanner(
          systemImageName: "mappin.slash",
          message: "この授業は講義棟が未登録のため，経路を表示できません．",
          accentColor: .orange
        )
      }
    } else {
      StatusBanner(
        systemImageName: "calendar.badge.exclamationmark",
        message: "今後1週間の授業が見つかりません．時間割タブからインポートまたは追加してください．",
        accentColor: .cyan
      )
    }
  }

  /// 位置情報の取得状態に応じたバナー
  @ViewBuilder
  private var locationStateBanner: some View {
    switch locationService.fetchState {
    case .denied:
      StatusBanner(
        systemImageName: "location.slash.fill",
        message: "位置情報の利用が許可されていません．設定アプリから許可してください．",
        accentColor: .orange,
        actionTitle: "設定を開く",
        action: openAppSettings
      )
    case .restricted:
      StatusBanner(
        systemImageName: "exclamationmark.lock.fill",
        message: "この端末では位置情報の利用が制限されています．",
        accentColor: .orange
      )
    case .failed(let reason):
      StatusBanner(
        systemImageName: "antenna.radiowaves.left.and.right.slash",
        message: "現在地を取得できませんでした（\(reason)）",
        accentColor: .orange,
        actionTitle: "再試行",
        action: { locationService.startUpdating() }
      )
    case .locating:
      ProgressBanner(message: "現在地を取得しています…")
    case .idle, .available:
      EmptyView()
    }
  }

  /// 経路探索の進行状態に応じたバナー
  @ViewBuilder
  private var navigationStateBanner: some View {
    switch viewModel.phase {
    case .calculatingRoute:
      ProgressBanner(message: "経路を探索しています…")
    case .failed(let message):
      StatusBanner(
        systemImageName: "arrow.triangle.2.circlepath",
        message: message,
        accentColor: .orange,
        actionTitle: "再試行",
        action: {
          Task {
            await viewModel.retryRoute(from: locationService.currentLocation)
          }
        }
      )
    case .showingRoute:
      if let route = viewModel.route, let building = viewModel.destinationBuilding {
        RouteSummaryCard(destinationName: building.name, route: route)
      }
    case .waitingForLocation:
      ProgressBanner(message: "現在地の確定を待っています…")
    case .idle:
      EmptyView()
    }
  }

  // MARK: - Private

  /// 本アプリの設定画面（位置情報許可）を開く
  private func openAppSettings() {
    guard
      let settingsUrl = URL(string: UIApplication.openSettingsURLString),
      UIApplication.shared.canOpenURL(settingsUrl)
    else {
      return
    }
    UIApplication.shared.open(settingsUrl)
  }
}

#Preview {
  CampusMapView(destinationBuilding: .building2, nextLecture: nil)
}
