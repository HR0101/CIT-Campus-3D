//
//  NextLectureCard.swift
//  CIT-Campus-3D
//
//  マップ上部に表示する「次の授業」の情報カード．
//

import SwiftUI

/// 次の授業の情報カード
struct NextLectureCard: View {

  /// カードの見た目に関する定数
  private enum CardConstants {
    static let cornerRadius: CGFloat = 14
  }

  /// 次の授業の判定結果
  let result: NextLectureResult

  /// 状態バッジの文言（授業中／次の授業）
  private var badgeText: String {
    result.isOngoing ? "授業中" : "次の授業"
  }

  /// 日時の表示文字列（例: 今日 2限 10:00〜11:00／月曜 2限 10:00〜11:00）
  private var scheduleText: String {
    let dayText = result.isToday ? "今日" : "\(result.lecture.weekday.shortName)曜"
    let periodText = result.lecture.classPeriod?.displayName ?? "\(result.lecture.period)限"
    let timeText = result.lecture.classPeriod?.timeRangeText ?? ""
    return "\(dayText) \(periodText) \(timeText)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(badgeText)
          .font(.caption.bold())
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(
            result.isOngoing ? Color.orange.opacity(0.25) : Color.cyan.opacity(0.25),
            in: Capsule()
          )
          .foregroundStyle(result.isOngoing ? .orange : .cyan)

        Text(scheduleText)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Text(result.lecture.subjectName)
        .font(.headline)
        .foregroundStyle(.white)

      HStack(spacing: 12) {
        Label(result.lecture.placeText, systemImage: "building.2")
        if !result.lecture.teacherName.isEmpty {
          Label(result.lecture.teacherName, systemImage: "person")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: CardConstants.cornerRadius))
    .environment(\.colorScheme, .dark)
  }
}
