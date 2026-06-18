//
//  PortalAuth.swift
//  CIT-Campus-3D
//
//  ポータル（UNIVERSAL PASSPORT → 統合認証Keycloak）への自動ログインに使う定数と注入スクリプトを集約する．
//  可視の取り込み画面（PortalImportView）と，背景同期（PortalChangeSyncService）の双方で共有する．
//  ログインの実フロー: UNIPA「統合認証」リンク → Keycloak username/password → OTP → SAMLでポータルへ戻る．
//

import Foundation

/// ポータル自動ログインの共有定数・スクリプト
enum PortalAuth {

  /// 千葉工業大学ポータル（UNIVERSAL PASSPORT）のURL
  static let portalURL = URL(string: "https://portal.chibatech.ac.jp/uprx/")!
  /// 遷移を許可するホスト接尾辞（偽サイト誘導防止．新旧ドメイン＋SSOホストを含む）
  static let allowedHostSuffixes = ["chibatech.ac.jp", "it-chiba.ac.jp"]
  /// PC版表示にするためのデスクトップUser-Agent
  static let desktopUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

  /// ログイン画面へ注入する自動入力データ（毎回新しいOTPを含む）
  struct AutofillPayload: Encodable {
    let uid: String
    let pwd: String
    let otp: String
    let allowSSO: Bool
    let allowLogin: Bool
    let allowOTP: Bool
  }

  /// 自動入力JS（ページ種別を判定し，該当欄を埋めて1回だけ送信する）
  /// 返値: 'sso_clicked' / 'login_submitted' / 'otp_submitted' / 'sso_present' /
  ///       'login_filled' / 'otp_filled' / 'unipa_filled' / 'no_form'
  static func autofillScript(argumentJSON: String) -> String {
    """
    (function(p){
      function setVal(el, v){
        if(!el || v == null || v === '') return false;
        el.focus();
        el.value = v;
        el.dispatchEvent(new Event('input', {bubbles:true}));
        el.dispatchEvent(new Event('change', {bubbles:true}));
        return true;
      }
      // Keycloak: ワンタイムコード入力ページ
      var otp = document.getElementById('otp');
      if (otp) {
        setVal(otp, p.otp);
        if (p.allowOTP) {
          var ob = document.getElementById('kc-login');
          if (ob) { ob.click(); return 'otp_submitted'; }
        }
        return 'otp_filled';
      }
      // Keycloak: ユーザー名／パスワード入力ページ
      var u = document.getElementById('username');
      var pw = document.getElementById('password');
      if (u && pw) {
        setVal(u, p.uid);
        setVal(pw, p.pwd);
        if (p.allowLogin) {
          var lb = document.getElementById('kc-login')
            || document.querySelector('#kc-form-login [type=submit]');
          if (lb) { lb.click(); return 'login_submitted'; }
        }
        return 'login_filled';
      }
      // UNIPAポータル: 統合認証(SSO)入口へ進む
      var sso = document.querySelector('a[href*="ShibbolethAuthServlet"]');
      if (sso) {
        if (p.allowSSO) { sso.click(); return 'sso_clicked'; }
        return 'sso_present';
      }
      // UNIPA直接ログインフォーム（フォールバック: 入力のみ・自動送信しない）
      var uid = document.getElementById('loginForm:userId');
      var upw = document.getElementById('loginForm:password');
      if (uid && upw) {
        setVal(uid, p.uid);
        setVal(upw, p.pwd);
        return 'unipa_filled';
      }
      return 'no_form';
    })(\(argumentJSON));
    """
  }
}
