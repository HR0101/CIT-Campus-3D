//
//  TTTimetableWidget.swift
//  CITWidget
//
//  ホーム画面ウィジェット（小・中・大）の構成．
//

import SwiftUI
import WidgetKit

/// ホーム画面の時間割ウィジェット
struct TimetableWidget: Widget {
  let kind = "TimetableWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TTTimetableProvider()) { entry in
      TimetableWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("時間割")
    .description("今日の授業や週間時間割を表示します．")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
