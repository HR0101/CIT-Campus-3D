//
//  ClassChangeScraper.swift
//  CIT-Campus-3D
//
//  ポータルの「時間割変更」一覧を開き，各掲示（休講・補講・教室変更のお知らせ）の本文を順に開いて
//  本文テキストを集めるためのJavaScript．本文の解析は PortalChangeParser が行う．
//
//  注意: 本文を1件ずつクリックで開いて戻る逐次処理のため，PrimeFacesのajax完了をポーリングで待つ．
//  WKWebViewの callAsyncJavaScript（async/await対応）で実行する想定．
//

import Foundation

/// スクレイプした掲示1件（件名と本文テキスト）
struct ScrapedNotice: Decodable {
  let title: String
  let body: String
}

/// 時間割変更スクレイパのスクリプト群
enum ClassChangeScraper {

  /// ポータルのホームから「時間割変更」を開くJS（同期evaluateJavaScript用）
  /// 返値: 'opened'（クリックした） / 'not_found'
  static let openChangeBoardScript = """
  (function(){
    var nodes = Array.prototype.slice.call(document.querySelectorAll('a,span,button,div'));
    var target = nodes.find(function(e){
      var label = e.getAttribute && e.getAttribute('aria-label');
      var text = (e.textContent || '').trim();
      return (label && label.indexOf('時間割変更') >= 0) || text === '時間割変更';
    });
    if (target) {
      var clickable = target.closest('a,button,[onclick]') || target;
      clickable.click();
      return 'opened';
    }
    return 'not_found';
  })();
  """

  /// 「時間割変更」一覧が表示されているか確認するJS
  /// 返値: 'ready'（休講・補講の掲示が見える） / 'waiting'
  static let boardReadyScript = """
  (function(){
    var links = Array.prototype.slice.call(document.querySelectorAll('a.ui-commandlink'))
      .filter(function(a){ return /(休講|補講|教室変更)のお知らせ/.test(a.textContent); });
    return links.length > 0 ? 'ready' : 'waiting';
  })();
  """

  /// 一覧の各掲示本文を順に開いて集める非同期JS（callAsyncJavaScript用）
  /// 返値: JSON文字列（ScrapedNotice配列）
  static let scrapeBodiesAsyncScript = """
  const sleep = function(ms){ return new Promise(function(r){ setTimeout(r, ms); }); };
  function noticeLinks(){
    return Array.prototype.slice.call(document.querySelectorAll('a.ui-commandlink'))
      .filter(function(a){ return /(休講|補講|教室変更)のお知らせ/.test(a.textContent); });
  }
  function isDetail(){
    var t = document.body.innerText || '';
    return /科目名|日\\s*時|教\\s*室/.test(t);
  }
  // 件名で同定する（クリックでIDが振り直されるため）
  var titles = noticeLinks().map(function(a){ return a.textContent.trim(); });
  // 重複件名は1回だけ扱う
  var seen = {};
  titles = titles.filter(function(t){ if (seen[t]) return false; seen[t] = true; return true; });

  var results = [];
  for (var i = 0; i < titles.length; i++) {
    var title = titles[i];
    var link = noticeLinks().find(function(a){ return a.textContent.trim() === title; });
    if (!link) { results.push({ title: title, body: '' }); continue; }
    link.click();
    // 本文の読み込み完了を待つ（最大約9秒）
    var body = '';
    for (var w = 0; w < 60; w++) {
      await sleep(150);
      if (isDetail()) { body = document.body.innerText; break; }
    }
    results.push({ title: title, body: body });
    // 一覧へ戻る
    var back = Array.prototype.slice.call(document.querySelectorAll('a,button,input,span'))
      .find(function(e){
        var s = (e.textContent || e.value || '').replace(/\\s/g, '');
        return s === '戻る' || s === '一覧へ戻る' || s === '一覧に戻る';
      });
    if (back) {
      var clickable = back.closest('a,button,[onclick]') || back;
      clickable.click();
    }
    // 一覧の再表示を待つ（最大約9秒）
    for (var w2 = 0; w2 < 60; w2++) {
      await sleep(150);
      if (noticeLinks().length > 0 && !isDetail()) break;
    }
  }
  return JSON.stringify(results);
  """
}
