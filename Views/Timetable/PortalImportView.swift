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

/// ポータルを表示するWebView（大学ドメインに遷移を限定する）
private struct PortalWebView: UIViewRepresentable {

  let controller: PortalWebController

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
    Coordinator(controller: controller)
  }

  /// 遷移制限と状態反映を担うデリゲート
  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate {

    private let controller: PortalWebController

    init(controller: PortalWebController) {
      self.controller = controller
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
    }

    func webView(
      _ webView: WKWebView,
      didFail navigation: WKNavigation!,
      withError error: Error
    ) {
      controller.isLoading = false
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
        PortalWebView(controller: controller)
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
      Label {
        Text("ポータルにログイン → 時間割表のページを開いて「取り込む」を押してください．")
          .font(.caption)
      } icon: {
        Image(systemName: "info.circle")
          .foregroundStyle(.cyan)
      }

      Label {
        Text("2段階認証は「パスキー」ではなく「ワンタイムパスワード」を選んでください．アプリ内ブラウザではパスキーは使えません．")
          .font(.caption)
      } icon: {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
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
