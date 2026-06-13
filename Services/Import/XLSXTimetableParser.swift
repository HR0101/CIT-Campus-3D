//
//  XLSXTimetableParser.swift
//  CIT-Campus-3D
//
//  ポータルの「学生時間割表」Excel（.xlsx）を解析するパーサ．
//  シートは印刷レイアウト型で，曜日は固定のアンカー列，セル内容は
//  視覚行ごとに別の行へ分割されている．構造は以下の通り:
//    - 「◯◯年度前期／後期」を含むセル → シートの学期
//    - 「月曜日」〜「土曜日」のセル → 曜日アンカー列（ヘッダ行）
//    - 曜日列より左にある1〜10の整数セル → 時限ブロックの開始行
//    - 各ブロック内の曜日アンカー列のセル群 → 1コマ分の視覚行
//

import CoreXLSX
import Foundation

/// Excel（.xlsx）形式の学生時間割表パーサ
struct XLSXTimetableParser {

  /// シート上の1セル（列番号・行番号・文字列）
  private struct SheetCell {
    let column: Int
    let row: Int
    let text: String
  }

  /// 曜日ヘッダのラベルと曜日の対応
  private static let dayLabels: [String: Weekday] = [
    "月曜日": .monday,
    "火曜日": .tuesday,
    "水曜日": .wednesday,
    "木曜日": .thursday,
    "金曜日": .friday,
    "土曜日": .saturday,
  ]

  /// ファイルを解析して授業ドラフトの一覧を返す
  func parse(fileURL: URL) throws -> [LectureDraft] {
    guard let file = XLSXFile(filepath: fileURL.path) else {
      throw ImportError.cannotOpenFile
    }

    let sharedStrings: SharedStrings?
    let worksheetPaths: [String]
    do {
      sharedStrings = try file.parseSharedStrings()
      worksheetPaths = try file.parseWorksheetPaths()
    } catch {
      throw ImportError.invalidFormat(detail: "Excelの内部構造を読み取れませんでした")
    }

    var drafts: [LectureDraft] = []
    for path in worksheetPaths {
      let worksheet: Worksheet
      do {
        worksheet = try file.parseWorksheet(at: path)
      } catch {
        // 1シートの失敗で全体を止めず，読めるシートだけ解析する
        continue
      }
      let cells = extractCells(from: worksheet, sharedStrings: sharedStrings)
      drafts.append(contentsOf: parseSheet(cells: cells))
    }

    guard !drafts.isEmpty else {
      throw ImportError.noLecturesFound
    }
    return drafts
  }

  // MARK: - Private

  /// ワークシートから文字列の入ったセルだけを取り出す
  private func extractCells(
    from worksheet: Worksheet,
    sharedStrings: SharedStrings?
  ) -> [SheetCell] {
    var cells: [SheetCell] = []
    for row in worksheet.data?.rows ?? [] {
      for cell in row.cells {
        let text: String?
        if let sharedStrings {
          text = cell.stringValue(sharedStrings) ?? cell.value
        } else {
          text = cell.value
        }
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
          continue
        }
        cells.append(
          SheetCell(
            column: columnNumber(cell.reference.column.value),
            row: Int(cell.reference.row),
            text: text
          )
        )
      }
    }
    return cells
  }

  /// 1シート分のセル群を解析して授業ドラフトを返す
  private func parseSheet(cells: [SheetCell]) -> [LectureDraft] {
    // 学期の判定（見つからないシートは時間割ではないとみなす）
    guard let semester = detectSemester(cells: cells) else {
      return []
    }

    // 曜日ヘッダ（アンカー列）の検出
    var dayColumns: [(column: Int, weekday: Weekday)] = []
    var headerRow = 0
    for cell in cells {
      if let weekday = Self.dayLabels[cell.text.trimmingCharacters(in: .whitespaces)] {
        dayColumns.append((cell.column, weekday))
        headerRow = max(headerRow, cell.row)
      }
    }
    guard let minDayColumn = dayColumns.map(\.column).min() else {
      return []
    }

    // 時限マーカー（曜日列より左にある1〜10の整数セル）の検出
    let validPeriods = 1...ClassPeriod.allPeriods.count
    let periodMarkers = cells
      .filter { $0.row > headerRow && $0.column < minDayColumn }
      .compactMap { cell -> (row: Int, period: Int)? in
        guard
          let value = Int(cell.text.trimmingCharacters(in: .whitespaces)),
          validPeriods.contains(value)
        else {
          return nil
        }
        return (row: cell.row, period: value)
      }
      .sorted { $0.row < $1.row }

    // 時限ブロックごとに曜日アンカー列のセルを集めて解析
    var drafts: [LectureDraft] = []
    for (index, marker) in periodMarkers.enumerated() {
      let endRow = index + 1 < periodMarkers.count
        ? periodMarkers[index + 1].row - 1
        : Int.max
      for (column, weekday) in dayColumns {
        let lines = cells
          .filter { $0.column == column && $0.row >= marker.row && $0.row <= endRow }
          .sorted { $0.row < $1.row }
          .map(\.text)
        guard let parsed = LectureCellParser.parse(lines: lines) else {
          continue
        }
        drafts.append(
          LectureDraft(
            semester: semester,
            weekday: weekday,
            period: marker.period,
            subjectName: parsed.subjectName,
            teacherName: parsed.teacherName,
            campus: parsed.campus,
            buildingName: parsed.buildingName,
            roomNumber: parsed.roomNumber
          )
        )
      }
    }
    return drafts
  }

  /// シート内の「◯◯年度前期／後期」表記から学期を判定する
  private func detectSemester(cells: [SheetCell]) -> Semester? {
    for cell in cells {
      if cell.text.contains("年度前期") {
        return .firstHalf
      }
      if cell.text.contains("年度後期") {
        return .secondHalf
      }
    }
    return nil
  }

  /// 列のアルファベット表記を列番号へ変換する（A=1, B=2, …, AA=27）
  private func columnNumber(_ letters: String) -> Int {
    let baseValue = Int(UnicodeScalar("A").value)
    return letters.uppercased().unicodeScalars.reduce(0) { result, scalar in
      result * 26 + Int(scalar.value) - baseValue + 1
    }
  }
}
