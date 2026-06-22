//
//  CampusMapView.swift
//  CIT-Campus-3D
//
//  3Dキャンパスマップ画面（MapLibre＋OSMベース）．
//  「次の授業」の講義棟を既定の目的地とし，現在地からの徒歩経路をpitch付き3D視点で描画する．
//  左上のボタンで次の授業パネルを開閉でき，場所一覧から任意の場所を目的地に選べる．
//

import CoreLocation
import SwiftUI
import UIKit

/// 3Dマップとナビゲーション状態を統合した画面
struct CampusMapView: View {

  /// 現在地サービス（ContentViewが所有し，注入する）
  let locationService: LocationService

  /// 次の授業の講義棟（自動で決まる既定の目的地．不明な場合はnil）
  let destinationBuilding: CampusBuilding?

  /// 次の授業の判定結果（登録授業がない場合はnil）
  let nextLecture: NextLectureResult?

  /// 次の授業が無いときに表示するメッセージ（学年暦を考慮済み）
  let emptyStateMessage: String

  /// 本日が休講日のときの注意文（無ければnil）
  let todayClosureNote: String?

  /// ユーザー設定（経路表示の制限）
  @Environment(AppSettings.self) private var settings

  /// 実効カラースキーム（アプリ外観設定に追従．マップのライト/ダーク描画に渡す）
  @Environment(\.colorScheme) private var colorScheme

  /// マップ状態のViewModel
  @State private var viewModel: CampusMapViewModel

  /// 次の授業パネルを開いているか
  @State private var isInfoExpanded = true

  /// 手動で選んだ目的地（nilなら次の授業を目的地にする）
  @State private var manualDestination: CampusBuilding?

  /// 場所一覧シートの表示フラグ
  @State private var isPlacePickerPresented = false

  /// 到着案内（VoiceOver）を一度だけ読み上げるためのフラグ（目的地が変わるとリセット）
  @State private var didAnnounceArrival = false

  /// 到着とみなす目的地までの距離（メートル）
  private let arrivalThresholdMeters: CLLocationDistance = 40

  init(
    locationService: LocationService,
    destinationBuilding: CampusBuilding?,
    nextLecture: NextLectureResult?,
    emptyStateMessage: String,
    todayClosureNote: String?
  ) {
    self.locationService = locationService
    self.destinationBuilding = destinationBuilding
    self.nextLecture = nextLecture
    self.emptyStateMessage = emptyStateMessage
    self.todayClosureNote = todayClosureNote
    _viewModel = State(initialValue: CampusMapViewModel(destinationBuilding: destinationBuilding))
  }

  /// 実際の目的地（手動選択があればそれを優先，無ければ次の授業）
  private var effectiveDestination: CampusBuilding? {
    manualDestination ?? destinationBuilding
  }

  /// 手動で目的地を選んでいるか
  private var isManualDestination: Bool {
    manualDestination != nil
  }

  /// 次の授業の教室階までの昇降時間（秒）．手動目的地・階数不明の場合は0
  private var destinationFloorSeconds: TimeInterval {
    guard !isManualDestination else { return 0 }
    return nextLecture?.lecture.floorClimbSeconds ?? 0
  }

  /// 次の授業の教室の階数表示（例: 3階）．手動目的地・1階・不明の場合はnil
  private var destinationFloorNote: String? {
    guard !isManualDestination, let floor = nextLecture?.lecture.floor, floor > 1 else {
      return nil
    }
    return "\(floor)階"
  }

  /// 現在地から目的地までの直線距離（どちらか無ければnil）
  private var distanceToDestination: CLLocationDistance? {
    guard
      let location = locationService.currentLocation,
      let building = viewModel.destinationBuilding
    else {
      return nil
    }
    return location.distance(
      from: CLLocation(latitude: building.latitude, longitude: building.longitude)
    )
  }

  /// 目的地に到着したか（しきい値以内）
  private var hasArrivedAtDestination: Bool {
    guard let distance = distanceToDestination else { return false }
    return distance <= arrivalThresholdMeters
  }

  /// 大学WiFiで在校と判定でき，かつ次の授業が進行中（＝その授業を受講中）か．
  /// 手動目的地のときは対象外．在校時はその授業の棟にいるとみなして受講中を表示する
  private var isAttendingOngoingClass: Bool {
    guard
      !isManualDestination,
      let next = nextLecture,
      next.isOngoing,
      let building = next.lecture.building
    else {
      return false
    }
    return locationService.isOnCampus(of: building.campus)
  }

  var body: some View {
    ZStack(alignment: .topLeading) {
      MapLibreMapView(
        destinationBuilding: viewModel.destinationBuilding,
        route: viewModel.route,
        cameraCommand: viewModel.cameraCommand,
        colorScheme: colorScheme
      )
      .ignoresSafeArea()

      topPanel
        .padding(.horizontal)
        .padding(.top, 8)
    }
    .overlay(alignment: .bottomTrailing) {
      controlButtons
        .padding(.trailing)
        .padding(.bottom, 56)
    }
    .overlay(alignment: .bottomLeading) {
      // OpenStreetMapデータの帰属表示（ODbL上，地図に常時表示が必要）
      mapAttribution
        .padding(.leading, 10)
        .padding(.bottom, 56)
    }
    .sheet(isPresented: $isPlacePickerPresented) {
      PlacePickerView(currentLocation: locationService.currentLocation) { place in
        manualDestination = place
      }
    }
    .task {
      // 初回表示時に現在状態で経路表示を評価する
      await refreshRoute()
    }
    .onAppear {
      // 現在地はマップ表示中のみ取得する（時間割・設定タブではGPSを止め電池を節約）
      locationService.startUpdating()
    }
    .onDisappear {
      locationService.stopUpdating()
    }
    .onChange(of: locationService.currentLocation) { _, _ in
      // 現在地が更新されるたびに経路表示（と大学周辺判定）を更新する
      Task { await refreshRoute() }
    }
    .onChange(of: destinationBuilding?.id) { _, _ in
      // 「次の授業」が変わったら反映する（ただし手動選択中は上書きしない）
      guard manualDestination == nil else { return }
      viewModel.setDestination(destinationBuilding)
      Task { await refreshRoute() }
    }
    .onChange(of: manualDestination?.id) { _, _ in
      // 手動で目的地を選んだ（または解除した）ときに反映する
      viewModel.setDestination(effectiveDestination)
      if let place = manualDestination, locationService.currentLocation == nil {
        // 現在地が未取得で経路が出せない場合でも，選んだ場所へカメラを寄せる
        viewModel.focusOnBuilding(place)
      }
      Task { await refreshRoute() }
    }
    .onChange(of: settings.restrictRouteToCampus) { _, _ in
      Task { await refreshRoute() }
    }
    .onChange(of: hasArrivedAtDestination) { _, arrived in
      // 到着した瞬間に一度だけVoiceOverで読み上げる
      guard arrived, !didAnnounceArrival, let building = viewModel.destinationBuilding else {
        return
      }
      didAnnounceArrival = true
      UIAccessibility.post(
        notification: .announcement,
        argument: "\(building.displayName) に到着しました"
      )
    }
    .onChange(of: viewModel.destinationBuilding?.id) { _, _ in
      // 目的地が変わったら到着案内をリセットする
      didAnnounceArrival = false
    }
  }

  /// 現在の目的地・設定で経路表示を更新する．
  /// 手動選択時は大学周辺の制限を無視し，どこからでも経路を出す．
  private func refreshRoute() async {
    await viewModel.refreshRoute(
      currentLocation: locationService.currentLocation,
      restrictToCampus: isManualDestination ? false : settings.restrictRouteToCampus
    )
  }

  // MARK: - 左上パネル（次の授業／目的地）

  /// 左上の開閉ボタンと情報パネル
  private var topPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      infoToggleButton
      if isInfoExpanded {
        infoContent
      }
    }
  }

  /// 次の授業パネルの開閉ボタン
  private var infoToggleButton: some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        isInfoExpanded.toggle()
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: isManualDestination ? "mappin.and.ellipse" : "graduationcap.fill")
        Text(isManualDestination ? "目的地" : "次の授業")
        Image(systemName: isInfoExpanded ? "chevron.up" : "chevron.down")
          .font(.caption2)
      }
      .font(.subheadline.bold())
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(.ultraThinMaterial, in: Capsule())
      .foregroundStyle(.cyan)
    }
    .accessibilityLabel(isInfoExpanded ? "情報を隠す" : "情報を表示")
  }

  /// 展開時に表示する情報（目的地カード・状態バナー）
  @ViewBuilder
  private var infoContent: some View {
    if isManualDestination {
      manualDestinationCard
    } else {
      nextLectureBanner
    }
    locationStateBanner
    navigationStateBanner
  }

  /// 手動選択中の目的地カード（「次の授業に戻る」ボタンつき）
  @ViewBuilder
  private var manualDestinationCard: some View {
    if let place = manualDestination {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(place.campus.displayName)キャンパス")
              .font(.caption)
              .foregroundStyle(.secondary)
            Text(place.displayName)
              .font(.headline)
              .foregroundStyle(.primary)
          }
          Spacer()
        }
        Button {
          manualDestination = nil
        } label: {
          Label("次の授業に戻る", systemImage: "arrow.uturn.backward")
            .font(.caption.bold())
            .foregroundStyle(.cyan)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
  }

  // MARK: - 右下のボタン

  /// 場所一覧ボタンと現在地ボタン
  private var controlButtons: some View {
    VStack(spacing: 12) {
      placeListButton
      focusUserButton
    }
  }

  /// 場所一覧を開くボタン
  private var placeListButton: some View {
    Button {
      isPlacePickerPresented = true
    } label: {
      Image(systemName: "list.bullet")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.cyan)
        .frame(width: 44, height: 44)
        .background(.ultraThinMaterial, in: Circle())
    }
    .accessibilityLabel("場所一覧")
  }

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
    }
    .accessibilityLabel("現在地へ移動")
  }

  // MARK: - 地図データの帰属表示

  /// OpenStreetMapの帰属表示（タップで著作権ページを開く）
  private var mapAttribution: some View {
    Button {
      UIApplication.shared.open(AppMetadata.openStreetMapCopyrightURL)
    } label: {
      Text("© OpenStreetMap contributors")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
    }
    .accessibilityLabel("地図データの著作権: OpenStreetMap contributors．タップで著作権ページを開きます")
  }

  // MARK: - 状態バナー（信頼性の担保）

  /// 次の授業の情報カード（未登録・休講・期間外は案内バナー）
  @ViewBuilder
  private var nextLectureBanner: some View {
    // 本日が休講日のときは，次の授業の有無にかかわらず注意文を出す
    if let todayClosureNote {
      StatusBanner(
        systemImageName: "calendar.badge.minus",
        message: todayClosureNote,
        accentColor: .cyan
      )
    }

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
        message: emptyStateMessage,
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
      // 「おおよその位置情報」（低精度）許可時は正確な経路が出せないため案内する
      if locationService.isReducedAccuracy {
        StatusBanner(
          systemImageName: "location.circle",
          message: "おおよその位置情報のため，正確な経路を表示できません．設定で「正確な位置情報」をオンにしてください．",
          accentColor: .orange,
          actionTitle: "設定を開く",
          action: openAppSettings
        )
      } else {
        EmptyView()
      }
    }
  }

  /// ナビゲーション状態のバナー．
  /// 大学WiFiで在校＋授業の時間帯のときは「受講中」を最優先で表示し，経路案内は出さない
  @ViewBuilder
  private var navigationStateBanner: some View {
    if isAttendingOngoingClass, let lecture = nextLecture?.lecture {
      StatusBanner(
        systemImageName: "studentdesk",
        message: "受講中：\(lecture.subjectName)（\(lecture.placeText)）",
        accentColor: .green
      )
    } else {
      routePhaseBanner
    }
  }

  /// 経路探索の進行状態に応じたバナー
  @ViewBuilder
  private var routePhaseBanner: some View {
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
            await viewModel.retryRoute(
              currentLocation: locationService.currentLocation,
              restrictToCampus: isManualDestination ? false : settings.restrictRouteToCampus
            )
          }
        }
      )
    case .showingRoute:
      if hasArrivedAtDestination, let building = viewModel.destinationBuilding {
        StatusBanner(
          systemImageName: "checkmark.circle.fill",
          message: "\(building.displayName) に到着しました",
          accentColor: .green
        )
      } else if let route = viewModel.route, let building = viewModel.destinationBuilding {
        RouteSummaryCard(
          destinationName: building.displayName,
          route: route,
          extraSeconds: destinationFloorSeconds,
          floorNote: destinationFloorNote
        )
      }
    case .outsideCampus:
      outsideCampusBanner
    case .waitingForLocation:
      ProgressBanner(message: "現在地の確定を待っています…")
    case .idle:
      EmptyView()
    }
  }

  /// 大学の周辺ではないことを伝えるバナー（距離も表示する）
  @ViewBuilder
  private var outsideCampusBanner: some View {
    let message: String = {
      guard
        let building = viewModel.destinationBuilding,
        let location = locationService.currentLocation
      else {
        return "大学の周辺に入ると経路を表示します．"
      }
      let distanceKm = building.campus.distanceMeters(from: location.coordinate) / 1_000
      return String(
        format: "%@キャンパスまで約%.1fkm．周辺に入ると経路を表示します．",
        building.campus.displayName, distanceKm
      )
    }()
    StatusBanner(
      systemImageName: "figure.walk.circle",
      message: message,
      accentColor: .cyan
    )
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
  CampusMapView(
    locationService: LocationService(),
    destinationBuilding: .building2,
    nextLecture: nil,
    emptyStateMessage: "時間割が未登録です．",
    todayClosureNote: nil
  )
  .environment(AppSettings())
}
