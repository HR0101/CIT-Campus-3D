//
//  AttendanceChecker.swift
//  CIT-Campus-3D
//

import Foundation

enum AttendanceCheckResult {
  case needsAttendance
  case alreadyAttendedOrNotAvailable
  case loginFailed
  case networkError(Error)
}

final class AttendanceChecker {
  private let session: URLSession

  /// 出席システム側の仕様で，正しいID・パスワードでも1回目のログインに失敗することがあるため，
  /// 最大でこの回数までログインを再試行する
  private static let maxLoginAttempts = 10
  /// ログイン再試行の間隔
  private static let retryInterval: Duration = .milliseconds(500)

  init() {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .always
    config.httpShouldSetCookies = true
    self.session = URLSession(configuration: config)
  }

  func checkStatus(roomID: String, userID: String, password: String) async -> AttendanceCheckResult {
    guard let targetUrl = URL(string: "https://attendance.is.chibatech.ac.jp/attendance/class_room/\(roomID)") else {
      return .alreadyAttendedOrNotAvailable
    }

    do {
      let html = try await fetchHTML(from: targetUrl)
      guard isLoginPage(html) else {
        return checkHtmlForAttendance(html)
      }

      // ログインページにリダイレクトされた場合．最大maxLoginAttempts回まで再試行する
      guard
        await loginWithRetry(targetUrl: targetUrl, firstPageHTML: html, userID: userID, password: password)
      else {
        return .loginFailed
      }

      // ログイン後にもう一度対象ページへ
      let html2 = try await fetchHTML(from: targetUrl)
      return checkHtmlForAttendance(html2)
    } catch {
      return .networkError(error)
    }
  }

  // MARK: - ログイン（リトライあり）

  /// ログインページに対して最大`maxLoginAttempts`回までログインを試みる．
  /// 失敗して再びログインページへ戻された場合は，新しいCSRFトークンを取り直してから再送信する．
  private func loginWithRetry(
    targetUrl: URL, firstPageHTML: String, userID: String, password: String
  ) async -> Bool {
    var loginPageHTML = firstPageHTML

    for attempt in 1...Self.maxLoginAttempts {
      guard let csrf = extractCSRF(from: loginPageHTML) else { return false }

      do {
        try await submitLogin(csrf: csrf, userID: userID, password: password)
        let resultHTML = try await fetchHTML(from: targetUrl)
        if !isLoginPage(resultHTML) {
          return true
        }
        loginPageHTML = resultHTML
      } catch {
        // 通信エラーは一時的な可能性があるため，リトライを続ける
      }

      if attempt < Self.maxLoginAttempts {
        try? await Task.sleep(for: Self.retryInterval)
      }
    }
    return false
  }

  private func submitLogin(csrf: String, userID: String, password: String) async throws {
    guard let loginUrl = URL(string: "https://attendance.is.chibatech.ac.jp/attendance/login") else {
      throw URLError(.badURL)
    }
    var request = URLRequest(url: loginUrl)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "username", value: userID),
      URLQueryItem(name: "password", value: password),
      URLQueryItem(name: "_csrf", value: csrf),
    ]
    request.httpBody = components.query?.data(using: .utf8)

    _ = try await session.data(for: request)
  }

  // MARK: - HTML判定

  private func fetchHTML(from url: URL) async throws -> String {
    let (data, _) = try await session.data(from: url)
    return String(decoding: data, as: UTF8.self)
  }

  /// ログインフォームのページか（未ログイン，またはログイン失敗で戻された状態）
  private func isLoginPage(_ html: String) -> Bool {
    html.contains("name=\"_csrf\"") && html.contains("name=\"password\"")
  }

  private func extractCSRF(from html: String) -> String? {
    let pattern = "name=\"_csrf\"[^>]*?value=\"([^\"]+)\""
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
    if let match = regex.firstMatch(in: html, options: [], range: nsRange) {
      if let range = Range(match.range(at: 1), in: html) {
        return String(html[range])
      }
    }
    return nil
  }

  private func checkHtmlForAttendance(_ html: String) -> AttendanceCheckResult {
    if html.contains("id=\"attend\"") {
      return .needsAttendance
    } else {
      return .alreadyAttendedOrNotAvailable
    }
  }
}
