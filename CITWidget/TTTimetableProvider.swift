//
//  TTTimetableProvider.swift
//  CITWidget
//
//  ウィジェットのタイムラインを供給するプロバイダ．
//  共有ストアから時間割を読み，毎正時にエントリを更新する（policyは.atEndで尽きたら再読込）．
//

import WidgetKit

/// 時間割ウィジェットのタイムラインプロバイダ
struct TTTimetableProvider: TimelineProvider {

  /// プレースホルダ（初回描画・ギャラリーの枠）
  func placeholder(in context: Context) -> TimetableEntry {
    .sample
  }

  /// スナップショット（ギャラリーのプレビュー）
  func getSnapshot(in context: Context, completion: @escaping (TimetableEntry) -> Void) {
    // ギャラリー表示時は素早く見せるためサンプルを使い，実利用時は実データを読む
    if context.isPreview {
      completion(.sample)
    } else {
      completion(TTTimetableLoader.singleEntry(at: Date()))
    }
  }

  /// タイムライン（実データ＋更新スケジュール）
  func getTimeline(in context: Context, completion: @escaping (Timeline<TimetableEntry>) -> Void) {
    let entries = TTTimetableLoader.timelineEntries(now: Date())
    // エントリを使い切ったら再読込する（時間割変更時はアプリ側からreloadAllTimelinesも呼ばれる）
    completion(Timeline(entries: entries, policy: .atEnd))
  }
}
