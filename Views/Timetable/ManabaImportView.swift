//
//  ManabaImportView.swift
//  CIT-Campus-3D
//
//  manaba（cit.manaba.jp）にアプリ内WebViewで自動ログインし，未提出課題一覧を取り込む画面．
//  認証情報（MARINE ID・パスワード）はポータルと共通の PortalCredentialStore を再利用する．
//  manabaは2段階認証が無いため，ID・パスワードだけで自動ログインできる．
//

import Observation
import SwiftUI
import WebKit

/// manaba課題取り込みのエラー
enum ManabaScrapeError: LocalizedError {
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
      return "ページから課題を読み取れませんでした．"
    case .decode(let message):
      return "読み取り結果の解析に失敗しました（\(message)）．"
    }
  }
}

/// WebViewの状態を公開し，課題一覧のスクレイプを起動するコントローラ
@MainActor
@Observable
final class ManabaWebController {

  /// 表示中のWebView（UI状態ではないため観測対象外）
  @ObservationIgnored weak var webView: WKWebView?

  /// 読み込み中か
  var isLoading = false

  /// 現在表示中のホスト
  var currentHost = ""

  /// 表示中ページから課題一覧を読み取る
  func scrape(completion: @escaping (Result<ManabaScrapeResult, ManabaScrapeError>) -> Void) {
    guard let webView else {
      completion(.failure(.noWebView))
      return
    }
    webView.evaluateJavaScript(ManabaAssignmentScraper.script) { value, error in
      if let error {
        completion(.failure(.javaScript(error.localizedDescription)))
        return
      }
      guard let json = value as? String, let data = json.data(using: .utf8) else {
        completion(.failure(.invalidResult))
        return
      }
      do {
        let result = try JSONDecoder().decode(ManabaScrapeResult.self, from: data)
        completion(.success(result))
      } catch {
        completion(.failure(.decode(error.localizedDescription)))
      }
    }
  }
}

/// manabaを表示するWebView（ドメイン限定・自動ログイン・課題一覧への自動遷移）
private struct ManabaWebView: UIViewRepresentable {

  let controller: ManabaWebController
  let credentialStore: PortalCredentialStore

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.customUserAgent = ManabaWeb.desktopUserAgent
    webView.navigationDelegate = context.coordinator
    webView.allowsBackForwardNavigationGestures = true
    controller.webView = webView
    webView.load(URLRequest(url: ManabaWeb.loginURL))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(controller: controller, credentialStore: credentialStore)
  }

  /// 遷移制限・状態反映・自動ログイン・課題一覧への自動遷移を担うデリゲート
  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {

    private let controller: ManabaWebController
    private let credentialStore: PortalCredentialStore

    // 自動送信は1回だけ・課題一覧への自動遷移も1回だけ
    private var attemptedLogin = false
    private var navigatedToList = false

    init(controller: ManabaWebController, credentialStore: PortalCredentialStore) {
      self.controller = controller
      self.credentialStore = credentialStore
    }

    /// manabaドメイン以外への遷移を遮断する
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let host = navigationAction.request.url?.host else {
        decisionHandler(.allow)
        return
      }
      let isAllowed = ManabaWeb.allowedHostSuffixes.contains { host.hasSuffix($0) }
      decisionHandler(isAllowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
      controller.isLoading = true
      controller.currentHost = webView.url?.host ?? ""
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      controller.isLoading = false
      controller.currentHost = webView.url?.host ?? ""
      handleAutoFlow(on: webView)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      controller.isLoading = false
    }

    // MARK: - 自動ログイン＆遷移

    /// ログイン画面なら自動入力，ログイン済みなら課題一覧へ自動遷移する
    private func handleAutoFlow(on webView: WKWebView) {
      guard credentialStore.isRegistered, let userID = credentialStore.userID else { return }

      let payload = ManabaAutofillPayload(
        uid: userID,
        pwd: credentialStore.loadPassword() ?? "",
        allowLogin: !attemptedLogin
      )
      guard
        let data = try? JSONEncoder().encode(payload),
        let json = String(data: data, encoding: .utf8)
      else { return }

      let currentURL = webView.url?.absoluteString ?? ""

      webView.evaluateJavaScript(ManabaWeb.loginScript(argumentJSON: json)) { result, _ in
        guard let step = result as? String else { return }
        MainActor.assumeIsolated {
          switch step {
          case "login_submitted":
            self.attemptedLogin = true
          case "no_form":
            // ログインフォームが無い＝ログイン済み．未取得なら課題一覧へ一度だけ遷移する
            if !self.navigatedToList,
              !currentURL.contains("home_library_query") {
              self.navigatedToList = true
              webView.load(URLRequest(url: ManabaWeb.assignmentListURL))
            }
          default:
            // 'login_filled'（ログイン画面のまま）等は何もしない
            break
          }
        }
      }
    }
  }
}

/// 取り込んだ課題ドラフトをシート表示するためのラッパ
private struct AssignmentDraftBundle: Identifiable {
  let id = UUID()
  let drafts: [AssignmentDraft]
}

/// manabaから課題を取り込む画面
struct ManabaImportView: View {

  /// 保存処理（upsert＋通知再予約は呼び出し側で行う）
  let onSave: ([AssignmentDraft]) -> Void

  @Environment(\.dismiss) private var dismiss
  @Environment(PortalCredentialStore.self) private var credentialStore
  @State private var controller = ManabaWebController()

  /// 取り込んだドラフト（非nilでプレビュー表示）
  @State private var draftBundle: AssignmentDraftBundle?

  /// 読み取り中か
  @State private var isScraping = false

  /// エラーメッセージ（非nilでアラート）
  @State private var errorMessage: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        hintBanner
        ManabaWebView(controller: controller, credentialStore: credentialStore)
      }
      .navigationTitle("manabaから課題を取り込み")
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
        AssignmentImportPreviewView(drafts: bundle.drafts) { drafts in
          onSave(drafts)
          dismiss()
        }
      }
      .alert(
        "取り込みできませんでした",
        isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
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
        Label {
          Text("登録済みの認証情報で自動ログインし，未提出課題の一覧を開きます．一覧が表示されたら「取り込む」を押してください．")
            .font(.caption)
        } icon: {
          Image(systemName: "wand.and.stars").foregroundStyle(.cyan)
        }
      } else {
        Label {
          Text("設定の「CITポータル連携」でMARINE ID・パスワードを登録すると，manabaにも自動ログインできます．未登録の場合は手動でログインしてください．")
            .font(.caption)
        } icon: {
          Image(systemName: "key.horizontal").foregroundStyle(.cyan)
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

  /// 表示中ページから課題一覧を読み取り，プレビューへ渡す
  private func scrape() {
    isScraping = true
    controller.scrape { result in
      isScraping = false
      switch result {
      case .success(let scrapeResult):
        let drafts = ManabaAssignmentMapper.makeDrafts(from: scrapeResult)
        if drafts.isEmpty {
          errorMessage = scrapeResult.error == "list_not_found"
            ? "このページに課題一覧が見つかりませんでした．「未提出課題」の一覧が表示された状態で「取り込む」を押してください．"
            : "課題を読み取れませんでした．未提出課題の一覧ページを開いているか確認してください．"
        } else {
          draftBundle = AssignmentDraftBundle(drafts: drafts)
        }
      case .failure(let error):
        errorMessage = error.errorDescription
      }
    }
  }
}

/// 取り込む課題の確認プレビュー
struct AssignmentImportPreviewView: View {

  let drafts: [AssignmentDraft]
  let onConfirm: ([AssignmentDraft]) -> Void

  @Environment(\.dismiss) private var dismiss

  /// 締切表示用フォーマッタ
  private static let dueFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d(E) HH:mm"
    return formatter
  }()

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(drafts, id: \.manabaURL) { draft in
            VStack(alignment: .leading, spacing: 4) {
              Text(draft.title)
                .font(.headline)
              HStack(spacing: 12) {
                if !draft.type.isEmpty {
                  Label(draft.type, systemImage: "tag")
                }
                if !draft.courseName.isEmpty {
                  Label(draft.courseName, systemImage: "book")
                }
              }
              .font(.caption)
              .foregroundStyle(.secondary)
              if let due = draft.dueDate {
                Label("締切 \(Self.dueFormatter.string(from: due))", systemImage: "clock.badge.exclamationmark")
                  .font(.caption)
                  .foregroundStyle(.orange)
              }
            }
            .padding(.vertical, 2)
          }
        } header: {
          Text("\(drafts.count)件の課題")
        } footer: {
          Text("既に取り込み済みの課題は重複せず，締切などの内容だけ最新に更新されます．")
        }
      }
      .navigationTitle("課題の取り込み")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("\(drafts.count)件を取り込む") {
            onConfirm(drafts)
            dismiss()
          }
        }
      }
    }
  }
}
