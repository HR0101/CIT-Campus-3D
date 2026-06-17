//
//  NextLectureResolver.swift
//  CIT-Campus-3D
//
//  現在時刻と登録済み時間割から「次の授業」を判定するサービス．
//  学年暦（AcademicCalendar）を参照し，長期休業・試験期間・休講日は授業なしとして扱う．
//

import Foundation

/// 次の授業の判定結果．
/// 千葉工大は基本2コマ（まれに3〜4コマ）で1つの授業のため，
/// 同じ科目名で連続するコマは1つのブロックとして扱う（lectureは先頭コマを代表とする）．
struct NextLectureResult {
  /// 対象の授業（複数コマ連続の場合は先頭コマを代表とする）
  let lecture: Lecture
  /// 授業（ブロック）の開始時刻（先頭コマの開始）
  let startDate: Date
  /// 授業（ブロック）の終了時刻（末尾コマの終了）
  let endDate: Date
  /// 現在授業中かどうか
  let isOngoing: Bool
  /// 今日の授業かどうか
  let isToday: Bool
  /// 先頭コマの時限番号
  let startPeriod: Int
  /// 末尾コマの時限番号（単一コマなら startPeriod と同じ）
  let endPeriod: Int

  /// 時限の表示文字列（例: 2限／1〜2限）
  var periodText: String {
    startPeriod == endPeriod ? "\(startPeriod)限" : "\(startPeriod)〜\(endPeriod)限"
  }

  /// 時間帯の表示文字列（例: 9:00〜11:00．先頭コマ開始〜末尾コマ終了）
  var timeRangeText: String {
    guard
      let start = ClassPeriod.period(number: startPeriod),
      let end = ClassPeriod.period(number: endPeriod)
    else {
      return ""
    }
    return String(
      format: "%d:%02d〜%d:%02d",
      start.startHour, start.startMinute, end.endHour, end.endMinute
    )
  }
}

/// 「次の授業」の判定を担うサービス
struct NextLectureResolver {

  /// 判定に関する定数
  private enum ResolverConstants {
    /// 何日先まで授業を探すか（今日を含めて1週間．授業は週単位で繰り返すため7日で十分）
    static let searchDayLimit = 7
    /// 一度に取り出す授業の最大件数（通知のまとめ予約用）
    static let defaultMaxCount = 16
  }

  /// 参照する学年暦
  let academicCalendar: AcademicCalendar

  init(academicCalendar: AcademicCalendar = .current) {
    self.academicCalendar = academicCalendar
  }

  /// 登録済みの授業から，これから始まる授業を時刻の早い順に列挙する．
  /// 学年暦上の休講日・授業期間外は除外する．
  /// - Parameters:
  ///   - lectures: 全登録授業
  ///   - now: 基準となる現在時刻
  ///   - maxCount: 取り出す最大件数
  ///   - calendar: 判定に使うカレンダー
  /// - Returns: これから始まる授業（終了済み・休講日・期間外は除外）を時刻順に並べた配列
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

      // 土日など授業のない曜日は除外する（lectureDaysを唯一の基準にする）
      let weekdayValue = calendar.component(.weekday, from: day)
      guard
        let weekday = Weekday(rawValue: weekdayValue),
        Weekday.lectureDays.contains(weekday)
      else {
        continue
      }

      // 学年暦でその日が授業日かどうかを判定し，授業実施日の学期を得る
      guard let semester = classSemester(on: day, calendar: calendar) else {
        continue
      }

      // その日の学期・曜日に該当する授業を取り出し，
      // 同じ科目名で連続するコマ（千葉工大の2〜4コマ連続授業）を1ブロックにまとめて列挙する
      let dayLectures = lectures.filter {
        $0.semesterRawValue == semester.rawValue && $0.weekdayRawValue == weekdayValue
      }
      let dayResults = groupConsecutiveLectures(dayLectures)
        .compactMap { block -> NextLectureResult? in
          guard
            let first = block.first,
            let last = block.last,
            let startPeriod = first.classPeriod,
            let endPeriod = last.classPeriod,
            let startDate = startPeriod.startDate(on: day, calendar: calendar),
            let endDate = endPeriod.endDate(on: day, calendar: calendar)
          else {
            return nil
          }
          // ブロック全体が終了するまでは「次の授業」に切り替えない（コマ途中で案内・通知を出さない）
          guard endDate > now else { return nil }
          return NextLectureResult(
            lecture: first,
            startDate: startDate,
            endDate: endDate,
            isOngoing: startDate <= now,
            isToday: dayOffset == 0,
            startPeriod: first.period,
            endPeriod: last.period
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

  /// 指定日の授業ブロック（連続コマ統合済み）を，終了済みも含めて時限順に返す．
  /// 「今日の時間割」をすべて表示したいウィジェット用（resolveUpcomingは終了済みを除外するため別に用意する）．
  /// 学年暦上の休講日・授業期間外・授業のない曜日（土日）の場合は空配列を返す．
  /// - Parameters:
  ///   - day: 対象日
  ///   - lectures: 全登録授業
  ///   - now: 現在時刻（isOngoing判定に使用）
  ///   - calendar: 判定に使うカレンダー
  /// - Returns: その日の授業ブロック（終了済みも含む）を時限順に並べた配列
  func blocks(
    on day: Date,
    from lectures: [Lecture],
    now: Date,
    calendar: Calendar = .current
  ) -> [NextLectureResult] {
    // 授業のない曜日（土日）は除外する
    let weekdayValue = calendar.component(.weekday, from: day)
    guard
      let weekday = Weekday(rawValue: weekdayValue),
      Weekday.lectureDays.contains(weekday)
    else {
      return []
    }
    // 学年暦でその日が授業日かどうかを判定し，授業実施日の学期を得る（休講・期間外はnil）
    guard let semester = classSemester(on: day, calendar: calendar) else {
      return []
    }

    let isToday = calendar.isDate(day, inSameDayAs: now)
    let dayLectures = lectures.filter {
      $0.semesterRawValue == semester.rawValue && $0.weekdayRawValue == weekdayValue
    }
    return groupConsecutiveLectures(dayLectures)
      .compactMap { block -> NextLectureResult? in
        guard
          let first = block.first,
          let last = block.last,
          let startPeriod = first.classPeriod,
          let endPeriod = last.classPeriod,
          let startDate = startPeriod.startDate(on: day, calendar: calendar),
          let endDate = endPeriod.endDate(on: day, calendar: calendar)
        else {
          return nil
        }
        return NextLectureResult(
          lecture: first,
          startDate: startDate,
          endDate: endDate,
          // 開始済みかつ未終了のときだけ「授業中」とみなす（終了済みはfalse）
          isOngoing: startDate <= now && now < endDate,
          isToday: isToday,
          startPeriod: first.period,
          endPeriod: last.period
        )
      }
      .sorted { $0.startDate < $1.startDate }
  }

  /// 指定日時点で参照すべき学期（週間時間割の表示に使う）．
  /// 授業期間中はその学期，期間外は次に始まる学期，全期間終了後は後期，学年暦対象外の年は月ベースで判定する．
  /// - Parameters:
  ///   - day: 基準日
  ///   - calendar: 判定に使うカレンダー
  /// - Returns: 表示対象とする学期
  func currentSemester(on day: Date, calendar: Calendar = .current) -> Semester {
    switch academicCalendar.scheduleStatus(on: day, calendar: calendar) {
    case .classDay(let semester):
      return semester
    case .closureDay:
      // 休講日は授業期間内なので，その期間の学期を返す
      return academicCalendar.term(on: day, calendar: calendar)?.semester
        ?? Semester.current(on: day, calendar: calendar)
    case .breakUntil(let nextSemester, _):
      return nextSemester
    case .afterAllTerms:
      return .secondHalf
    case .unknownYear:
      return Semester.current(on: day, calendar: calendar)
    }
  }

  // MARK: - Private

  /// 同じ科目名で連続する時限を1つのブロック（授業）にまとめる．
  /// 千葉工大の授業は基本2コマ・まれに3〜4コマで1つのため，連続コマを別授業として扱うと
  /// 授業の途中で「次の授業」案内や毎時の通知が出てしまう．それを防ぐためにまとめる．
  /// - Parameter lectures: 同一日・同一学期の授業（コマ単位）
  /// - Returns: 連続する同名コマごとにまとめた配列（各要素が1つの授業ブロック）
  private func groupConsecutiveLectures(_ lectures: [Lecture]) -> [[Lecture]] {
    let sorted = lectures.sorted { $0.period < $1.period }
    var blocks: [[Lecture]] = []
    for lecture in sorted {
      if let previous = blocks.last?.last,
        previous.subjectName == lecture.subjectName,
        lecture.period == previous.period + 1 {
        // 直前のコマと同じ科目名かつ次の時限なら，同じ授業ブロックに連結する
        blocks[blocks.count - 1].append(lecture)
      } else {
        blocks.append([lecture])
      }
    }
    return blocks
  }

  /// その日が授業実施日であればその学期を返す（休講日・授業期間外はnil）．
  /// 学年暦データの対象外の年は，旧来の月ベース判定にフォールバックする．
  private func classSemester(on day: Date, calendar: Calendar) -> Semester? {
    if academicCalendar.covers(day, calendar: calendar) {
      // 学年暦の対象年: 授業期間内かつ休講日でない日のみ授業ありとする
      guard let term = academicCalendar.term(on: day, calendar: calendar) else {
        return nil  // 長期休業・試験期間など
      }
      guard academicCalendar.isClassDay(day, calendar: calendar) else {
        return nil  // 休講日
      }
      return term.semester
    } else {
      // 学年暦データの対象外の年: 月ベースの簡易判定にフォールバック
      return Semester.current(on: day, calendar: calendar)
    }
  }
}
