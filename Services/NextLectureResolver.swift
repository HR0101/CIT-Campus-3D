//
//  NextLectureResolver.swift
//  CIT-Campus-3D
//
//  現在時刻と登録済み時間割から「次の授業」を判定するサービス．
//

import Foundation

/// 次の授業の判定結果
struct NextLectureResult {
  /// 対象の授業
  let lecture: Lecture
  /// 授業の開始時刻
  let startDate: Date
  /// 授業の終了時刻
  let endDate: Date
  /// 現在授業中かどうか
  let isOngoing: Bool
  /// 今日の授業かどうか
  let isToday: Bool
}

/// 「次の授業」の判定を担うサービス
struct NextLectureResolver {

  /// 判定に関する定数
  private enum ResolverConstants {
    /// 何日先まで授業を探すか（今日を含めて1週間）
    static let searchDayLimit = 7
    /// 一度に取り出す授業の最大件数（通知のまとめ予約用）
    static let defaultMaxCount = 16
  }

  /// 登録済みの授業から，これから始まる授業を時刻の早い順に列挙する
  /// - Parameters:
  ///   - lectures: 全登録授業
  ///   - now: 基準となる現在時刻
  ///   - maxCount: 取り出す最大件数
  ///   - calendar: 判定に使うカレンダー
  /// - Returns: これから始まる授業（終了済みは除外）を時刻順に並べた配列
  func resolveUpcoming(
    from lectures: [Lecture],
    now: Date,
    maxCount: Int = ResolverConstants.defaultMaxCount,
    calendar: Calendar = .current
  ) -> [NextLectureResult] {
    guard !lectures.isEmpty else { return [] }

    var results: [NextLectureResult] = []
    // 今日から最大7日先まで順に走査する
    for dayOffset in 0..<ResolverConstants.searchDayLimit {
      guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now) else {
        continue
      }
      let semester = Semester.current(on: day, calendar: calendar)
      let weekdayValue = calendar.component(.weekday, from: day)

      // その日の学期・曜日に該当する授業を時刻つきで列挙
      let dayResults = lectures
        .filter {
          $0.semesterRawValue == semester.rawValue && $0.weekdayRawValue == weekdayValue
        }
        .compactMap { lecture -> NextLectureResult? in
          guard
            let classPeriod = lecture.classPeriod,
            let startDate = classPeriod.startDate(on: day, calendar: calendar),
            let endDate = classPeriod.endDate(on: day, calendar: calendar)
          else {
            return nil
          }
          // すでに終了した授業は対象外（当日のみ実質的に効く条件）
          guard endDate > now else { return nil }
          return NextLectureResult(
            lecture: lecture,
            startDate: startDate,
            endDate: endDate,
            isOngoing: startDate <= now,
            isToday: dayOffset == 0
          )
        }
        .sorted { $0.startDate < $1.startDate }

      results.append(contentsOf: dayResults)
      if results.count >= maxCount {
        break
      }
    }
    return Array(results.prefix(maxCount))
  }

  /// 登録済みの授業から次の授業を1件だけ判定する
  /// - Returns: 次の授業（1週間以内に見つからない場合はnil）
  func resolveNextLecture(
    from lectures: [Lecture],
    now: Date,
    calendar: Calendar = .current
  ) -> NextLectureResult? {
    resolveUpcoming(from: lectures, now: now, maxCount: 1, calendar: calendar).first
  }
}
