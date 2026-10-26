//
//  AttendanceWebView.swift
//  CIT-Campus-3D
//

import SwiftUI
import WebKit

/// 表示するURLとシートの表示状態を一緒に管理する．
struct AttendanceDestination: Identifiable {
  let id = UUID()
  let url: URL
}

/// 出席システムのログイン画面へ注入する自動入力データ（JSONとしてJSへ渡す）．
/// 文字列内挿ではなくJSON経由にすることで，パスワードに含まれるクォートや
/// バックスラッシュがあってもJSの構文を壊さないようにする．
private struct AttendanceAutofillPayload: Encodable {
  let uid: String
  let pwd: String
  /// ログインフォームの自動送信を許可するか（1回のみ）
  let allowLogin: Bool
  /// 出席フォームの自動送信を許可するか（1回のみ）
  let allowAttend: Bool
}

struct AttendanceWebView: UIViewRepresentable {
  let url: URL
  /// 出席システムへのログインに使うユーザーID（呼び出し元が解決済みのものを渡す）
  let userID: String
  /// 出席システムへのログインに使うパスワード
  let password: String
  @Binding var isLoading: Bool
  @Binding var loadError: String?

  func makeUIView(context: Context) -> WKWebView {
    let prefs = WKWebpagePreferences()
    prefs.allowsContentJavaScript = true
    let config = WKWebViewConfiguration()
    config.defaultWebpagePreferences = prefs

    let webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = context.coordinator
    webView.load(URLRequest(url: url, timeoutInterval: 30))
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {
    // SwiftUIの再描画でログインやリダイレクトを中断しない．
    context.coordinator.parent = self
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  class Coordinator: NSObject, WKNavigationDelegate {
    var parent: AttendanceWebView
    /// ログイン試行回数．出席システム側の仕様で1回目のログインが失敗することがあるため，
    /// ログインページへ戻されるたびに，最大maxLoginAttempts回まで自動で再送信する
    var loginAttemptCount = 0
    var hasClickedAttend = false

    /// ログインの最大再試行回数
    private static let maxLoginAttempts = 10

    init(_ parent: AttendanceWebView) {
      self.parent = parent
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      parent.isLoading = true
      parent.loadError = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      handleFailure(error)
    }

    private func handleFailure(_ error: Error) {
      guard (error as NSError).code != NSURLErrorCancelled else { return }
      parent.isLoading = false
      parent.loadError = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      parent.isLoading = false
      parent.loadError = "ページの表示が中断されました。再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      parent.isLoading = false
      // 出席サイト以外へ遷移した場合は認証情報を渡さない．
      guard webView.url?.scheme == "https",
        webView.url?.host == "attendance.is.chibatech.ac.jp" else { return }
      // 認証情報を自動入力（JSONエンコードしてJSへ渡す）
      let payload = AttendanceAutofillPayload(
        uid: parent.userID,
        pwd: parent.password,
        allowLogin: loginAttemptCount < Self.maxLoginAttempts,
        allowAttend: !hasClickedAttend
      )
      guard
        let data = try? JSONEncoder().encode(payload),
        let json = String(data: data, encoding: .utf8)
      else {
        return
      }

      webView.evaluateJavaScript(Self.autofillScript(argumentJSON: json)) { [weak self] result, error in
        switch result as? String {
        case "login_submitted":
          self?.loginAttemptCount += 1
        case "attend_submitted":
          self?.hasClickedAttend = true
        default:
          break
        }
        if let error = error {
          print("Attendance automation JS error: \(error)")
        }
      }
    }

    /// 自動入力JS（ログイン・出席のそれぞれにつき1回だけ送信する）．
    /// 引数はJSONそのものをJSリテラルとしてパースさせるため，文字列内挿によるJS構文破壊が起きない．
    static func autofillScript(argumentJSON: String) -> String {
      """
      (function(p) {
        function fill(field, value) {
          field.value = value;
          field.dispatchEvent(new Event('input', {bubbles: true}));
          field.dispatchEvent(new Event('change', {bubbles: true}));
          // 出席サイトはkeyupでログインボタンのdisabledを解除する．
          field.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true}));
        }
        if (p.allowLogin) {
          var userField = document.querySelector('input[name="username"]')
            || document.getElementById('userid') || document.getElementById('username');
          var passField = document.querySelector('input[name="password"]')
            || document.getElementById('password');
          if (userField && passField && p.uid && p.pwd) {
            var loginForm = userField.form;
            if (!loginForm || passField.form !== loginForm
                || new URL(loginForm.action, location.href).origin !== location.origin) return "none";
            if (loginForm.dataset.citSubmitted) return "none";
            fill(userField, p.uid);
            fill(passField, p.pwd);
            var loginButton = loginForm.querySelector('button[type="submit"], input[type="submit"]');
            if (loginButton && loginButton.disabled) return "login_disabled";
            if (!loginForm.checkValidity()) return "none";
            loginForm.dataset.citSubmitted = 'true';
            if (loginButton) loginButton.click();
            else loginForm.requestSubmit();
            return "login_submitted";
          }
        }

        // ボタンのクリック処理（位置情報取得など）とフォーム検証を通す．
        if (p.allowAttend) {
          var attendButton = document.getElementById('attend');
          var attendForm = document.getElementById('attendForm');
          if (attendButton && attendForm && !attendButton.disabled
              && attendButton.getAttribute('aria-disabled') !== 'true'
              && !attendButton.dataset.citClicked
              && new URL(attendForm.action, location.href).origin === location.origin) {
            attendButton.dataset.citClicked = 'true';
            attendButton.click();
            return "attend_submitted";
          }
        }

        return "none";
      })(\(argumentJSON));
      """
    }
  }
}

struct AttendanceSheetView: View {
  let url: URL
  @Environment(PortalCredentialStore.self) private var portalStore
  @Environment(AttendanceCredentialStore.self) private var attendanceStore
  @Environment(\.dismiss) private var dismiss
  @State private var isLoading = true
  @State private var loadError: String?
  @State private var reloadID = UUID()

  /// 実際に使う出席システムのユーザーID（「ポータルと同じ」設定なら，ポータルの認証情報を使う）
  private var userID: String? {
    attendanceStore.effectiveUserID(portalStore: portalStore)
  }

  /// 実際に使う出席システムのパスワード
  private var password: String? {
    attendanceStore.effectivePassword(portalStore: portalStore)
  }

  var body: some View {
    NavigationStack {
      Group {
        if let userID, let password {
          AttendanceWebView(
            url: url, userID: userID, password: password,
            isLoading: $isLoading, loadError: $loadError
          )
          .id(reloadID)
          .overlay {
            if let loadError {
              ContentUnavailableView {
                Label("出席システムを読み込めません", systemImage: "wifi.exclamationmark")
              } description: {
                Text(loadError)
              } actions: {
                Button("再読み込み") {
                  self.loadError = nil
                  isLoading = true
                  reloadID = UUID()
                }
              }
              .background(.background)
            } else if isLoading {
              ProgressView("出席システムを読み込み中…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
            }
          }
        } else {
          unregisteredNotice
        }
      }
      .navigationTitle("出席システム")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("閉じる") {
            dismiss()
          }
        }
      }
    }
  }

  /// ID・パスワード未登録のときの案内（空欄のまま自動ログインが失敗するのを防ぐ）
  private var unregisteredNotice: some View {
    ContentUnavailableView {
      Label("ID・パスワードが未登録です", systemImage: "key.slash")
    } description: {
      Text("出席を自動で行うには、ユーザーID・パスワードを登録してください。")
    } actions: {
      NavigationLink("出席のID・パスワードを登録") {
        AttendanceCredentialSetupView()
      }
      .buttonStyle(.borderedProminent)
    }
  }
}
