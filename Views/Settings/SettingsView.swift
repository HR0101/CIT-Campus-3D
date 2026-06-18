//
//  SettingsView.swift
//  CIT-Campus-3D
//
//  経路表示・通知のオンオフを切り替える設定画面．
//

import SwiftUI
import UIKit

/// 設定画面（経路表示・通知）
struct SettingsView: View {

  @Environment(AppSettings.self) private var settings
  @Environment(NotificationService.self) private var notifications
  @Environment(PortalCredentialStore.self) private var portalStore

  var body: some View {
    // @Observableの設定をToggle/Pickerへバインドするための束縛
    @Bindable var settings = settings

    NavigationStack {
      Form {
        // 外観
        Section {
          Picker("外観", selection: $settings.appearance) {
            ForEach(AppearanceMode.allCases) { mode in
              Text(mode.displayName).tag(mode)
            }
          }
        } header: {
          Text("外観")
        } footer: {
          Text("画面の配色を切り替えます．「システムに合わせる」を選ぶと，端末（スマホ）のダーク／ライト設定に自動で従います．3Dマップ画面は見やすさのため常にダーク表示です．")
        }

        // スケジュール
        Section {
          NavigationLink {
            AcademicCalendarView()
          } label: {
            Label("\(AcademicCalendar.current.academicYear)年度 学年暦", systemImage: "calendar")
          }
        } header: {
          Text("スケジュール")
        } footer: {
          Text("登録済みの授業期間・休講日です．「次の授業」の判定はこの学年暦に従い，休講日や長期休業中は授業を表示しません．")
        }

        // ポータル連携（時間割の自動入力）
        Section {
          NavigationLink {
            PortalCredentialSetupView()
          } label: {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text("CITポータル連携")
                Text(portalStore.isRegistered ? "登録済み：\(portalStore.userID ?? "")" : "未登録")
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "key.horizontal")
            }
          }
        } header: {
          Text("ポータル連携")
        } footer: {
          Text("ユーザーID・パスワード・ワンタイムパスワードのキーを登録すると，ポータルから取り込む際にログイン情報を自動入力します．認証情報はこの端末内にのみ保存します．")
        }

        // 経路表示
        Section {
          Toggle("大学周辺でのみ経路を表示", isOn: $settings.restrictRouteToCampus)
        } header: {
          Text("経路表示")
        } footer: {
          Text("オンのとき，キャンパスから離れている間は徒歩ルートを表示しません．大学の近く（約\(Int(Campus.vicinityRadiusMeters))m以内）に入ると自動で表示されます．")
        }

        // 授業前リマインダー
        Section {
          Toggle("授業の前に通知", isOn: $settings.enableClassReminder)
          if settings.enableClassReminder {
            Picker("通知タイミング", selection: $settings.classReminderOffsetMinutes) {
              ForEach(AppSettings.reminderOffsetOptions, id: \.self) { minutes in
                Text("\(minutes)分前").tag(minutes)
              }
            }
          }
        } header: {
          Text("授業前リマインダー")
        } footer: {
          Text("次の授業の開始時刻の前に通知します．")
        }

        // 出発リマインダー
        Section {
          Toggle("出発時刻に通知", isOn: $settings.enableDepartureReminder)
          if settings.enableDepartureReminder {
            Picker("余裕時間", selection: $settings.departureBufferMinutes) {
              ForEach(AppSettings.departureBufferOptions, id: \.self) { minutes in
                Text(minutes == 0 ? "なし" : "\(minutes)分").tag(minutes)
              }
            }
          }
        } header: {
          Text("出発リマインダー")
        } footer: {
          Text("今いる場所から次の講義棟までの徒歩時間を逆算し，出発すべき時刻に通知します．余裕時間を足すと，その分だけ早めに通知します．")
        }

        // 通知が許可されていない場合の案内
        if isNotificationBlocked {
          Section {
            Button("通知を許可する") {
              openAppSettings()
            }
          } footer: {
            Text("通知がオフになっています．リマインダーを受け取るには，設定アプリから通知を許可してください．")
          }
        }
      }
      .navigationTitle("設定")
    }
    .task {
      await notifications.refreshAuthorizationStatus()
    }
    .onChange(of: settings.enableClassReminder) { _, isOn in
      if isOn {
        Task { await requestAuthorizationIfNeeded() }
      }
    }
    .onChange(of: settings.enableDepartureReminder) { _, isOn in
      if isOn {
        Task { await requestAuthorizationIfNeeded() }
      }
    }
  }

  // MARK: - Private

  /// いずれかの通知がオンなのに許可が拒否されている状態か
  private var isNotificationBlocked: Bool {
    let wantsNotification = settings.enableClassReminder || settings.enableDepartureReminder
    return wantsNotification && notifications.authorizationStatus == .denied
  }

  /// 通知が未許可なら許可をリクエストする
  private func requestAuthorizationIfNeeded() async {
    if notifications.authorizationStatus == .notDetermined {
      await notifications.requestAuthorization()
    } else {
      await notifications.refreshAuthorizationStatus()
    }
  }

  /// 本アプリの設定画面（通知許可）を開く
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
  SettingsView()
    .environment(AppSettings())
    .environment(NotificationService())
}
