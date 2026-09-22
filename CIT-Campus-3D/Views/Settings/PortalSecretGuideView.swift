//
//  PortalSecretGuideView.swift
//  CIT-Campus-3D
//
//  「ワンタイムパスワードのキー（TOTPシークレット）」の取得手順を，ITに不慣れな人でも
//  辿れるように案内する画面．統合認証（Keycloak）のセキュリティ設定をワンタップで開く
//  ボタンと，番号つきの手順・QRから取り出す別法・セキュリティ注意で構成する．
//

import SwiftUI

/// TOTPシークレットの取得手順ガイド
struct PortalSecretGuideView: View {

  /// 外部ブラウザ（Safari）を開くための環境値
  @Environment(\.openURL) private var openURL

  /// 統合認証（Keycloak）のアカウント管理URL（セキュリティ設定の入口）
  private let accountConsoleURL = URL(string: "https://sso.chibatech.ac.jp/realms/marine/account/")!

  var body: some View {
    Form {
      // 概要
      Section {
        Text(
          "二段階認証アプリを「新しく登録」する途中に表示される英数字（base32の鍵）が「キー」です．"
            + "すでに使っているAuthenticatorアプリからは取り出せないため，下の手順で登録操作を行い，"
            + "その途中で表示される鍵を控えます．"
        )
        .font(.callout)
      }

      // ワンタップで開くボタン
      Section {
        Button {
          openURL(accountConsoleURL)
        } label: {
          Label("統合認証のセキュリティ設定を開く", systemImage: "safari")
        }
      } footer: {
        Text("Safariで統合認証（\(accountConsoleURL.host ?? "")）が開きます．ログインして二段階認証の設定に進んでください．")
      }

      // 手順
      Section {
        step(1, "上の「統合認証のセキュリティ設定を開く」を押し，Safariでログインします．")
        step(2, "「アカウントのセキュリティ」→「ログイン方法（Signing in）」を開きます．")
        step(3, "「Authenticatorアプリケーション」の「設定する」を選びます．")
        step(4, "QRコードが表示されたら，その下の「QRコードをスキャンできない場合」（Unable to scan?）を押します．")
        step(5, "表示された英数字（base32の鍵）をコピーします．これが「ワンタイムパスワードのキー」です．")
        step(6, "（任意）今のAuthenticatorアプリも使い続けたい場合は，同じ鍵をそのアプリにも登録します．")
        step(7, "画面の指示どおり6桁コードを1回入力して，設定を確定します．")
        step(8, "このアプリの登録欄に鍵を貼り付け，「OTP生成テスト」で6桁が一致すれば完了です．")
      } header: {
        Text("手順")
      } footer: {
        Text("画面の文言はシステムの更新で多少変わることがあります．「QR」「バーコード」「Authenticator」を目印に探してください．")
      }

      // QRから取り出す別法
      Section {
        Text(
          "QRコードを，認証アプリではなく普通のカメラ／QRリーダーで読み取ると，"
            + "「otpauth://totp/...secret=XXXX...」というURLが表示されます．"
            + "この「secret=」に続く文字列がそのままキーです．"
        )
        .font(.callout)
      } header: {
        Text("別の取り出し方（QRから）")
      }

      // セキュリティ注意
      Section {
        Label {
          Text(
            "このキーはパスワードと同格の機密です．人に見せたり，スクリーンショットをクラウドに残したり"
              + "しないでください．アプリは端末内Keychainに限定保存し，iCloudにも同期しません．"
          )
          .font(.caption)
        } icon: {
          Image(systemName: "exclamationmark.shield.fill")
            .foregroundStyle(.orange)
        }
      } header: {
        Text("セキュリティ上の注意")
      }
    }
    .navigationTitle("キーの取得方法")
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: - 部品

  /// 番号つきの手順行
  private func step(_ number: Int, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(number)")
        .font(.subheadline.bold())
        .foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(Circle().fill(Color.accentColor))
      Text(text)
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 2)
  }
}

#Preview {
  NavigationStack {
    PortalSecretGuideView()
  }
}
