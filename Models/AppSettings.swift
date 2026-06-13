//
//  AppSettings.swift
//  CIT-Campus-3D
//
//  アプリ全体の設定（経路表示の制限・通知のオンオフなど）．
//  UserDefaultsへ永続化し，変更は@Observableを通じて各画面へ即時反映する．
//

import Foundation
import Observation

/// ユーザー設定（経路表示・通知）
@MainActor
@Observable
final class AppSettings {

  /// UserDefaultsのキー
  private enum Keys {
    static let restrictRouteToCampus = "settings.restrictRouteToCampus"
    static let enableClassReminder = "settings.enableClassReminder"
    static let classReminderOffsetMinutes = "settings.classReminderOffsetMinutes"
    static let enableDepartureReminder = "settings.enableDepartureReminder"
    static let departureBufferMinutes = "settings.departureBufferMinutes"
  }

  /// 設定の初期値
  private enum DefaultValues {
    /// 既定で「大学周辺でのみ経路を表示」する（要件: 範囲外では経路を出さない）
    static let restrictRouteToCampus = true
    /// 既定で授業前リマインダーをオンにする
    static let enableClassReminder = true
    /// 授業の何分前に通知するか
    static let classReminderOffsetMinutes = 15
    /// 既定で出発リマインダーをオンにする
    static let enableDepartureReminder = true
    /// 出発時刻に上乗せする余裕時間（分）
    static let departureBufferMinutes = 5
  }

  /// 授業前リマインダーの選択肢（分）
  static let reminderOffsetOptions = [5, 10, 15, 20, 30]
  /// 出発リマインダーの余裕時間の選択肢（分）
  static let departureBufferOptions = [0, 5, 10, 15]

  private let store: UserDefaults

  /// 大学周辺にいるときだけ経路を表示する
  var restrictRouteToCampus: Bool {
    didSet { store.set(restrictRouteToCampus, forKey: Keys.restrictRouteToCampus) }
  }

  /// 授業前リマインダーを有効にする
  var enableClassReminder: Bool {
    didSet { store.set(enableClassReminder, forKey: Keys.enableClassReminder) }
  }

  /// 授業の何分前に通知するか
  var classReminderOffsetMinutes: Int {
    didSet { store.set(classReminderOffsetMinutes, forKey: Keys.classReminderOffsetMinutes) }
  }

  /// 出発リマインダー（徒歩時間を逆算した出発時刻の通知）を有効にする
  var enableDepartureReminder: Bool {
    didSet { store.set(enableDepartureReminder, forKey: Keys.enableDepartureReminder) }
  }

  /// 出発時刻に上乗せする余裕時間（分）
  var departureBufferMinutes: Int {
    didSet { store.set(departureBufferMinutes, forKey: Keys.departureBufferMinutes) }
  }

  init(userDefaults: UserDefaults = .standard) {
    self.store = userDefaults
    // 既定値を登録してから読み出す（初回起動時も意図した既定値になる）
    userDefaults.register(defaults: [
      Keys.restrictRouteToCampus: DefaultValues.restrictRouteToCampus,
      Keys.enableClassReminder: DefaultValues.enableClassReminder,
      Keys.classReminderOffsetMinutes: DefaultValues.classReminderOffsetMinutes,
      Keys.enableDepartureReminder: DefaultValues.enableDepartureReminder,
      Keys.departureBufferMinutes: DefaultValues.departureBufferMinutes,
    ])
    // init内の代入ではdidSetは呼ばれないため，二重書き込みは発生しない
    self.restrictRouteToCampus = userDefaults.bool(forKey: Keys.restrictRouteToCampus)
    self.enableClassReminder = userDefaults.bool(forKey: Keys.enableClassReminder)
    self.classReminderOffsetMinutes = userDefaults.integer(forKey: Keys.classReminderOffsetMinutes)
    self.enableDepartureReminder = userDefaults.bool(forKey: Keys.enableDepartureReminder)
    self.departureBufferMinutes = userDefaults.integer(forKey: Keys.departureBufferMinutes)
  }
}
