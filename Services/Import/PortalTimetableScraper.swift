//
//  PortalTimetableScraper.swift
//  CIT-Campus-3D
//
//  大学ポータル（UNIVERSAL PASSPORT / UNIPA）の時間割表ページから，
//  WebViewに注入するJavaScriptで時間割を読み取り，取り込み用のドラフト（LectureDraft）へ変換する．
//
//  ※ ポータルのHTML構造は変わりうるため，読み取りは「曜日見出し＋時限行を持つ表」を
//    汎用的に探す方針とし，セル文言の解釈はSwift側で行って調整しやすくしている．
//

import Foundation

/// スクレイプした1コマ分（曜日・時限・セル本文・学期）
struct ScrapedCell: Codable {
  /// 曜日（Weekday.rawValueと同じ 1=日〜7=土）
  let day: Int
  /// 時限（1〜10）
  let period: Int
  /// セルの本文（改行区切りの生テキスト）
  let text: String
  /// このコマが属する学期（"前期"/"後期"．表ごとに判別．不明ならnil）
  let semester: String?
}

/// スクレイプ結果（JSがJSON文字列として返す）
struct ScrapeResult: Codable {
  /// 読み取った全コマ
  let cells: [ScrapedCell]
  /// ページから推定した学期（"前期"/"後期"．不明ならnil）
  let semester: String?
  /// 読み取れなかった場合の理由（正常時はnil）
  let error: String?
}

/// 時間割表ページに注入するスクレイピングスクリプト
enum PortalTimetableScraper {

  /// WebViewで評価するJavaScript．ページ内の時間割表（複数可）を探し，JSON文字列を返す．
  /// - 表の探索条件: ヘッダ行に曜日（「○曜」を3つ以上）を含む表すべて（前期・後期が同一ページにあるため）
  /// - 曜日判定は「月曜日」等の末尾「曜日」の"日"を日曜と誤検出しないよう「○曜」を優先で照合する
  /// - rowspan/colspan（結合セル）を仮想グリッド化して列ずれを防ぐ（CITは結合せず各時限にセルを繰り返すが保険）
  /// - 表ごとに直前の見出しから学期（前期/後期）を判別し，各コマに付与する
  /// - 各データ行の先頭列セルから時限番号を取り出す（取れなければ行番号で代用）
  static let script: String = """
  (function() {
    function txt(el) {
      return ((el && (el.innerText || el.textContent)) || '').trim();
    }
    var dayKanji = ['日', '月', '火', '水', '木', '金', '土'];
    // 「○曜」を優先で照合し，無ければ単独の曜日文字で照合する（「月曜日」の末尾"日"の誤検出を防ぐ）
    function findDayIndex(s) {
      for (var i = 0; i < dayKanji.length; i++) {
        if (s.indexOf(dayKanji[i] + '曜') >= 0) return i;
      }
      for (var i = 0; i < dayKanji.length; i++) {
        if (s.indexOf(dayKanji[i]) >= 0) return i;
      }
      return -1;
    }
    // 要素の直接の子テキストノードだけを連結する（祖先が両学期を含む問題を避ける）
    function ownText(el) {
      var s = '';
      for (var i = 0; i < el.childNodes.length; i++) {
        var n = el.childNodes[i];
        if (n.nodeType === 3) s += n.nodeValue;
      }
      return s;
    }
    var allEls = document.body ? document.body.getElementsByTagName('*') : [];
    // 表より前方の見出しを逆走査し，最も近い「前期/後期」を学期とする
    function semesterForTable(table) {
      var idx = -1;
      for (var i = 0; i < allEls.length; i++) {
        if (allEls[i] === table) { idx = i; break; }
      }
      if (idx < 0) return null;
      var limit = Math.max(0, idx - 800);
      for (var i = idx - 1; i >= limit; i--) {
        var t = ownText(allEls[i]);
        if (t.indexOf('後期') >= 0) return '後期';
        if (t.indexOf('前期') >= 0) return '前期';
      }
      return null;
    }
    // 表をrowspan/colspanを反映した2次元配列（仮想グリッド）に展開する
    function buildGrid(table) {
      var grid = [], rows = table.rows;
      for (var r = 0; r < rows.length; r++) {
        if (!grid[r]) grid[r] = [];
        var col = 0, cells = rows[r].cells;
        for (var i = 0; i < cells.length; i++) {
          while (grid[r][col] !== undefined) col++;
          var cell = cells[i];
          var rs = cell.rowSpan || 1, cs = cell.colSpan || 1;
          for (var rr = 0; rr < rs; rr++) {
            if (!grid[r + rr]) grid[r + rr] = [];
            for (var cc = 0; cc < cs; cc++) {
              grid[r + rr][col + cc] = cell;
            }
          }
          col += cs;
        }
      }
      return grid;
    }

    var cells = [];
    var tables = document.getElementsByTagName('table');
    for (var t = 0; t < tables.length; t++) {
      var trows = tables[t].rows;
      if (!trows || trows.length < 2) continue;
      var grid = buildGrid(tables[t]);
      var header = grid[0] || [];
      var dayCols = {}, dayCount = 0;
      for (var c = 0; c < header.length; c++) {
        if (c in dayCols) continue;
        var di = findDayIndex(txt(header[c]));
        if (di >= 0) { dayCols[c] = di; dayCount++; }
      }
      if (dayCount < 3) continue;
      var sem = semesterForTable(tables[t]);
      for (var r = 1; r < grid.length; r++) {
        var rowArr = grid[r] || [];
        var periodText = rowArr[0] ? txt(rowArr[0]) : '';
        var match = periodText.match(/\\d+/);
        var period = match ? parseInt(match[0], 10) : r;
        for (var key in dayCols) {
          var ci = parseInt(key, 10);
          var cell = rowArr[ci];
          if (!cell) continue;
          var cellText = txt(cell);
          if (cellText.length < 2) continue;
          cells.push({ day: dayCols[key] + 1, period: period, text: cellText, semester: sem });
        }
      }
    }
    if (cells.length === 0) {
      return JSON.stringify({ cells: [], semester: null, error: 'timetable_not_found' });
    }
    return JSON.stringify({ cells: cells, semester: null, error: null });
  })();
  """
}

/// スクレイプ結果を取り込み用ドラフトへ変換する
enum PortalTimetableMapper {

  /// セルから抽出した授業情報
  private struct ParsedPortalCell {
    let subject: String
    let teacher: String
    let campus: Campus
    let building: String
    let room: String
  }

  /// スクレイプ結果をドラフト配列へ変換する
  /// - Parameters:
  ///   - result: JSの読み取り結果
  ///   - defaultSemester: ページから学期が判別できなかった場合に使う学期
  /// - Returns: 取り込み用ドラフト（解釈できないセルは除外）
  static func makeDrafts(from result: ScrapeResult, defaultSemester: Semester) -> [LectureDraft] {
    return result.cells.compactMap { cell -> LectureDraft? in
      // 授業のある曜日・妥当な時限のみ採用する
      guard
        let weekday = Weekday(rawValue: cell.day),
        Weekday.lectureDays.contains(weekday),
        cell.period >= 1, cell.period <= 10,
        let parsed = parseCellText(cell.text)
      else {
        return nil
      }
      // 学期は表ごとに判別した値を優先し，無ければ全体の判別値→既定の順で使う
      let semester = parseSemester(cell.semester)
        ?? parseSemester(result.semester)
        ?? defaultSemester
      return LectureDraft(
        semester: semester,
        weekday: weekday,
        period: cell.period,
        subjectName: parsed.subject,
        teacherName: parsed.teacher,
        campus: parsed.campus,
        buildingName: parsed.building,
        roomNumber: parsed.room
      )
    }
  }

  // MARK: - Private

  /// 学期文字列（"前期"/"後期"）を列挙へ変換する（不明ならnil）
  private static func parseSemester(_ text: String?) -> Semester? {
    guard let text else { return nil }
    if text.contains("後期") { return .secondHalf }
    if text.contains("前期") { return .firstHalf }
    return nil
  }

  /// セル本文（改行区切り）を授業情報へ解釈する
  private static func parseCellText(_ text: String) -> ParsedPortalCell? {
    let lines = text
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard let firstLine = lines.first else { return nil }

    let subject = cleanSubject(firstLine)
    guard !subject.isEmpty else { return nil }

    // 教室情報を含む行を探す（教室番号の抽出に使う）
    let locationLine = lines.first { isLocationLine($0) }
    // キャンパスは教室行に限らずセル全体から判別する（新習志野キャンパスの行が教室行と別なため）
    let campus = Campus.detect(fromLocationText: text)
    let room = extractRoomNumber(from: locationLine ?? "")
    let building = CampusBuilding.building(forRoomNumber: room, campus: campus)?.name ?? ""

    // 教員名: 科目名でも教室行でもない最初の行（無ければ空）
    let teacher = lines
      .dropFirst()
      .first { $0 != locationLine && !isLocationLine($0) } ?? ""

    return ParsedPortalCell(
      subject: subject,
      teacher: teacher,
      campus: campus,
      building: building,
      room: room
    )
  }

  /// 科目名から付帯表記（クラス指定・対象学科・再履修など）を除去する
  /// 例: 「離散数学 情工3年　※情N経P」→「離散数学」／「総合学際科目 身体論　再履修」→「総合学際科目 身体論」
  private static func cleanSubject(_ raw: String) -> String {
    var name = raw
    // 「※」以降のクラス指定，「情工」以降の対象学科，「再履修」以降を順に除去する
    for marker in ["※", "情工", "再履修"] {
      if let range = name.range(of: marker) {
        name = String(name[..<range.lowerBound])
      }
    }
    let trimSet = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "　"))
    return name.trimmingCharacters(in: trimSet)
  }

  /// 教室・キャンパスを示す行か（号館・教室・講義室・キャンパス，または3桁以上の数字を含む）
  private static func isLocationLine(_ line: String) -> Bool {
    if line.contains("号館") || line.contains("教室")
      || line.contains("講義室") || line.contains("キャンパス") {
      return true
    }
    return consecutiveDigitCount(in: line) >= 3
  }

  /// 行から教室番号（最初に現れる3桁以上の連続数字）を取り出す
  private static func extractRoomNumber(from line: String) -> String {
    var current: [Character] = []
    var longest: [Character] = []
    for character in line {
      if let digit = normalizeDigit(character) {
        current.append(digit)
      } else {
        if current.count > longest.count { longest = current }
        current = []
      }
    }
    if current.count > longest.count { longest = current }
    return longest.count >= 3 ? String(longest) : ""
  }

  /// 行に含まれる連続数字の最大長
  private static func consecutiveDigitCount(in line: String) -> Int {
    var current = 0, longest = 0
    for character in line {
      if normalizeDigit(character) != nil {
        current += 1
        longest = max(longest, current)
      } else {
        current = 0
      }
    }
    return longest
  }

  /// 全角数字を半角へ正規化する（数字以外はnil）
  private static func normalizeDigit(_ character: Character) -> Character? {
    guard character.isNumber, let scalar = character.unicodeScalars.first else { return nil }
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
