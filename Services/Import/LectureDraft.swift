//
//  LectureDraft.swift
//  CIT-Campus-3D
//
//  ファイル解析結果の中間表現と，セル文字列の共通パーサ．
//  解析結果はプレビュー画面でユーザーが確認してからSwiftDataへ保存する．
//

import Foundation

/// 解析された授業1コマ分のドラフト（保存前の中間表現）
struct LectureDraft: Identifiable, Hashable {
  let id = UUID()
  /// 学期
  let semester: Semester
  /// 曜日
  let weekday: Weekday
  /// 時限（1〜10）
  let period: Int
  /// 科目名（クラス指定などを除去した表示用の名称）
  let subjectName: String
  /// 教員名
  let teacherName: String
  /// キャンパス（場所表記から判別）
  let campus: Campus
  /// 講義棟名（教室番号から推定．不明の場合は空文字）
  let buildingName: String
  /// 教室番号（例: 731．不明の場合は空文字）
  let roomNumber: String

  /// SwiftDataモデルへ変換する
  func makeLecture() -> Lecture {
    Lecture(
      semester: semester,
      weekday: weekday,
      period: period,
      subjectName: subjectName,
      teacherName: teacherName,
      campus: campus,
      buildingName: buildingName,
      roomNumber: roomNumber
    )
  }
}

/// 時間割表のセル文字列（視覚行の配列）から授業情報を抽出する共通パーサ．
/// ExcelとPDFのどちらの解析でも同じセル構造
/// 「科目名（複数行）→教員名→教室／キャンパス→[複数回]等→N単位」を前提とする．
enum LectureCellParser {

  /// セルから抽出した授業情報
  struct ParsedCell {
    let subjectName: String
    let teacherName: String
    let campus: Campus
    let buildingName: String
    let roomNumber: String
  }

  /// セル内の視覚行の配列を解析する（授業セルでない場合はnil）
  static func parse(lines rawLines: [String]) -> ParsedCell? {
    // 空行を除去して前後の空白を整える
    let lines = rawLines
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard !lines.isEmpty else { return nil }

    // 場所ブロックの開始行: 「講義室」を含む行，なければ「キャンパス」を含む行．
    // どちらもないセルは授業セルとみなさない
    guard let locationStart = lines.firstIndex(where: { $0.contains("講義室") })
      ?? lines.firstIndex(where: { $0.contains("キャンパス") })
    else {
      return nil
    }

    // 場所ブロックの終了行: 開始行以降で「キャンパス」を含む最初の行
    // （「６４６講義室／津」「田沼キャンパス」のように改行で分割されているため）
    let locationEnd = lines[locationStart...].firstIndex { $0.contains("キャンパス") }
      ?? locationStart
    let locationText = lines[locationStart...locationEnd].joined()

    // 教員名: 場所ブロックの直前の行．科目名: それより前の行をすべて結合
    // （科目名は行の途中で折り返されるため，区切りなしで連結する）
    let teacherName: String
    let rawSubjectName: String
    if locationStart >= 2 {
      teacherName = lines[locationStart - 1]
      rawSubjectName = lines[0..<(locationStart - 1)].joined()
    } else {
      teacherName = ""
      rawSubjectName = lines[0..<locationStart].joined()
    }

    let subjectName = cleanSubjectName(rawSubjectName)
    guard !subjectName.isEmpty else { return nil }

    // 場所表記（例: ７３１講義室／津田沼キャンパス）からキャンパスと講義棟を判別する
    let campus = Campus.detect(fromLocationText: locationText)
    let roomNumber = extractRoomNumber(from: locationText)
    let buildingName = CampusBuilding.building(forRoomNumber: roomNumber, campus: campus)?.name ?? ""

    return ParsedCell(
      subjectName: subjectName,
      teacherName: teacherName,
      campus: campus,
      buildingName: buildingName,
      roomNumber: roomNumber
    )
  }

  // MARK: - Private

  /// 科目名からクラス指定などの付帯表記を除去する
  /// 例: 「離散数学 情工3年　※情N経P」→「離散数学」
  private static func cleanSubjectName(_ rawName: String) -> String {
    var name = rawName
    // 「※」以降のクラス指定（例: ※情報NS）を除去
    if let range = name.range(of: "※") {
      name = String(name[..<range.lowerBound])
    }
    // 「情工」以降の対象学科表記（例: 情工3年）を除去
    if let range = name.range(of: "情工") {
      name = String(name[..<range.lowerBound])
    }
    // 「再履修」表記を除去
    if let range = name.range(of: "再履修") {
      name = String(name[..<range.lowerBound])
    }
    // 半角・全角の空白を前後から除去
    let trimSet = CharacterSet.whitespacesAndNewlines
      .union(CharacterSet(charactersIn: "　"))
    return name.trimmingCharacters(in: trimSet)
  }

  /// 場所テキストから教室番号を取り出す
  /// 例: 「６４６講義室／津田沼キャンパス」→「646」
  private static func extractRoomNumber(from locationText: String) -> String {
    guard let range = locationText.range(of: "講義室") else {
      return ""
    }
    let prefix = locationText[..<range.lowerBound]
    let digits = prefix.compactMap { normalizeDigit($0) }
    return String(digits)
  }

  /// 全角数字を半角に正規化する（数字以外はnil）
  private static func normalizeDigit(_ character: Character) -> Character? {
    guard character.isNumber else { return nil }
    guard let scalar = character.unicodeScalars.first else { return nil }
    // 全角数字（０〜９）を半角（0〜9）へ変換
    let fullWidthZero: UInt32 = 0xFF10
    let fullWidthNine: UInt32 = 0xFF19
    let halfWidthZero: UInt32 = 0x30
    if scalar.value >= fullWidthZero, scalar.value <= fullWidthNine {
      guard let converted = UnicodeScalar(scalar.value - fullWidthZero + halfWidthZero) else {
        return character
      }
      return Character(converted)
    }
    return character
  }
}
