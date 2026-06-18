//
//  PortalChangeSyncService.swift
//  CIT-Campus-3D
//
//  ポータル（UNIVERSAL PASSPORT）へ画面を見せずに自動ログインし，「時間割変更」一覧から
//  休講・補講・教室変更を取得して保存する．ログインにOTPが必要なため，TOTPシークレットが
//  登録済みのときだけ実行できる（未登録なら可視の取り込み画面を使う）．
//
//  フロー: 不可視WKWebView → TOTP自動ログイン → ホームで「時間割変更」を開く →
//          各掲示の本文を順に開いてテキスト取得 → PortalChangeParser で解析 → upsert．
//

import Foundation
import Observation
import SwiftData
import UIKit
import WebKit

/// ポータル「時間割変更」のバックグラウンド同期サービス
@MainActor
@Observable
final class PortalChangeSyncService: NSObject, WKNavigationDelegate {

  /// 同期の状態
  enum Status {
    case idle
    case syncing
    case error
  }

  // MARK: - 公開状態

  private(set) var status: Status = .idle
  private(set) var lastSyncDate: Date?
  private(set) var lastErrorMessage: String?
  private(set) var lastImportedCount = 0

  var isSyncing: Bool { status == .syncing }

  // MARK: - 内部状態

  @ObservationIgnored private var webView: WKWebView?
  @ObservationIgnored private var attemptedSSO = false
  @ObservationIgnored private var attemptedLogin = false
  @ObservationIgnored private var attemptedOTP = false
  @ObservationIgnored private var startedBoardFlow = false
  @ObservationIgnored private var timeoutTask: Task<Void, Never>?

  @ObservationIgnored private var credentialStore: PortalCredentialStore?
  @ObservationIgnored private var modelContext: ModelContext?

  /// 本文の開閉を含むため長めのタイムアウト
  private let timeoutSeconds: TimeInterval = 120
  private let lastSyncKey = "portalChange.lastSyncDate"

  override init() {
    super.init()
    lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
  }

  // MARK: - 公開API

  /// 背景同期が可能か（資格情報＋TOTPシークレットが揃っている）
  func canSync(credentialStore: PortalCredentialStore) -> Bool {
    credentialStore.isRegistered && credentialStore.hasTOTPSecret
  }

  /// 前回から指定時間が経っていれば同期する
  func syncIfStale(
    minimumInterval: TimeInterval = 6 * 3600,
    credentialStore: PortalCredentialStore,
    modelContext: ModelContext
  ) {
    if let lastSyncDate, Date().timeIntervalSince(lastSyncDate) < minimumInterval { return }
    sync(credentialStore: credentialStore, modelContext: modelContext)
  }

  /// 今すぐ同期する（TOTP未登録・同期中は何もしない）
  func sync(credentialStore: PortalCredentialStore, modelContext: ModelContext) {
    guard status != .syncing else { return }
    guard canSync(credentialStore: credentialStore), credentialStore.userID != nil else { return }

    self.credentialStore = credentialStore
    self.modelContext = modelContext
    attemptedSSO = false
    attemptedLogin = false
    attemptedOTP = false
    startedBoardFlow = false
    lastErrorMessage = nil
    status = .syncing

    let webView = WKWebView(
      frame: CGRect(x: 0, y: 0, width: 1024, height: 1366),
      configuration: WKWebViewConfiguration()
    )
    webView.customUserAgent = PortalAuth.desktopUserAgent
    webView.navigationDelegate = self
    attachHidden(webView)
    self.webView = webView
    webView.load(URLRequest(url: PortalAuth.portalURL))

    startTimeout()
  }

  // MARK: - WKNavigationDelegate

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in await handleLogin(on: webView) }
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    fail("通信に失敗しました（\(error.localizedDescription)）．")
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    fail("ページを読み込めませんでした（\(error.localizedDescription)）．")
  }

  // MARK: - ログイン

  /// ログイン画面を自動入力で進める．ホームに着いたら一覧取得フローへ移る
  private func handleLogin(on webView: WKWebView) async {
    guard status == .syncing, !startedBoardFlow,
      let credentialStore, let userID = credentialStore.userID
    else { return }

    let payload = PortalAuth.AutofillPayload(
      uid: userID,
      pwd: credentialStore.loadPassword() ?? "",
      otp: credentialStore.currentOTP() ?? "",
      allowSSO: !attemptedSSO,
      allowLogin: !attemptedLogin,
      allowOTP: !attemptedOTP
    )
    guard
      let data = try? JSONEncoder().encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      fail("認証情報の準備に失敗しました．")
      return
    }

    let result = (try? await webView.evaluateJavaScript(
      PortalAuth.autofillScript(argumentJSON: json)
    )) as? String

    switch result {
    case "sso_clicked":
      attemptedSSO = true
    case "login_submitted":
      attemptedLogin = true
    case "otp_submitted":
      attemptedOTP = true
    case "login_filled":
      if attemptedLogin { fail("統合認証へのログインに失敗しました．ID・パスワードを確認してください．") }
    case "otp_filled":
      if attemptedOTP { fail("ワンタイムパスワードの認証に失敗しました．キー・端末時刻を確認してください．") }
    case "no_form":
      // ポータルのホストでフォームが無い＝ログイン済みホーム
      if let host = webView.url?.host, host.hasSuffix("portal.chibatech.ac.jp") {
        startBoardFlow(on: webView)
      }
    default:
      break
    }
  }

  // MARK: - 時間割変更の取得

  /// ホームから「時間割変更」を開き，各本文を順に取得して保存する
  private func startBoardFlow(on webView: WKWebView) {
    guard !startedBoardFlow else { return }
    startedBoardFlow = true

    Task { @MainActor in
      do {
        // 「時間割変更」を開く
        let opened = (try await webView.evaluateJavaScript(
          ClassChangeScraper.openChangeBoardScript
        )) as? String
        guard opened == "opened" else {
          fail("「時間割変更」を開けませんでした．")
          return
        }

        // 一覧の表示を待つ（最大約10秒）
        var ready = false
        for _ in 0..<40 {
          try await Task.sleep(for: .milliseconds(250))
          if status != .syncing { return }
          let state = (try await webView.evaluateJavaScript(
            ClassChangeScraper.boardReadyScript
          )) as? String
          if state == "ready" { ready = true; break }
        }
        guard ready else {
          fail("「時間割変更」の一覧を読み込めませんでした．")
          return
        }

        // 各掲示の本文を順に取得する（callAsyncJavaScript: async/await対応）
        let json = (try await webView.callAsyncJavaScript(
          ClassChangeScraper.scrapeBodiesAsyncScript,
          arguments: [:],
          in: nil,
          contentWorld: .page
        )) as? String

        guard
          let json,
          let data = json.data(using: .utf8),
          let notices = try? JSONDecoder().decode([ScrapedNotice].self, from: data)
        else {
          fail("「時間割変更」の本文を読み取れませんでした．")
          return
        }

        let drafts = notices.compactMap {
          PortalChangeParser.makeDraft(bodyText: $0.body, title: $0.title, postedDate: nil)
        }
        if let modelContext {
          try ClassChangeImporter.upsert(drafts, into: modelContext)
          lastImportedCount = drafts.count
        }
        finishSuccess()
      } catch {
        fail("「時間割変更」の取得に失敗しました（\(error.localizedDescription)）．")
      }
    }
  }

  // MARK: - 終了処理

  private func finishSuccess() {
    let now = Date()
    lastSyncDate = now
    UserDefaults.standard.set(now, forKey: lastSyncKey)
    status = .idle
    teardown()
  }

  private func fail(_ message: String) {
    guard status == .syncing else { return }
    lastErrorMessage = message
    status = .error
    teardown()
  }

  private func teardown() {
    timeoutTask?.cancel()
    timeoutTask = nil
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView = nil
    credentialStore = nil
    modelContext = nil
  }

  private func startTimeout() {
    timeoutTask?.cancel()
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(120))
      guard let self, self.status == .syncing else { return }
      self.fail("同期がタイムアウトしました．時間をおいて再試行してください．")
    }
  }

  /// WebViewをキーウィンドウへ不可視で取り付ける
  private func attachHidden(_ webView: WKWebView) {
    webView.alpha = 0
    webView.isUserInteractionEnabled = false
    guard
      let window = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .flatMap({ $0.windows })
        .first(where: { $0.isKeyWindow })
    else { return }
    window.addSubview(webView)
    window.sendSubviewToBack(webView)
  }
}
