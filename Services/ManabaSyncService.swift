//
//  ManabaSyncService.swift
//  CIT-Campus-3D
//
//  manaba（cit.manaba.jp）へ画面を見せずにバックグラウンドでログインし，未提出課題を取得して保存する．
//  画面表示用の WKWebView を持たず，キーウィンドウに不可視（alpha 0）で取り付けた WKWebView を使って
//  ログイン → 課題一覧へ遷移 → スクレイプ → upsert → 締切リマインダー再予約 までを自動で行う．
//
//  認証情報は PortalCredentialStore（MARINE ID＋パスワード）を再利用する．manabaは2段階認証が無いため
//  ID・パスワードだけで完結する．資格情報が未登録のときは何もしない．
//

import Foundation
import Observation
import SwiftData
import UIKit
import WebKit

/// manabaのバックグラウンド同期サービス
@MainActor
@Observable
final class ManabaSyncService: NSObject, WKNavigationDelegate {

  /// 同期の状態
  enum Status {
    case idle
    case syncing
    case error
  }

  // MARK: - 公開状態

  /// 現在の同期状態
  private(set) var status: Status = .idle
  /// 最終同期日時（成功時に更新．UserDefaultsへ永続化）
  private(set) var lastSyncDate: Date?
  /// 直近のエラーメッセージ
  private(set) var lastErrorMessage: String?
  /// 直近の取り込み件数
  private(set) var lastImportedCount = 0

  /// 同期中か
  var isSyncing: Bool { status == .syncing }

  // MARK: - 内部状態

  /// 不可視のスクレイプ用WebView（同期中のみ保持）
  @ObservationIgnored private var webView: WKWebView?
  /// 自動送信を試みたか（1回だけ）
  @ObservationIgnored private var attemptedLogin = false
  /// 課題一覧へ遷移したか（1回だけ）
  @ObservationIgnored private var navigatedToList = false
  /// スクレイプ済みか
  @ObservationIgnored private var didScrape = false
  /// タイムアウト監視タスク
  @ObservationIgnored private var timeoutTask: Task<Void, Never>?

  // 今回の同期で使う依存（同期中のみ保持）
  @ObservationIgnored private var credentialStore: PortalCredentialStore?
  @ObservationIgnored private var modelContext: ModelContext?
  @ObservationIgnored private var settings: AppSettings?
  @ObservationIgnored private var notifications: NotificationService?

  /// 同期がタイムアウトする秒数
  private let timeoutSeconds: TimeInterval = 45
  /// 最終同期日時のUserDefaultsキー
  private let lastSyncKey = "manaba.lastSyncDate"

  override init() {
    super.init()
    lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
  }

  // MARK: - 公開API

  /// 直近の同期から指定時間が経っていれば同期する（起動時の自動同期などに使う）
  /// - Parameters:
  ///   - minimumInterval: この秒数以内に同期済みなら何もしない（既定1時間）
  func syncIfStale(
    minimumInterval: TimeInterval = 3600,
    credentialStore: PortalCredentialStore,
    modelContext: ModelContext,
    settings: AppSettings,
    notifications: NotificationService
  ) {
    if let lastSyncDate, Date().timeIntervalSince(lastSyncDate) < minimumInterval {
      return
    }
    sync(
      credentialStore: credentialStore,
      modelContext: modelContext,
      settings: settings,
      notifications: notifications
    )
  }

  /// 今すぐ同期する（資格情報未登録・同期中は何もしない）
  func sync(
    credentialStore: PortalCredentialStore,
    modelContext: ModelContext,
    settings: AppSettings,
    notifications: NotificationService
  ) {
    guard status != .syncing else { return }
    // 資格情報が無いとバックグラウンドではログインできない
    guard credentialStore.isRegistered, credentialStore.userID != nil else { return }

    // 依存を保持し，状態を初期化する
    self.credentialStore = credentialStore
    self.modelContext = modelContext
    self.settings = settings
    self.notifications = notifications
    attemptedLogin = false
    navigatedToList = false
    didScrape = false
    lastErrorMessage = nil
    status = .syncing

    // 不可視のWebViewを生成してログインページを読み込む．
    // フォーカスによるソフトキーボードの一瞬表示を防ぐ設定を使う
    let configuration = PortalAuth.makeHeadlessWebViewConfiguration()
    let webView = WKWebView(
      frame: CGRect(x: 0, y: 0, width: 1024, height: 1366),
      configuration: configuration
    )
    webView.customUserAgent = ManabaWeb.desktopUserAgent
    webView.navigationDelegate = self
    attachHidden(webView)
    self.webView = webView
    webView.load(URLRequest(url: ManabaWeb.loginURL))

    startTimeout()
  }

  // MARK: - WKNavigationDelegate

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    handleStep(on: webView)
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

  // MARK: - フロー

  /// ページ読み込み完了ごとに，ログイン→一覧遷移→スクレイプ を進める
  private func handleStep(on webView: WKWebView) {
    guard status == .syncing, let credentialStore, let userID = credentialStore.userID else { return }

    let currentURL = webView.url?.absoluteString ?? ""

    // 課題一覧ページに到達したらスクレイプして保存する
    if currentURL.contains("home_library_query") {
      scrapeAndSave(on: webView)
      return
    }

    // ログイン自動入力（フォームが無ければ 'no_form'）
    let payload = ManabaAutofillPayload(
      uid: userID,
      pwd: credentialStore.loadPassword() ?? "",
      allowLogin: !attemptedLogin
    )
    guard
      let data = try? JSONEncoder().encode(payload),
      let json = String(data: data, encoding: .utf8)
    else {
      fail("認証情報の準備に失敗しました．")
      return
    }

    webView.evaluateJavaScript(ManabaWeb.loginScript(argumentJSON: json)) { result, _ in
      MainActor.assumeIsolated {
        guard self.status == .syncing else { return }
        switch result as? String {
        case "login_submitted":
          self.attemptedLogin = true
        case "no_form":
          // ログイン済み．未遷移なら課題一覧へ一度だけ進む
          if !self.navigatedToList {
            self.navigatedToList = true
            webView.load(URLRequest(url: ManabaWeb.assignmentListURL))
          } else {
            self.fail("課題一覧を開けませんでした．")
          }
        case "login_filled":
          // 送信を試みた後もログイン画面のまま＝ログイン失敗
          if self.attemptedLogin {
            self.fail("manabaへのログインに失敗しました．ID・パスワードを確認してください．")
          }
        default:
          break
        }
      }
    }
  }

  /// 課題一覧をスクレイプして保存し，締切リマインダーを再予約する
  private func scrapeAndSave(on webView: WKWebView) {
    guard !didScrape, let modelContext else { return }
    didScrape = true

    webView.evaluateJavaScript(ManabaAssignmentScraper.script) { value, error in
      MainActor.assumeIsolated {
        guard self.status == .syncing else { return }
        if let error {
          self.fail("課題の読み取りに失敗しました（\(error.localizedDescription)）．")
          return
        }
        guard
          let json = value as? String,
          let data = json.data(using: .utf8),
          let result = try? JSONDecoder().decode(ManabaScrapeResult.self, from: data)
        else {
          self.fail("課題を読み取れませんでした．")
          return
        }

        let drafts = ManabaAssignmentMapper.makeDrafts(from: result)
        do {
          try AssignmentImporter.upsert(drafts, into: modelContext)
          self.lastImportedCount = drafts.count
          self.finishSuccess()
        } catch {
          self.fail("課題の保存に失敗しました（\(error.localizedDescription)）．")
        }
      }
    }
  }

  /// 同期成功で締める（最終同期日時の更新・リマインダー再予約・後片付け）
  private func finishSuccess() {
    let now = Date()
    lastSyncDate = now
    UserDefaults.standard.set(now, forKey: lastSyncKey)

    if let settings, let notifications, let modelContext {
      let all = (try? modelContext.fetch(FetchDescriptor<Assignment>())) ?? []
      notifications.rescheduleAssignmentReminders(assignments: all, settings: settings)
    }

    status = .idle
    teardown()
  }

  /// 失敗で締める
  private func fail(_ message: String) {
    guard status == .syncing else { return }
    lastErrorMessage = message
    status = .error
    teardown()
  }

  /// WebViewと依存を解放する
  private func teardown() {
    timeoutTask?.cancel()
    timeoutTask = nil
    webView?.navigationDelegate = nil
    webView?.stopLoading()
    webView?.removeFromSuperview()
    webView = nil
    credentialStore = nil
    modelContext = nil
    settings = nil
    notifications = nil
  }

  /// タイムアウト監視を開始する
  private func startTimeout() {
    timeoutTask?.cancel()
    timeoutTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(45))
      guard let self, self.status == .syncing else { return }
      self.fail("同期がタイムアウトしました．時間をおいて再試行してください．")
    }
  }

  /// WebViewをキーウィンドウへ不可視で取り付ける（描画・JS実行を確実にするため）
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
