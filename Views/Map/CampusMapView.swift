//
//  CampusMapView.swift
//  CIT-Campus-3D
//
//  3Dキャンパスマップ画面（MapLibre＋OSMベース）．
//  「次の授業」の講義棟を目的地として，現在地からの徒歩経路をpitch付き3D視点で描画する．
//  キャンパス8棟はOSM実測の外形＋自前の高さデータで高忠実に押し出し表示される．
//

import SwiftUI
import UIKit

/// 3Dマップとナビゲーション状態を統合した画面
struct CampusMapView: View {

  /// 目的地の講義棟（次の授業の講義棟．不明な場合はnil）
  private let destinationBuilding: CampusBuilding?

  /// 次の授業の判定結果（登録授業がない場合はnil）
  private let nextLecture: NextLectureResult?

  /// 現在地サービス（画面の生存期間と同じライフサイクル）
  @State private var locationService = LocationService()

  /// マップ状態のViewModel
  @State private var viewModel: CampusMapViewModel

  init(destinationBuilding: CampusBuilding?, nextLecture: NextLectureResult?) {
    self.destinationBuilding = destinationBuilding
    self.nextLecture = nextLecture
    _viewModel = State(initialValue: CampusMapViewModel(destinationBuilding: destinationBuilding))
  }

  var body: some View {
    ZStack(alignment: .top) {
      MapLibreMapView(
        destinationBuilding: viewModel.destinationBuilding,
        route: viewModel.route,
        cameraCommand: viewModel.cameraCommand
      )
      .ignoresSafeArea()

      statusOverlay
        .padding(.horizontal)
        .padding(.top, 8)
    }
    .overlay(alignment: .bottomTrailing) {
      focusUserButton
        .padding(.trailing)
        .padding(.bottom, 56)
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

  // MARK: - 現在地ボタン

  /// カメラを現在地へ移動するボタン
  private var focusUserButton: some View {
    Button {
      viewModel.focusOnUserLocation(locationService.currentLocation)
    } label: {
      Image(systemName: "location.fill")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.cyan)
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
        .environment(\.colorScheme, .dark)
    }
    .accessibilityLabel("現在地へ移動")
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
