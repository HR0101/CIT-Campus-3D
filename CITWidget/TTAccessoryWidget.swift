//
//  TTAccessoryWidget.swift
//  CITWidget
//
//  ロック画面・Apple Watch文字盤向けのアクセサリウィジェット．
//  次の授業（今日の未終了の先頭，無ければ曜日をまたいだ次の授業）を1行〜数行で表示する．
//

import SwiftUI
import WidgetKit

/// ロック画面アクセサリ「次の授業」ウィジェット
struct NextClassAccessoryWidget: Widget {
  let kind = "NextClassAccessoryWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: TTTimetableProvider()) { entry in
      NextClassAccessoryView(entry: entry)
    }
    .configurationDisplayName("次の授業")
    .description("ロック画面に次の授業を表示します．")
    .supportedFamilies([.accessoryInline, .accessoryRectangular, .accessoryCircular])
  }
}

/// アクセサリの表示（ファミリで切り替える）
struct NextClassAccessoryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TimetableEntry

  /// 注目する授業（今日の未終了の先頭，無ければ次の授業）
  private var focus: WidgetLectureItem? {
    entry.todayItems.first { $0.endDate > entry.date } ?? entry.nextUp
  }

  var body: some View {
    switch family {
    case .accessoryInline:
      inlineView
    case .accessoryCircular:
      circularView
    case .accessoryRectangular:
      rectangularView
    default:
      rectangularView
    }
  }

  /// 1行表示（ロック画面の時計上など）
  @ViewBuilder
  private var inlineView: some View {
    if let focus {
      Label("\(focus.periodText) \(focus.subjectName)", systemImage: "book.closed")
    } else {
      Label("授業はありません", systemImage: "book.closed")
    }
  }

  /// 円形表示（次の授業の時限を中央に）
  @ViewBuilder
  private var circularView: some View {
    ZStack {
      AccessoryWidgetBackground()
      if let focus {
        VStack(spacing: 0) {
          Image(systemName: "book.closed")
            .font(.system(size: 11))
          Text("\(focus.startPeriod)限")
            .font(.system(size: 13, weight: .bold))
        }
      } else {
        Image(systemName: "checkmark")
          .font(.system(size: 16, weight: .bold))
      }
    }
  }

  /// 長方形表示（次の授業の時限・科目・場所）
  @ViewBuilder
  private var rectangularView: some View {
    VStack(alignment: .leading, spacing: 1) {
      if let focus {
        HStack(spacing: 3) {
          Image(systemName: "clock")
          Text("\(focus.dayLabel) \(focus.periodText)・\(focus.timeRangeText)")
        }
        .font(.caption2)
        .widgetAccentable()
        Text(focus.subjectName)
          .font(.headline)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Text(focus.shortPlace)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      } else {
        Text("次の授業")
          .font(.caption2)
          .widgetAccentable()
        Text(entry.statusMessage ?? "本日は終了")
          .font(.subheadline)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }
}
