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
  @Environment(\.modelContext) private var modelContext
  @Environment(AppSettings.self) private var settings
  @Environment(NotificationService.self) private var notifications
  @Environment(PortalCredentialStore.self) private var credentialStore
  @Environment(ManabaSyncService.self) private var manabaSync
  @Environment(PortalChangeSyncService.self) private var portalChangeSync

  /// 全登録授業
  @Query private var lectures: [Lecture]

  /// 取り込み済みの時間割変更（休講で「次の授業」を除外するために使う）
  @Query private var classChanges: [ClassChange]

  /// 現在地サービス（マップと通知の両方で使うためルートビューが所有する）
  @State private var locationService = LocationService()

  /// 次の授業の判定サービス
  private let resolver = NextLectureResolver()

  /// 出発リマインダー用の徒歩時間計算サービス
  private let routeService = RouteService()

  var body: some View {
    // 毎分再評価して「次の授業」の切り替わりを自動で反映する
    TimelineView(.everyMinute) { context in
      let resolved = resolver.resolveUpcoming(from: lectures, now: context.date)
      // 休講に該当する授業を「次の授業」から除外する
      let upcoming = resolver.removingCancellations(resolved, changes: classChanges)
      let nextLecture = upcoming.first
      let scheduleStatus = AcademicCalendar.current.scheduleStatus(
        on: context.date, calendar: .current
      )

      TabView {
        Tab("マップ", systemImage: "map.fill") {
          CampusMapView(
            locationService: locationService,
            destinationBuilding: nextLecture?.lecture.building,
            nextLecture: nextLecture,
            emptyStateMessage: emptyLectureMessage(status: scheduleStatus),
            todayClosureNote: todayClosureNote(status: scheduleStatus)
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
    .task {
      await prepareNotifications()
    }
    .task {
      // 起動時にCloudKit同期などで生じた重複（課題・時間割変更）を掃除する
      try? AssignmentImporter.deduplicate(into: modelContext)
      try? ClassChangeImporter.deduplicate(into: modelContext)
      // 起動時にmanaba課題をバックグラウンド同期する（資格情報があり，前回から時間が経っていれば）
      manabaSync.syncIfStale(
        credentialStore: credentialStore,
        modelContext: modelContext,
        settings: settings,
        notifications: notifications
      )
      // 起動時にポータルの休講・補講もバックグラウンド同期する（TOTP登録済みのときのみ）
      portalChangeSync.syncIfStale(
        credentialStore: credentialStore,
        modelContext: modelContext
      )
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // 復帰時に通知許可状態を取り直す（設定アプリでの変更を反映）．
        // 位置情報はマップタブのonAppearで開始するためここでは起動しない
        Task { await notifications.refreshAuthorizationStatus() }
        // 復帰時にも前回から十分時間が経っていれば課題を同期する
        manabaSync.syncIfStale(
          credentialStore: credentialStore,
          modelContext: modelContext,
          settings: settings,
          notifications: notifications
        )
      case .background:
        // バックグラウンドでは位置情報を止めてバッテリーを節約する
        locationService.stopUpdating()
      default:
        break
      }
    }
  }

  // MARK: - 学年暦に応じたメッセージ

  /// 次の授業が無いときに表示するメッセージ（学年暦の状態を考慮する）
  private func emptyLectureMessage(status: AcademicCalendar.ScheduleStatus) -> String {
    // 時間割そのものが未登録の場合はインポートを促す
    if lectures.isEmpty {
      return "時間割が未登録です．時間割タブからインポートまたは追加してください．"
    }
    switch status {
    case .breakUntil(let nextSemester, let startKey):
      let dateText = AcademicCalendar.monthDayText(fromKey: startKey)
      return "現在は授業期間外です．\(nextSemester.displayName)は\(dateText)から始まります．"
    case .afterAllTerms:
      return "本年度の授業はすべて終了しました．"
    case .closureDay(let reason):
      return "本日は休講です（\(reason)）．今週これからの授業はありません．"
    case .classDay, .unknownYear:
      return "今後1週間の授業が見つかりません．"
    }
  }

  /// 本日が休講日のときの注意文（授業実施日・期間外ならnil）
  private func todayClosureNote(status: AcademicCalendar.ScheduleStatus) -> String? {
    if case .closureDay(let reason) = status {
      return "本日は休講です（\(reason)）"
    }
    return nil
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

    // 出発リマインダーが有効な場合のみ，現在地から次の講義棟までの徒歩時間を求める．
    // 教室の階数分の昇降時間も加え，「教室に着く」までの時間で出発時刻を逆算する．
    var travelTime: TimeInterval?
    if settings.enableDepartureReminder,
       let next = upcoming.first,
       let destination = next.lecture.building,
       let location = locationService.currentLocation {
      if let walkingTime = try? await routeService
        .calculateWalkingRoute(from: location.coordinate, to: destination.coordinate)
        .expectedTravelTime {
        travelTime = walkingTime + next.lecture.floorClimbSeconds
      }
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
