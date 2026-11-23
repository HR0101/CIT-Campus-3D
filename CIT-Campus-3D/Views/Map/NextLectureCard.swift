//
//  NextLectureCard.swift
//  CIT-Campus-3D
//
//  マップ上部に表示する「次の授業」の情報カード．
//

import SwiftUI

/// 次の授業の情報カード
struct NextLectureCard: View {

  /// 次の授業の判定結果
  let result: NextLectureResult

  /// 出席ボタンがタップされた時のコールバック
  var onAttendanceTap: ((URL) -> Void)?

  /// 状態バッジの文言（授業中／次の授業）
  private var badgeText: String {
    result.isOngoing ? "授業中" : "次の授業"
  }

  /// 日時の表示文字列（例: 今日 1〜2限 9:00〜11:00／月曜 2限 10:00〜11:00）．
  /// 連続コマは1ブロックとして時限・時間帯をまとめて表示する
  private var scheduleText: String {
    let dayText = result.isToday ? "今日" : "\(result.lecture.weekday.shortName)曜"
    return "\(dayText) \(result.periodText) \(result.timeRangeText)"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Text(badgeText)
          .font(.caption2.weight(.medium))
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(
            result.isOngoing ? CampusTheme.warning.opacity(0.14) : CampusTheme.accentTint,
            in: RoundedRectangle(cornerRadius: CampusTheme.tagRadius)
          )
          .foregroundStyle(result.isOngoing ? CampusTheme.warning : CampusTheme.accent)

        Text(scheduleText)
          .font(.caption)
          .monospacedDigit()
          .foregroundStyle(CampusTheme.textSecondary)
      }

      Text(result.lecture.subjectName)
        .font(.headline.weight(.medium))
        .foregroundStyle(CampusTheme.textPrimary)
        .lineLimit(2)
        .minimumScaleFactor(0.85)

      HStack(alignment: .bottom, spacing: 12) {
        HStack(spacing: 12) {
          Label(result.lecture.placeText, systemImage: "building.2")
          if !result.lecture.teacherName.isEmpty {
            Label(result.lecture.teacherName, systemImage: "person")
          }
        }
        .font(.caption)
        .foregroundStyle(CampusTheme.textSecondary)
        .lineLimit(1)

        Spacer(minLength: 8)

        if !result.lecture.attendanceRoomId.isEmpty,
           let url = URL(string: "https://attendance.is.chibatech.ac.jp/attendance/class_room/\(result.lecture.attendanceRoomId)") {
          Button {
            onAttendanceTap?(url)
          } label: {
            Label("出席", systemImage: "checkmark.circle")
              .font(.caption.weight(.medium))
              .padding(.horizontal, 12)
              .padding(.vertical, 6)
              .background(CampusTheme.accentTint, in: RoundedRectangle(cornerRadius: CampusTheme.controlRadius))
              .foregroundStyle(CampusTheme.accent)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .campusFloatingCard()
  }
}
