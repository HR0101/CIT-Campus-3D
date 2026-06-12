//
//  PDFTimetableParser.swift
//  CIT-Campus-3D
//
//  ポータルの「学生時間割表」PDFを解析するパーサ．
//  PDFのテキストをそのまま読むと列をまたいで行が混ざるため，
//  PDFSelection（矩形指定のテキスト選択）で表のセル構造を幾何学的に復元する:
//    - 「月曜日」〜「土曜日」ラベルの位置 → 曜日列の境界
//    - 表の左端の1〜10の数字 → 時限ブロックのY座標帯
//    - 各（時限帯 × 曜日列）の矩形選択 → 1コマ分の視覚行（selectionsByLine）
//  ※このロジックは実際の時間割PDF（4ページ・前期/後期・42コマ）で検証済み．
//

import Foundation
import PDFKit

/// PDF形式の学生時間割表パーサ
struct PDFTimetableParser {

  /// 座標処理に関する定数
  private enum LayoutConstants {
    /// 時限マーカー行をセル帯に含めるための余白（ポイント）
    static let bandTopMargin: CGFloat = 1.0
    /// 表下端（凡例など）を除外する余白（ポイント）
    static let footerMargin: CGFloat = 2.0
  }

  /// 曜日ヘッダのラベルと曜日の対応
  private static let dayLabels: [(label: String, weekday: Weekday)] = [
    ("月曜日", .monday),
    ("火曜日", .tuesday),
    ("水曜日", .wednesday),
    ("木曜日", .thursday),
    ("金曜日", .friday),
    ("土曜日", .saturday),
  ]

  /// 表の下端を判定するためのフッタのキーワード（時限の凡例・集中講義表）
  private static let footerKeywords = ["（1限", "集中講義"]

  /// ファイルを解析して授業ドラフトの一覧を返す
  func parse(fileURL: URL) throws -> [LectureDraft] {
    guard let document = PDFDocument(url: fileURL) else {
      throw ImportError.cannotOpenFile
    }

    var drafts: [LectureDraft] = []
    for pageIndex in 0..<document.pageCount {
      guard let page = document.page(at: pageIndex) else { continue }
      drafts.append(contentsOf: parsePage(page, in: document))
    }

    guard !drafts.isEmpty else {
      throw ImportError.noLecturesFound
    }
    return drafts
  }

  // MARK: - Private

  /// 1ページ分を解析して授業ドラフトを返す
  private func parsePage(_ page: PDFPage, in document: PDFDocument) -> [LectureDraft] {
    guard let pageText = page.string else { return [] }
    let pageBounds = page.bounds(for: .mediaBox)

    // 学期の判定（見つからないページは時間割ではないとみなす）
    let semester: Semester
    if pageText.contains("年度前期") {
      semester = .firstHalf
    } else if pageText.contains("年度後期") {
      semester = .secondHalf
    } else {
      return []
    }

    // 曜日ラベルの位置 → 曜日列の境界
    let anchors = findDayAnchors(on: page, in: document)
    guard anchors.count >= 2, let firstAnchor = anchors.first else { return [] }
    let boundaries = columnBoundaries(for: anchors.map(\.centerX))
    guard boundaries.count == anchors.count + 1, let leftTableEdge = boundaries.first else {
      return []
    }

    // 時限マーカー（ヘッダより下・最初の曜日列より左にある1〜10の数字）
    let markers = findPeriodMarkers(
      on: page,
      pageBounds: pageBounds,
      leftBoundary: leftTableEdge,
      headerY: firstAnchor.labelY
    )
    guard let lastMarker = markers.last else { return [] }

    // 表の下端（時限の凡例や集中講義表を除外するための境界）
    let tableBottomY = findTableBottomY(
      on: page,
      in: document,
      pageBounds: pageBounds,
      lastMarkerY: lastMarker.maxY
    )

    // （時限帯 × 曜日列）ごとに矩形選択でセルを復元して解析
    var drafts: [LectureDraft] = []
    for (index, marker) in markers.enumerated() {
      // PDF座標は下が原点のため，下の行ほどYが小さい
      let bandTop = marker.maxY + LayoutConstants.bandTopMargin
      let bandBottom = index + 1 < markers.count
        ? markers[index + 1].maxY + LayoutConstants.bandTopMargin
        : tableBottomY
      guard bandTop > bandBottom else { continue }

      for (dayIndex, anchor) in anchors.enumerated() {
        let cellRect = CGRect(
          x: boundaries[dayIndex],
          y: bandBottom,
          width: boundaries[dayIndex + 1] - boundaries[dayIndex],
          height: bandTop - bandBottom
        )
        guard let cellSelection = page.selection(for: cellRect) else { continue }

        // 視覚行単位に分割し，上の行から順に並べる
        let cellLines = cellSelection.selectionsByLine()
          .map { (y: $0.bounds(for: page).midY, text: $0.string ?? "") }
          .sorted { $0.y > $1.y }
          .map(\.text)

        guard let parsed = LectureCellParser.parse(lines: cellLines) else { continue }
        drafts.append(
          LectureDraft(
            semester: semester,
            weekday: anchor.weekday,
            period: marker.period,
            subjectName: parsed.subjectName,
            teacherName: parsed.teacherName,
            buildingName: parsed.buildingName,
            roomNumber: parsed.roomNumber
          )
        )
      }
    }
    return drafts
  }

  /// 曜日ラベルの位置を検出する（中心X座標の昇順で返す）
  private func findDayAnchors(
    on page: PDFPage,
    in document: PDFDocument
  ) -> [(centerX: CGFloat, labelY: CGFloat, weekday: Weekday)] {
    var anchors: [(centerX: CGFloat, labelY: CGFloat, weekday: Weekday)] = []
    for (label, weekday) in Self.dayLabels {
      // findStringはドキュメント全体を検索するため，対象ページの結果だけを使う
      for selection in document.findString(label, withOptions: []) {
        guard selection.pages.contains(page) else { continue }
        let rect = selection.bounds(for: page)
        anchors.append((centerX: rect.midX, labelY: rect.midY, weekday: weekday))
      }
    }
    return anchors.sorted { $0.centerX < $1.centerX }
  }

  /// 曜日ラベル中心X座標から各列の境界を計算する（要素数はラベル数+1）
  private func columnBoundaries(for centers: [CGFloat]) -> [CGFloat] {
    guard centers.count >= 2, let first = centers.first, let last = centers.last else {
      return []
    }
    // 列幅は等間隔のため，隣接ラベルの中点を境界とする
    var boundaries: [CGFloat] = []
    let averageGap = (last - first) / CGFloat(centers.count - 1)
    boundaries.append(first - averageGap / 2)
    for index in 0..<(centers.count - 1) {
      boundaries.append((centers[index] + centers[index + 1]) / 2)
    }
    boundaries.append(last + averageGap / 2)
    return boundaries
  }

  /// 表の左端にある時限番号（1〜10）の位置を検出する（上から順に返す）
  private func findPeriodMarkers(
    on page: PDFPage,
    pageBounds: CGRect,
    leftBoundary: CGFloat,
    headerY: CGFloat
  ) -> [(maxY: CGFloat, period: Int)] {
    // ヘッダより下・最初の曜日列より左の縦長の帯を選択し，行ごとに数字を探す
    let leftStrip = CGRect(
      x: pageBounds.minX,
      y: pageBounds.minY,
      width: leftBoundary - pageBounds.minX,
      height: headerY - pageBounds.minY
    )
    guard let stripSelection = page.selection(for: leftStrip) else { return [] }

    let validPeriods = 1...ClassPeriod.allPeriods.count
    var markers: [(maxY: CGFloat, period: Int)] = []
    for lineSelection in stripSelection.selectionsByLine() {
      guard
        let text = lineSelection.string?.trimmingCharacters(in: .whitespaces),
        let value = Int(text),
        validPeriods.contains(value)
      else {
        continue
      }
      markers.append((maxY: lineSelection.bounds(for: page).maxY, period: value))
    }
    return markers.sorted { $0.maxY > $1.maxY }
  }

  /// 表の下端のY座標を求める（時限の凡例・集中講義表を除外するため）
  private func findTableBottomY(
    on page: PDFPage,
    in document: PDFDocument,
    pageBounds: CGRect,
    lastMarkerY: CGFloat
  ) -> CGFloat {
    var bottomY = pageBounds.minY
    for keyword in Self.footerKeywords {
      for selection in document.findString(keyword, withOptions: []) {
        guard selection.pages.contains(page) else { continue }
        let y = selection.bounds(for: page).maxY
        // 最後の時限マーカーより下にあるフッタのうち，最も上のものを下端とする
        if y < lastMarkerY, y + LayoutConstants.footerMargin > bottomY {
          bottomY = y + LayoutConstants.footerMargin
        }
      }
    }
    return bottomY
  }
}
