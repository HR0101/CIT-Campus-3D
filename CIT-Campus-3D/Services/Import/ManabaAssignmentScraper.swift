//
//  ManabaAssignmentScraper.swift
//  CIT-Campus-3D
//
//  manaba（cit.manaba.jp）の未提出課題一覧ページ（home_library_query）から
//  課題行（table.stdlist）を読み取るためのJavaScriptと，その結果をAssignmentへ変換する処理．
//

import Foundation

/// スクレイプした課題1件（JSから受け取る生データ）
struct ManabaAssignmentRow: Decodable {
  /// タイプ（レポート等）
  let type: String
  /// タイトル
  let title: String
  /// 課題URL
  let url: String
  /// コース名
  let course: String
  /// コースURL
  let courseUrl: String
  /// 受付開始日時の文字列（空の場合あり）
  let start: String
  /// 受付終了日時（締切）の文字列
  let due: String
}

/// スクレイプ結果（課題一覧）
struct ManabaScrapeResult: Decodable {
  /// エラー種別（空文字なら成功）
  let error: String
  /// 課題行
  let items: [ManabaAssignmentRow]
}

/// manabaのWebアクセスに関する共通定数・スクリプト（取り込み画面と同期サービスで共有）
enum ManabaWeb {
  /// ログインページ
  static let loginURL = URL(string: "https://cit.manaba.jp/ct/login")!
  /// 未提出課題一覧ページ
  static let assignmentListURL = URL(string: "https://cit.manaba.jp/ct/home_library_query")!
  /// 遷移を許可するホスト接尾辞（manabaドメインに限定）
  static let allowedHostSuffixes = ["manaba.jp"]
  /// PC版表示にするためのデスクトップUser-Agent
  static let desktopUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

  /// ログイン自動入力JS（payload JSON `{uid,pwd,allowLogin}` を引数に取り，
  /// 結果文字列 'login_submitted' / 'login_filled' / 'no_form' を返す）
  static func loginScript(argumentJSON: String) -> String {
    """
    (function(p){
      function setVal(el, v){
        if(!el || v == null || v === '') return false;
        el.focus(); el.value = v;
        el.dispatchEvent(new Event('input', {bubbles:true}));
        el.dispatchEvent(new Event('change', {bubbles:true}));
        return true;
      }
      var uid = document.getElementById('mainuserid')
        || document.querySelector('input[name=userid]');
      var pw = document.querySelector('input[name=password]');
      if (uid && pw) {
        setVal(uid, p.uid);
        setVal(pw, p.pwd);
        if (p.allowLogin) {
          var b = document.getElementById('login')
            || document.querySelector('input[type=submit][name=login]')
            || document.querySelector('form [type=submit]');
          if (b) { b.click(); return 'login_submitted'; }
        }
        return 'login_filled';
      }
      return 'no_form';
    })(\(argumentJSON));
    """
  }
}

/// ログイン画面へ注入する自動入力データ（uid・pwd・自動送信可否）
struct ManabaAutofillPayload: Encodable {
  let uid: String
  let pwd: String
  /// 自動送信を許可するか（1回だけ）
  let allowLogin: Bool
}

/// 取り込み前の課題ドラフト（重複排除キーつき）
struct AssignmentDraft {
  let type: String
  let title: String
  let courseName: String
  let dueDate: Date?
  let startDate: Date?
  let manabaURL: String
  let courseURL: String
  let manabaId: String

  /// SwiftDataの永続モデルを生成する
  func makeAssignment(importedAt: Date) -> Assignment {
    Assignment(
      type: type,
      title: title,
      courseName: courseName,
      dueDate: dueDate,
      startDate: startDate,
      manabaURL: manabaURL,
      courseURL: courseURL,
      manabaId: manabaId,
      importedAt: importedAt
    )
  }
}

/// manaba課題一覧のスクレイパ
enum ManabaAssignmentScraper {

  /// 課題一覧ページに注入し，JSON文字列（ManabaScrapeResult）を返すJavaScript
  static let script = """
  (function(){
    var table = document.querySelector('table.stdlist');
    if (!table) { return JSON.stringify({error:'list_not_found', items:[]}); }
    function txt(el){ return el ? el.textContent.replace(/\\s+/g,' ').trim() : ''; }
    function href(el){ var a = el ? el.querySelector('a') : null; return a ? a.href : ''; }
    var rows = table.querySelectorAll('tr.row0, tr.row1');
    var items = [];
    rows.forEach(function(tr){
      var tds = tr.querySelectorAll('td');
      if (tds.length < 5) return;
      items.push({
        type:     txt(tds[0]),
        title:    txt(tds[1]),
        url:      href(tds[1]),
        course:   txt(tds[2]),
        courseUrl:href(tds[2]),
        start:    txt(tds[3]),
        due:      txt(tds[4])
      });
    });
    return JSON.stringify({error:'', items: items});
  })();
  """
}

/// スクレイプ結果をAssignmentDraftへ変換するマッパー
enum ManabaAssignmentMapper {

  /// manabaの日時文字列のフォーマット（例: 2026-06-24 17:00）
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter
  }()

  /// スクレイプ結果を有効なドラフト配列へ変換する（URL・タイトルが空の行は除外）
  static func makeDrafts(from result: ManabaScrapeResult) -> [AssignmentDraft] {
    result.items.compactMap { row in
      let title = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
      let url = row.url.trimmingCharacters(in: .whitespacesAndNewlines)
      // タイトルもURLも無い行は課題として扱わない
      guard !title.isEmpty, !url.isEmpty else { return nil }

      return AssignmentDraft(
        type: row.type.trimmingCharacters(in: .whitespacesAndNewlines),
        title: title,
        courseName: row.course.trimmingCharacters(in: .whitespacesAndNewlines),
        dueDate: parseDate(row.due),
        startDate: parseDate(row.start),
        manabaURL: url,
        courseURL: row.courseUrl.trimmingCharacters(in: .whitespacesAndNewlines),
        manabaId: extractId(from: url)
      )
    }
  }

  /// 日時文字列をDateへ変換する（空・不正ならnil）
  private static func parseDate(_ text: String) -> Date? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return dateFormatter.date(from: trimmed)
  }

  /// 課題URLからID（末尾の数値列）を取り出す．取り出せない場合はURL全体をキーにする
  private static func extractId(from url: String) -> String {
    // 例: https://cit.manaba.jp/ct/course_1674063_report_1755367 → 1755367
    if let match = url.range(of: "[0-9]+$", options: .regularExpression) {
      return String(url[match])
    }
    return url
  }
}
