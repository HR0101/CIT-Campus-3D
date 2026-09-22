//
//  TTTimetableWidgetViews.swift
//  CITWidget
//
//  ホーム画面ウィジェット（小・中・大）の表示．
//  小＝今日の現在／次の授業，中＝今日の時間割リスト，大＝週間グリッド．
//

import SwiftUI
import WidgetKit

/// 授業の時間的な状態（過去・進行中・これから）
private enum LectureTimeStatus {
  case past
  case ongoing
  case upcoming
}

/// 基準時刻に対する授業の状態を返す
private func timeStatus(of item: WidgetLectureItem, at now: Date) -> LectureTimeStatus {
  if item.endDate <= now { return .past }
  if item.startDate <= now { return .ongoing }
  return .upcoming
}

/// ウィジェットのアクセントカラー
private let widgetAccent = Color.cyan

// MARK: - ファミリ振り分け

/// ホーム画面ウィジェットの本体（サイズで表示を切り替える）
struct TimetableWidgetEntryView: View {
  @Environment(\.widgetFamily) private var family
  let entry: TimetableEntry

  var body: some View {
    switch family {
    case .systemSmall:
      SmallTodayView(entry: entry)
    case .systemMedium:
      MediumTodayView(entry: entry)
    case .systemLarge:
      LargeWeekGridView(entry: entry)
    default:
      SmallTodayView(entry: entry)
    }
  }
}

// MARK: - 小（今日の現在／次の授業）

/// 小サイズ: 今日の進行中または次の授業に絞って表示する
private struct SmallTodayView: View {
  let entry: TimetableEntry

  /// 注目する授業（今日の未終了の先頭，無ければ曜日をまたいだ次の授業）
  private var focus: WidgetLectureItem? {
    entry.todayItems.first { $0.endDate > entry.date } ?? entry.nextUp
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header

      if let focus {
        let ongoing = timeStatus(of: focus, at: entry.date) == .ongoing
        Spacer(minLength: 0)
        Text(ongoing ? "授業中" : (focus.isToday ? "次の授業" : "次回 \(focus.dayLabel)"))
          .font(.caption2.bold())
          .foregroundStyle(ongoing ? Color.orange : widgetAccent)
        Text(focus.subjectName)
          .font(.headline)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Label("\(focus.periodText)・\(focus.timeRangeText)", systemImage: "clock")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Label(focus.shortPlace, systemImage: "mappin.and.ellipse")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      } else {
        Spacer(minLength: 0)
        Text(entry.statusMessage ?? "本日の授業は終了しました")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(3)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { widgetBackground }
  }

  private var header: some View {
    HStack(spacing: 4) {
      Image(systemName: "calendar")
        .font(.caption2)
        .foregroundStyle(widgetAccent)
      Text(todayText(entry.date))
        .font(.caption2.bold())
      Spacer(minLength: 0)
    }
  }
}

// MARK: - 中（今日の時間割リスト）

/// 中サイズ: 今日の授業をリスト表示する（進行中をハイライト）
private struct MediumTodayView: View {
  let entry: TimetableEntry

  /// 表示する今日の授業（最大4ブロック）
  private var items: [WidgetLectureItem] {
    Array(entry.todayItems.prefix(4))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Label("今日の時間割", systemImage: "list.bullet.rectangle")
          .font(.caption.bold())
          .foregroundStyle(widgetAccent)
        Spacer()
        Text("\(todayText(entry.date))・\(entry.semesterName)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      if items.isEmpty {
        Spacer()
        Text(entry.statusMessage ?? "今日の授業はありません")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
        Spacer()
      } else {
        ForEach(items) { item in
          LectureRowView(item: item, now: entry.date)
        }
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { widgetBackground }
  }
}

/// 中サイズの授業1行（時限バッジ＋科目＋時間・場所）
private struct LectureRowView: View {
  let item: WidgetLectureItem
  let now: Date

  var body: some View {
    let status = timeStatus(of: item, at: now)
    HStack(spacing: 8) {
      Text(item.periodText)
        .font(.caption2.bold())
        .foregroundStyle(status == .ongoing ? Color.white : widgetAccent)
        .frame(width: 42, height: 22)
        .background(
          status == .ongoing ? Color.orange : widgetAccent.opacity(0.15),
          in: RoundedRectangle(cornerRadius: 6)
        )

      VStack(alignment: .leading, spacing: 1) {
        Text(item.subjectName)
          .font(.subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .strikethrough(status == .past, color: .secondary)
          .foregroundStyle(status == .past ? .secondary : .primary)
        Text("\(item.timeRangeText)・\(item.shortPlace)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      Spacer(minLength: 0)
    }
    .opacity(status == .past ? 0.55 : 1)
  }
}

// MARK: - 大（週間グリッド）

/// 大サイズ: 曜日×時限の週間グリッド（当日列をハイライト）
private struct LargeWeekGridView: View {
  let entry: TimetableEntry

  /// 曜日→時限→セルの索引
  private var lookup: [Weekday: [Int: WidgetGridCell]] {
    var result: [Weekday: [Int: WidgetGridCell]] = [:]
    for cell in entry.weekCells {
      result[cell.weekday, default: [:]][cell.period] = cell
    }
    return result
  }

  var body: some View {
    // 行数（ヘッダ＋時限数）でセル高さを決め，ウィジェットの高さ内に必ず収める（見切れ防止）
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Label("週間時間割", systemImage: "calendar")
          .font(.caption2.bold())
          .foregroundStyle(widgetAccent)
        Spacer()
        Text(entry.semesterName)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Grid(horizontalSpacing: 3, verticalSpacing: 3) {
        // ヘッダ行（曜日＋その週の日付）
        GridRow {
          Text("")
            .frame(width: 14)
          ForEach(Weekday.lectureDays) { weekday in
            VStack(spacing: 0) {
              Text(weekday.shortName)
                .font(.caption2.bold())
              if let date = gridDate(for: weekday, reference: entry.date) {
                Text(shortDateLabel(date))
                  .font(.system(size: 8))
                  .lineLimit(1)
                  .minimumScaleFactor(0.5)
              }
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(weekday == entry.todayWeekday ? widgetAccent : .secondary)
          }
        }
        // 時限ごとの行（各行はグリッドの空き高さを等分して広がる）
        ForEach(1...entry.maxPeriod, id: \.self) { period in
          GridRow {
            Text("\(period)")
              .font(.caption2)
              .foregroundStyle(.secondary)
              .frame(width: 14)
            ForEach(Weekday.lectureDays) { weekday in
              GridCellView(
                cell: lookup[weekday]?[period],
                isTodayColumn: weekday == entry.todayWeekday
              )
            }
          }
        }
      }
      // グリッドを残り全高に広げ，行を等分する（固定高さにしないことで縦あふれを防ぐ）
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .containerBackground(for: .widget) { widgetBackground }
  }
}

/// 週間グリッドの1セル（科目名＋教室番号）
private struct GridCellView: View {
  let cell: WidgetGridCell?
  let isTodayColumn: Bool

  var body: some View {
    Group {
      if let cell {
        VStack(spacing: 0) {
          Text(cell.subjectName)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(2)
            .minimumScaleFactor(0.5)
          if !cell.roomNumber.isEmpty {
            // 教室番号（科目名の下に小さく表示）
            Text(cell.roomNumber)
              .font(.system(size: 8))
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .minimumScaleFactor(0.5)
          }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 1)
        // セルはグリッドの割当領域いっぱいに広がる（固定高さにしないことで見切れを防ぐ）
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          widgetAccent.opacity(isTodayColumn ? 0.35 : 0.18),
          in: RoundedRectangle(cornerRadius: 4)
        )
      } else {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.secondary.opacity(isTodayColumn ? 0.12 : 0.06))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}

// MARK: - 共通

/// ウィジェットの背景（システム背景＋淡いアクセントのグラデーション．ライト／ダーク両対応）
private var widgetBackground: some View {
  LinearGradient(
    colors: [.clear, widgetAccent.opacity(0.10)],
    startPoint: .top,
    endPoint: .bottom
  )
  .background(.background)
}

/// 日付を「6/17(火)」の形に整形する
private func todayText(_ date: Date) -> String {
  let calendar = Calendar.current
  let month = calendar.component(.month, from: date)
  let day = calendar.component(.day, from: date)
  let weekday = Weekday(rawValue: calendar.component(.weekday, from: date))?.shortName ?? ""
  return "\(month)/\(day)(\(weekday))"
}

/// 基準日と同じ週における，指定曜日の日付を返す．
/// 曜日値（1=日〜7=土）は日曜始まりの週内で単調なため，基準日との差分日数で求められる．
/// - Parameters:
///   - weekday: 対象の曜日
///   - reference: 基準日（この日を含む週で計算する）
/// - Returns: 対象曜日の日付（計算できなければnil）
private func gridDate(for weekday: Weekday, reference: Date) -> Date? {
  let calendar = Calendar.current
  let referenceWeekdayValue = calendar.component(.weekday, from: reference)
  let dayOffset = weekday.rawValue - referenceWeekdayValue
  return calendar.date(byAdding: .day, value: dayOffset, to: reference)
}

/// 日付を「6/15」の形（月/日）に整形する
private func shortDateLabel(_ date: Date) -> String {
  let calendar = Calendar.current
  return "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
}
