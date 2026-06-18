//
//  TOTPGenerator.swift
//  CIT-Campus-3D
//
//  RFC 6238（TOTP）に基づき，Authenticatorアプリと同じ6桁ワンタイムコードを端末内で生成する．
//  ポータルの2段階認証で登録したTOTPシークレット（base32文字列）から，
//  サーバーや外部アプリを使わずに現在時刻のコードを算出する．
//
//  セキュリティ注意:
//  TOTPシークレットは2段階認証の「鍵そのもの」です．保存・取り扱いは PortalCredentialStore 側で
//  端末内Keychain（iCloud非同期）に限定しています．本ファイルは生成ロジックのみを担います．
//

import CryptoKit
import Foundation

/// TOTP生成に関するエラー
enum TOTPError: LocalizedError {
  /// base32として解釈できない文字が含まれている
  case invalidBase32
  /// シークレットが空，または復号後の鍵長が0
  case emptySecret

  var errorDescription: String? {
    switch self {
    case .invalidBase32:
      return "ワンタイムパスワードのキー（base32）に使えない文字が含まれています．"
    case .emptySecret:
      return "ワンタイムパスワードのキーが空です．"
    }
  }
}

/// RFC 6238 準拠のTOTPコード生成器
enum TOTPGenerator {

  // MARK: - 既定パラメータ（一般的なAuthenticator設定に合わせた定数）

  /// 生成する桁数（一般的なAuthenticatorは6桁）
  static let defaultDigits = 6
  /// コードの更新周期（秒）．一般的なAuthenticatorは30秒
  static let defaultPeriod = 30
  /// カウンタを格納するバイト数（RFC 6238はビッグエンディアン8バイト）
  private static let counterByteCount = 8

  // MARK: - 公開API

  /// 指定時刻のTOTPコードを生成する
  /// - Parameters:
  ///   - secret: base32エンコードされたTOTPシークレット（空白・ハイフン・大小文字は許容）
  ///   - date: 基準時刻（既定は現在時刻）
  ///   - digits: 桁数（既定6桁）
  ///   - period: 更新周期秒（既定30秒）
  /// - Returns: ゼロ埋めされた数値文字列（例: "012345"）
  static func code(
    secret: String,
    at date: Date = Date(),
    digits: Int = defaultDigits,
    period: Int = defaultPeriod
  ) throws -> String {
    let key = try decodeBase32(secret)
    guard !key.isEmpty else { throw TOTPError.emptySecret }

    // 時間ステップ（カウンタ）= 経過秒 ÷ 周期．負時刻は想定外なので0で下限を切る
    let timeInterval = max(0, date.timeIntervalSince1970)
    let counter = UInt64(timeInterval) / UInt64(period)

    let hash = hmacSHA1(key: key, counter: counter)
    return truncate(hash: hash, digits: digits)
  }

  /// 現在の周期内でコードが残り何秒有効かを返す（UI表示用）
  /// - Parameters:
  ///   - date: 基準時刻（既定は現在時刻）
  ///   - period: 更新周期秒（既定30秒）
  /// - Returns: 残り有効秒（1〜period）
  static func secondsRemaining(at date: Date = Date(), period: Int = defaultPeriod) -> Int {
    let seconds = Int(max(0, date.timeIntervalSince1970))
    return period - (seconds % period)
  }

  // MARK: - 内部処理

  /// HMAC-SHA1 を計算する（鍵とビッグエンディアン8バイトのカウンタから）
  private static func hmacSHA1(key: Data, counter: UInt64) -> Data {
    // カウンタをビッグエンディアン8バイトに変換する
    var bigEndianCounter = counter.bigEndian
    let counterData = withUnsafeBytes(of: &bigEndianCounter) { Data($0) }

    let symmetricKey = SymmetricKey(data: key)
    let mac = HMAC<Insecure.SHA1>.authenticationCode(for: counterData, using: symmetricKey)
    return Data(mac)
  }

  /// RFC 6238 の動的切り詰めで，ハッシュから指定桁数のコードを取り出す
  private static func truncate(hash: Data, digits: Int) -> String {
    let bytes = [UInt8](hash)
    // 末尾バイトの下位4bitをオフセットとして使う
    let offset = Int(bytes[bytes.count - 1] & 0x0f)
    // オフセット位置から4バイトを取り出し，最上位bitを落として31bitの整数にする
    let binary =
      (UInt32(bytes[offset] & 0x7f) << 24)
      | (UInt32(bytes[offset + 1]) << 16)
      | (UInt32(bytes[offset + 2]) << 8)
      | UInt32(bytes[offset + 3])

    let modulo = UInt32(pow(10.0, Double(digits)))
    let code = binary % modulo
    // 桁数に満たない場合は先頭をゼロ埋めする
    return String(format: "%0\(digits)u", code)
  }

  /// base32（RFC 4648）文字列をデータへデコードする
  /// 空白・ハイフン・パディング（=）は無視し，大文字小文字は区別しない
  private static func decodeBase32(_ input: String) throws -> Data {
    // base32のアルファベット表（A〜Z, 2〜7）
    let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    // 区切り文字を除去し大文字化する（Authenticatorの手動キーは空白区切り表示が多いため）
    let sanitized = input
      .uppercased()
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")
      .replacingOccurrences(of: "=", with: "")

    guard !sanitized.isEmpty else { throw TOTPError.emptySecret }

    // 5bitずつのビット列を組み立て，8bit境界でバイト化する
    var bits = 0
    var value = 0
    var output = Data()

    for character in sanitized {
      guard let index = alphabet.firstIndex(of: character) else {
        throw TOTPError.invalidBase32
      }
      let charValue = alphabet.distance(from: alphabet.startIndex, to: index)
      value = (value << 5) | charValue
      bits += 5
      if bits >= 8 {
        bits -= 8
        output.append(UInt8((value >> bits) & 0xff))
      }
    }

    return output
  }
}
