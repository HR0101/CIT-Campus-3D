//
//  PortalChangeParser.swift
//  CIT-Campus-3D
//
//  ポータル「時間割変更」掲示の本文テキストを解析して，休講・補講・教室変更の構造化データ（ClassChangeDraft）を作る．
//  本文は次のようなラベル付きフリーテキスト（全角コロン・ラベル内の全角スペースに対応する）:
//
//    科目名：デジタル通信 情工　※情報_ディジタル通信
//    教員名：佐波　孝彦
//    日　時：2026年6月19日（金）4・5限
//    教　室：731教室
//

import Foundation

/// 取り込み前の時間割変更ドラフト
struct ClassChangeDraft {
  let type: ClassChangeType
  let subjectName: String
  let teacherName: String
  let date: Date?
  let startPeriod: Int
  let endPeriod: Int
  let room: String
  let noticeTitle: String
  let postedDate: Date?
  let changeKey: String

  /// SwiftDataの永続モデルを生成する
  func makeChange(importedAt: Date) -> ClassChange {
    ClassChange(
      type: type,
      subjectName: subjectName,
      teacherName: teacherName,
      date: date,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      room: room,
      noticeTitle: noticeTitle,
      postedDate: postedDate,
      changeKey: changeKey,
      importedAt: importedAt
    )
  }
}

/// 「時間割変更」掲示の本文パーサ
enum PortalChangeParser {

  /// 本文テキストと件名から ClassChangeDraft を作る（必要項目が取れない場合はnil）
  /// - Parameters:
  ///   - bodyText: 掲示本文のテキスト（innerText）
  ///   - title: 掲示の件名
  ///   - postedDate: 掲載日（不明ならnil）
  static func makeDraft(bodyText: String, title: String, postedDate: Date?) -> ClassChangeDraft? {
    // 種別は件名・本文の双方から判定する
    let type = ClassChangeType.detect(from: title + " " + bodyText)

    var subject = ""
    var teacher = ""
    var datetimeValue = ""
    var room = ""

    // 行ごとに「ラベル：値」を取り出す（ラベル内の全角・半角スペースは無視）
    for rawLine in bodyText.components(separatedBy: .newlines) {
      guard let colonRange = rawLine.rangeOfCharacter(from: CharacterSet(charactersIn: "：:")) else {
        continue
      }
      let label = String(rawLine[..<colonRange.lowerBound])
        .replacingOccurrences(of: "　", with: "")
        .replacingOccurrences(of: " ", with: "")
        .trimmingCharacters(in: .whitespaces)
      let value = String(rawLine[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)

      switch label {
      case "科目名": subject = value
      case "教員名": teacher = value
      case "日時": datetimeValue = value
      case "教室": room = normalizeRoom(value)
      default: break
      }
    }

    // 件名から科目名が取れないとき（本文にラベルが無い等）は件名から推測する
    if subject.isEmpty {
      subject = subjectFromTitle(title)
    }
    // 日時が本文に無い場合は件名の日付（例: 「5/8 …」）を試す
    let parsed = parseDateAndPeriods(datetimeValue)
    let date = parsed.date ?? dateFromTitle(title)

    // 種別・科目のどちらも取れなければ変更として扱わない
    guard type != .other || !subject.isEmpty else { return nil }

    let startPeriod = parsed.periods.min() ?? 0
    let endPeriod = parsed.periods.max() ?? 0
    let key = makeKey(type: type, subject: subject, date: date, startPeriod: startPeriod)

    return ClassChangeDraft(
      type: type,
      subjectName: subject,
      teacherName: teacher,
      date: date,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      room: room,
      noticeTitle: title,
      postedDate: postedDate,
      changeKey: key
    )
  }

  // MARK: - 解析ヘルパー

  /// 「2026年6月19日（金）4・5限」から日付と時限配列を取り出す
  private static func parseDateAndPeriods(_ text: String) -> (date: Date?, periods: [Int]) {
    let normalized = toHalfWidthDigits(text)
    return (parseJapaneseDate(normalized), parsePeriods(normalized))
  }

  /// 「YYYY年M月D日」形式の日付（Asia/Tokyoの正午で返す）
  private static func parseJapaneseDate(_ text: String) -> Date? {
    guard
      let match = text.range(of: #"(\d{4})年(\d{1,2})月(\d{1,2})日"#, options: .regularExpression)
    else { return nil }
    let matched = String(text[match])
    let numbers = matched
      .components(separatedBy: CharacterSet(charactersIn: "年月日"))
      .compactMap { Int($0) }
    guard numbers.count >= 3 else { return nil }

    var components = DateComponents()
    components.year = numbers[0]
    components.month = numbers[1]
    components.day = numbers[2]
    components.hour = 12  // 時差の影響で前後日へずれないよう正午にする
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    return calendar.date(from: components)
  }

  /// 「4・5限」「3〜4限」「2限」などから時限配列を取り出す
  private static func parsePeriods(_ text: String) -> [Int] {
    // 「限」の直前にある数字の並び（区切り含む）を取り出す
    guard
      let range = text.range(of: #"\d[\d・,，･\-〜～~ー－\s]*限"#, options: .regularExpression)
    else { return [] }
    let segment = String(text[range])
    // 範囲指定（3〜4限など）は両端から連続展開する
    let digitGroups = segment.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted)
      .compactMap { Int($0) }
      .filter { $0 > 0 }
    guard let first = digitGroups.first else { return [] }
    if segment.range(of: #"[〜～~ーｰ\-－]"#, options: .regularExpression) != nil,
      let last = digitGroups.last, last > first {
      // 範囲（first〜last）
      return Array(first...last)
    }
    // 列挙（4・5限）または単一（2限）
    return digitGroups
  }

  /// 「731教室」→「731」のように教室番号だけにする
  private static func normalizeRoom(_ text: String) -> String {
    text
      .replacingOccurrences(of: "教室", with: "")
      .replacingOccurrences(of: "講義室", with: "")
      .trimmingCharacters(in: .whitespaces)
  }

  /// 件名「【デジタル通信 情工…】補講のお知らせ」から科目名（【】内）を取り出す
  private static func subjectFromTitle(_ title: String) -> String {
    if let open = title.firstIndex(of: "【"), let close = title.firstIndex(of: "】"), open < close {
      return String(title[title.index(after: open)..<close])
    }
    return ""
  }

  /// 件名先頭の「5/8 …」のような日付を，今年の日付として取り出す
  private static func dateFromTitle(_ title: String) -> Date? {
    let normalized = toHalfWidthDigits(title)
    guard
      let range = normalized.range(of: #"(\d{1,2})/(\d{1,2})"#, options: .regularExpression)
    else { return nil }
    let parts = String(normalized[range]).split(separator: "/").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
    let year = calendar.component(.year, from: Date())
    var components = DateComponents()
    components.year = year
    components.month = parts[0]
    components.day = parts[1]
    components.hour = 12
    return calendar.date(from: components)
  }

  /// 全角数字を半角へ変換する
  private static func toHalfWidthDigits(_ text: String) -> String {
    let fullWidth = Array("０１２３４５６７８９")
    var result = text
    for (index, character) in fullWidth.enumerated() {
      result = result.replacingOccurrences(of: String(character), with: String(index))
    }
    return result
  }

  /// 重複排除キー
  private static func makeKey(type: ClassChangeType, subject: String, date: Date?, startPeriod: Int) -> String {
    let dateKey: String
    if let date {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .current
      let c = calendar.dateComponents([.year, .month, .day], from: date)
      dateKey = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    } else {
      dateKey = "nodate"
    }
    return "\(type.rawValue)|\(subject)|\(dateKey)|\(startPeriod)"
  }
}
