//
//  PortalImportView.swift
//  CIT-Campus-3D
//
//  大学ポータル（UNIVERSAL PASSPORT）にアプリ内WebViewでログインし，表示中の時間割表を取り込む画面．
//  認証情報はアプリで保存・取得せず，本人が公式サイトに直接ログインする方式（最も安全）．
//  読み取りは表示中ページにJavaScript（PortalTimetableScraper）を注入して行う．
//

import Observation
import SwiftUI
import WebKit

/// ポータル取り込み画面に関する定数
private enum PortalConstants {
  /// 千葉工業大学ポータル（UNIVERSAL PASSPORT）のURL
  static let portalURL = URL(string: "https://portal.chibatech.ac.jp/uprx/")!
  /// 遷移を許可するホストの接尾辞（偽サイトへの誘導を防ぐため大学ドメインに限定）．
  /// 新ドメイン（chibatech.ac.jp）と旧ドメイン（it-chiba.ac.jp）の両方を許可する
  static let allowedHostSuffixes = ["chibatech.ac.jp", "it-chiba.ac.jp"]
  /// PC版ページを表示させるためのデスクトップUser-Agent（UNIPAはモバイル表示が崩れるため）
  static let desktopUserAgent =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}

/// スクレイプ時のエラー
enum PortalScrapeError: LocalizedError {
  case noWebView
  case javaScript(String)
  case invalidResult
  case decode(String)

  var errorDescription: String? {
    switch self {
    case .noWebView:
      return "ページを読み込めていません．"
    case .javaScript(let message):
      return "ページの読み取りに失敗しました（\(message)）．"
    case .invalidResult:
      return "ページから時間割を読み取れませんでした．"
    case .decode(let message):
      return "読み取り結果の解析に失敗しました（\(message)）．"
    }
  }
}

/// WebViewの状態を公開し，スクレイプを起動するコントローラ
@MainActor
@Observable
final class PortalWebController {

  /// 表示中のWebView（representableが設定する．UI状態ではないため観測対象外）
  @ObservationIgnored weak var webView: WKWebView?

  /// 読み込み中か
  var isLoading = false

  /// 現在表示中のホスト（公式サイトに居ることを利用者が確認できるよう表示する）
  var currentHost = ""

  /// 表示中ページから時間割を読み取る
  /// - Parameter completion: 読み取り結果（成功時はScrapeResult）
  func scrape(completion: @escaping (Result<ScrapeResult, PortalScrapeError>) -> Void) {
    guard let webView else {
      completion(.failure(.noWebView))
      return
    }
    webView.evaluateJavaScript(PortalTimetableScraper.script) { value, error in
      if let error {
        completion(.failure(.javaScript(error.localizedDescription)))
        return
      }
      guard let json = value as? String, let data = json.data(using: .utf8) else {
        completion(.failure(.invalidResult))
        return
      }
      do {
        let result = try JSONDecoder().decode(ScrapeResult.self, from: data)
        completion(.success(result))
      } catch {
        completion(.failure(.decode(error.localizedDescription)))
      }
    }
  }
}

/// ログイン画面へ注入する自動入力データ（JSONとしてJSへ渡す．毎回新しいOTPを含む）
private struct PortalAutofillPayload: Encodable {
  /// ユーザーID（MARINE User ID）
  let uid: String
  /// パスワード
  let pwd: String
  /// 現在時刻のワンタイムコード（6桁）
  let otp: String
  /// 統合認証(SSO)入口の自動クリックを許可するか（1回だけ）
  let allowSSO: Bool
  /// Keycloakログインの自動送信を許可するか（1回だけ）
  let allowLogin: Bool
  /// OTPの自動送信を許可するか（1回だけ）
  let allowOTP: Bool
  /// 認証方法の選択（パスキー/ワンタイムパスワード）でOTPを自動選択するか
  let allowMethodSelect: Bool
}

/// ポータルを表示するWebView（大学ドメインに遷移を限定し，登録済みなら自動ログインする）
private struct PortalWebView: UIViewRepresentable {

  let controller: PortalWebController
  /// 認証情報ストア（未登録なら自動入力は行わない）
  let credentialStore: PortalCredentialStore

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.customUserAgent = PortalConstants.desktopUserAgent
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    controller.webView = webView
    webView.load(URLRequest(url: PortalConstants.portalURL))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(controller: controller, credentialStore: credentialStore)
  }

  /// 遷移制限・状態反映・ログイン自動入力を担うデリゲート
  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {

    private let controller: PortalWebController
    private let credentialStore: PortalCredentialStore

    // 自動送信は各ステップ1回だけ許可する（誤入力での再送信ループ＝アカウントロックを防ぐ）
    private var attemptedSSO = false
    private var attemptedLogin = false
    private var attemptedOTP = false
    // 認証方法の選択（パスキー/OTP）のクリック回数（多段選択に備え数回まで許可）
    private var methodSelectCount = 0

    init(controller: PortalWebController, credentialStore: PortalCredentialStore) {
      self.controller = controller
      self.credentialStore = credentialStore
    }

    /// 大学ドメイン以外への遷移を遮断する
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let host = navigationAction.request.url?.host else {
        // ホスト不明（about:blank等）は許可する
        decisionHandler(.allow)
        return
      }
      let isAllowed = PortalConstants.allowedHostSuffixes.contains { host.hasSuffix($0) }
      decisionHandler(isAllowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      controller.isLoading = true
      controller.currentHost = webView.url?.host ?? ""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      controller.isLoading = false
      controller.currentHost = webView.url?.host ?? ""
      runAutofillIfPossible(on: webView)
    }

    func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      controller.isLoading = false
    }

    // MARK: - 自動入力

    /// 登録済みの認証情報でログイン画面を自動入力する（未登録なら何もしない）
    private func runAutofillIfPossible(on webView: WKWebView) {
      guard credentialStore.isRegistered, let userID = credentialStore.userID else { return }

      // OTPは時刻依存のため，注入の直前に毎回生成する
      let payload = PortalAutofillPayload(
        uid: userID,
        pwd: credentialStore.loadPassword() ?? "",
        otp: credentialStore.currentOTP() ?? "",
        allowSSO: !attemptedSSO,
        allowLogin: !attemptedLogin,
        allowOTP: !attemptedOTP,
        allowMethodSelect: methodSelectCount < 3
      )

      guard
        let data = try? JSONEncoder().encode(payload),
        let json = String(data: data, encoding: .utf8)
      else { return }

      webView.evaluateJavaScript(Self.autofillScript(argumentJSON: json)) { result, _ in
        guard let step = result as? String else { return }
        MainActor.assumeIsolated {
          // 自動送信したステップはフラグを立て，次回以降は入力のみ（再送信しない）
          switch step {
          case "sso_clicked": self.attemptedSSO = true
          case "login_submitted": self.attemptedLogin = true
          case "otp_submitted": self.attemptedOTP = true
          case "otp_method_selected": self.methodSelectCount += 1
          default: break
          }
        }
      }
    }

    /// 自動入力JS（ページ種別を判定し，該当欄を埋めて1回だけ送信する）
    private static func autofillScript(argumentJSON: String) -> String {
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
          var otpFilled = setVal(otp, p.otp);
          if (otpFilled) {
            if (p.allowOTP) {
              var ob = document.getElementById('kc-login');
              if (ob) { ob.click(); return 'otp_submitted'; }
            }
            return 'otp_filled';
          }
          // OTPキー未登録で自動入力できない場合は，空のまま送信せず入力欄にフォーカスして手入力を促す
          otp.focus();
          return 'otp_manual';
        }
        // Keycloak: 認証方法の選択（パスキー/ワンタイムパスワード）でワンタイムパスワードを自動選択する．
        // ログイン欄もOTP欄も無い段階で，OTPの選択肢（無ければ「別の方法を試す」）を押す．
        if (p.allowMethodSelect
          && document.location.href.indexOf('/realms/') >= 0
          && !document.getElementById('username') && !document.getElementById('password')) {
          var clickables = Array.prototype.slice.call(
            document.querySelectorAll('a, button, input[type=submit], input[type=button], [role=button], [onclick]')
          );
          var labelOf = function(el){
            return (el.textContent || '') + ' ' + (el.value || '') + ' '
              + (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '');
          };
          var isPasskey = function(t){ return /パスキー|passkey|security ?key|セキュリティ ?キー|webauthn|生体|指紋|顔/i.test(t); };
          var isOtp = function(t){ return /ワンタイム|認証アプリ|認証システム|authenticator|one.?time|\\bOTP\\b/i.test(t); };
          var isAnother = function(t){ return /別の方法|他の方法|try another way|another way/i.test(t); };
          var choice = clickables.find(function(el){ var t = labelOf(el); return isOtp(t) && !isPasskey(t); });
          if (!choice) {
            choice = clickables.find(function(el){ var t = labelOf(el); return isAnother(t) && !isPasskey(t); });
          }
          if (choice) {
            (choice.closest('a,button,[onclick]') || choice).click();
            return 'otp_method_selected';
          }
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
}

/// 取り込んだドラフトをシート表示するためのラッパ
private struct DraftBundle: Identifiable {
  let id = UUID()
  let drafts: [LectureDraft]
}

/// ポータルから時間割を取り込む画面
struct PortalImportView: View {

  /// 保存処理（ファイル取込と同じ後段を共有する）
  let onSave: ([LectureDraft], _ replaceExisting: Bool) -> Void

  /// 「ファイルから取り込む」へ切り替える操作（ワンタイムパスワード未設定者向け．nilならボタン非表示）
  var onUseFileImport: (() -> Void)?

  @Environment(\.dismiss) private var dismiss
  @Environment(PortalCredentialStore.self) private var credentialStore
  @State private var controller = PortalWebController()

  /// 取り込んだドラフト（非nilでプレビューを表示）
  @State private var draftBundle: DraftBundle?

  /// 読み取り中か
  @State private var isScraping = false

  /// エラーメッセージ（非nilでアラート表示）
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        hintBanner
        PortalWebView(controller: controller, credentialStore: credentialStore)
      }
      .navigationTitle("ポータルから取り込み")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            scrape()
          } label: {
            if isScraping {
              ProgressView()
            } else {
              Text("取り込む")
            }
          }
          .disabled(isScraping || controller.isLoading)
        }
      }
      .sheet(item: $draftBundle) { bundle in
        ImportPreviewView(drafts: bundle.drafts) { drafts, replaceExisting in
          onSave(drafts, replaceExisting)
          dismiss()
        }
      }
      .alert(
        "取り込みできませんでした",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  // MARK: - ガイド表示

  private var hintBanner: some View {
    VStack(alignment: .leading, spacing: 6) {
      if credentialStore.isRegistered {
        // 認証情報が登録済み: 自動ログインが働く
        Label {
          Text("登録済みの認証情報で自動ログインします．時間割表のページを開いて「取り込む」を押してください．")
            .font(.caption)
        } icon: {
          Image(systemName: "wand.and.stars")
            .foregroundStyle(.cyan)
        }
        if !credentialStore.hasTOTPSecret {
          // OTPキー未登録: 6桁だけ手入力が必要なことを案内する
          Label {
            Text("ID・パスワードと認証方法の選択までは自動で進みます．ワンタイムパスワードの6桁だけご自身で入力してください．設定の「CITポータル連携」でキーを登録すると，6桁も自動になります．")
              .font(.caption)
          } icon: {
            Image(systemName: "key.horizontal")
              .foregroundStyle(.orange)
          }
        }
      } else {
        // 未登録: 従来どおり手動ログイン＋登録の案内
        Label {
          Text("ポータルにログイン → 時間割表のページを開いて「取り込む」を押してください．")
            .font(.caption)
        } icon: {
          Image(systemName: "info.circle")
            .foregroundStyle(.cyan)
        }

        Label {
          Text("設定の「CITポータル連携」でID・パスワード・ワンタイムパスワードのキーを登録すると，次回から自動ログインできます．")
            .font(.caption)
        } icon: {
          Image(systemName: "key.horizontal")
            .foregroundStyle(.cyan)
        }

        Label {
          Text("2段階認証は「パスキー」ではなく「ワンタイムパスワード」を選んでください．アプリ内ブラウザではパスキーは使えません．")
            .font(.caption)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
        }
      }

      // ワンタイムパスワード未設定者向け: ファイル取り込みへ切り替える導線
      if onUseFileImport != nil {
        Text("ワンタイムパスワードを設定していない場合は，CITポータルから時間割をPDF / Excelで保存し，下のボタンから取り込んでください．")
          .font(.caption2)
          .foregroundStyle(.secondary)
        Button {
          // ファイル取り込みに切り替える（このポータル画面は閉じる）
          onUseFileImport?()
          dismiss()
        } label: {
          Label("ファイル（PDF / Excel）から取り込む", systemImage: "doc")
            .font(.caption.bold())
        }
      }

      if !controller.currentHost.isEmpty {
        Text("接続先: \(controller.currentHost)")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  // MARK: - 取り込み

  /// 表示中ページから時間割を読み取り，プレビューへ渡す
  private func scrape() {
    isScraping = true
    controller.scrape { result in
      isScraping = false
      switch result {
      case .success(let scrapeResult):
        let drafts = PortalTimetableMapper.makeDrafts(
          from: scrapeResult,
          defaultSemester: .current(on: Date())
        )
        if drafts.isEmpty {
          errorMessage = scrapeResult.error == "timetable_not_found"
            ? "このページに時間割表が見つかりませんでした．時間割表（曜日×時限の表）が表示された状態で「取り込む」を押してください．"
            : "時間割を読み取れませんでした．時間割表のページを開いているか確認してください．"
        } else {
          draftBundle = DraftBundle(drafts: drafts)
        }
      case .failure(let error):
        errorMessage = error.errorDescription
      }
    }
  }
}
