import Testing
import WebKit
@testable import CIT_Campus_3D

@MainActor
struct AttendanceAutofillTests {
  /// 実際のサイトと同じuserid/name=username・keyupで有効化するフォームを使う．
  @Test func fillsActualLoginFieldsAndSubmitsTheirFormOnce() async throws {
    let page = TestPage()
    try await page.load("""
      <form id="unrelated"></form>
      <form id="loginForm" action="/attendance/login" onsubmit="event.preventDefault(); window.submissions = (window.submissions || 0) + 1;">
        <input id="userid" name="username"><input id="password" name="password" type="password">
        <button type="submit" disabled>ログイン</button>
      </form>
      <script>
        document.querySelectorAll('input').forEach(function(field) {
          field.addEventListener('keyup', function() {
            document.querySelector('button').disabled = !(document.getElementById('userid').value && document.getElementById('password').value);
          });
        });
      </script>
      """)
    let payload = #"{"uid":"test-student","pwd":"test+pass'\\word","allowLogin":true,"allowAttend":true}"#
    let script = AttendanceWebView.Coordinator.autofillScript(argumentJSON: payload)
    let first = try await page.webView.evaluateJavaScript(script) as? String
    #expect(first == "login_submitted")
    #expect(try await page.webView.evaluateJavaScript("document.getElementById('userid').value") as? String == "test-student")
    #expect(try await page.webView.evaluateJavaScript("document.getElementById('password').value") as? String == "test+pass'\\word")
    _ = try await page.webView.evaluateJavaScript(script)
    #expect(try await page.webView.evaluateJavaScript("window.submissions") as? Int == 1)
  }

  @Test func attendanceUsesClickHandlerAndIgnoresDisabledButton() async throws {
    let page = TestPage()
    try await page.load("""
      <form id="attendForm" onsubmit="event.preventDefault()">
        <button id="attend" type="button" disabled onclick="window.clicks = (window.clicks || 0) + 1;">出席</button>
      </form>
      """)
    let script = AttendanceWebView.Coordinator.autofillScript(
      argumentJSON: #"{"uid":"test","pwd":"test","allowLogin":true,"allowAttend":true}"#)
    #expect(try await page.webView.evaluateJavaScript(script) as? String == "none")
    _ = try await page.webView.evaluateJavaScript("document.getElementById('attend').disabled = false")
    #expect(try await page.webView.evaluateJavaScript(script) as? String == "attend_submitted")
    _ = try await page.webView.evaluateJavaScript(script)
    #expect(try await page.webView.evaluateJavaScript("window.clicks") as? Int == 1)
  }
}

@MainActor
private final class TestPage: NSObject, WKNavigationDelegate {
  let webView = WKWebView()
  private var continuation: CheckedContinuation<Void, Error>?
  func load(_ html: String) async throws {
    webView.navigationDelegate = self
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      webView.loadHTMLString(html, baseURL: URL(string: "https://attendance.is.chibatech.ac.jp/attendance/login")!)
    }
  }
  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    continuation?.resume(); continuation = nil
  }
  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    continuation?.resume(throwing: error); continuation = nil
  }
  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    continuation?.resume(throwing: error); continuation = nil
  }
}
