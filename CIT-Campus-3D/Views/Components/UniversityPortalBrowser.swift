import SafariServices
import SwiftUI

/// 大学サイト自身のログイン用。パスキーはSafariServicesに任せ、
/// アプリから認証情報・Cookie・ページ内容を取得しない。
struct UniversityPortalBrowser: UIViewControllerRepresentable {
  let url: URL
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    let browser = SFSafariViewController(url: url, configuration: configuration)
    browser.dismissButtonStyle = .done
    browser.delegate = context.coordinator
    return browser
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator { dismiss() }
  }

  final class Coordinator: NSObject, SFSafariViewControllerDelegate {
    private let onFinish: () -> Void

    init(onFinish: @escaping () -> Void) {
      self.onFinish = onFinish
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
      onFinish()
    }
  }
}
