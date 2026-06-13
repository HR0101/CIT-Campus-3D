//
//  ContentView.swift
//  CIT-Campus-3D
//
//  ルートビュー．マップ・時間割・設定の3タブ構成．
//  毎分の再評価で「次の授業」を判定してマップへ反映し，
//  現在地・設定の変化に応じて通知（授業前／出発リマインダー）を予約し直す．
//

import CoreLocation
import MapKit
import SwiftData
import SwiftUI

struct ContentView: View {

  @Environment(\.scenePhase) private var scenePhase
  @Environment(AppSettings.self) private var settings
  @Environment(NotificationService.self) private var notifications

  /// 全登録授業
  @Query private var lectures: [Lecture]

  /// 現在地サービス（マップと通知の両方で使うためルートビューが所有する）
  @State private var locationService = LocationService()

  /// 次の授業の判定サービス
  private let resolver = NextLectureResolver()

  /// 出発リマインダー用の徒歩時間計算サービス
  private let routeService = RouteService()

  var body: some View {
    // 毎分再評価して「次の授業」の切り替わりを自動で反映する
    TimelineView(.everyMinute) { context in
      let upcoming = resolver.resolveUpcoming(from: lectures, now: context.date)
      let nextLecture = upcoming.first

      TabView {
        Tab("マップ", systemImage: "map.fill") {
          CampusMapView(
            locationService: locationService,
            destinationBuilding: nextLecture?.lecture.building,
            nextLecture: nextLecture
          )
        }
        Tab("時間割", systemImage: "calendar") {
          TimetableListView()
        }
        Tab("設定", systemImage: "gearshape") {
          SettingsView()
        }
      }
      // 授業・現在地・設定・許可状態のいずれかが変わったら通知を予約し直す
      .task(id: schedulingKey(upcoming: upcoming)) {
        await rescheduleNotifications(upcoming: upcoming)
      }
    }
    .onAppear {
      locationService.startUpdating()
    }
    .task {
      await prepareNotifications()
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // 復帰時に位置情報を再開し，通知許可状態を取り直す（設定アプリでの変更を反映）
        locationService.startUpdating()
        Task { await notifications.refreshAuthorizationStatus() }
      case .background:
        // バックグラウンドでは位置情報を止めてバッテリーを節約する
        locationService.stopUpdating()
      default:
        break
      }
    }
  }

  // MARK: - 通知の予約

  /// 起動時の通知準備（許可状態の取得と，必要なら許可リクエスト）
  private func prepareNotifications() async {
    await notifications.refreshAuthorizationStatus()
    let wantsNotification = settings.enableClassReminder || settings.enableDepartureReminder
    if wantsNotification && notifications.authorizationStatus == .notDetermined {
      await notifications.requestAuthorization()
    }
  }

  /// 直近の授業群に対して通知を予約し直す
  private func rescheduleNotifications(upcoming: [NextLectureResult]) async {
    guard !upcoming.isEmpty else {
      notifications.cancelAll()
      return
    }

    // 出発リマインダーが有効な場合のみ，現在地から次の講義棟までの徒歩時間を求める
    var travelTime: TimeInterval?
    if settings.enableDepartureReminder,
       let next = upcoming.first,
       let destination = next.lecture.building,
       let location = locationService.currentLocation {
      travelTime = try? await routeService
        .calculateWalkingRoute(from: location.coordinate, to: destination.coordinate)
        .expectedTravelTime
    }

    notifications.reschedule(
      upcoming: upcoming,
      departureTravelTime: travelTime,
      settings: settings
    )
  }

  /// 通知の再予約が必要かどうかを表すキー．
  /// 授業群・現在地（粗め）・各設定・許可状態のいずれかが変わると値が変化する．
  private func schedulingKey(upcoming: [NextLectureResult]) -> String {
    let lecturePart = upcoming
      .prefix(NotificationKeyConstants.maxLecturesInKey)
      .map { "\($0.lecture.subjectName)#\(Int($0.startDate.timeIntervalSince1970))" }
      .joined(separator: ",")

    // 現在地は約55m単位に丸めて，わずかな移動での再計算を防ぐ
    let locationPart: String
    if let coordinate = locationService.currentLocation?.coordinate {
      let step = NotificationKeyConstants.locationRoundStep
      let roundedLatitude = (coordinate.latitude * step).rounded() / step
      let roundedLongitude = (coordinate.longitude * step).rounded() / step
      locationPart = "\(roundedLatitude),\(roundedLongitude)"
    } else {
      locationPart = "noloc"
    }

    return [
      lecturePart,
      locationPart,
      "\(settings.enableClassReminder)",
      "\(settings.classReminderOffsetMinutes)",
      "\(settings.enableDepartureReminder)",
      "\(settings.departureBufferMinutes)",
      "\(notifications.authorizationStatus.rawValue)",
    ].joined(separator: "|")
  }

  /// 通知キーの定数
  private enum NotificationKeyConstants {
    /// キーに含める授業の最大件数
    static let maxLecturesInKey = 8
    /// 現在地の丸め単位（1/step度．2000なら約0.0005度＝約55m）
    static let locationRoundStep: Double = 2_000
  }
}

#Preview {
  ContentView()
    .modelContainer(for: Lecture.self, inMemory: true)
    .environment(AppSettings())
    .environment(NotificationService())
}
