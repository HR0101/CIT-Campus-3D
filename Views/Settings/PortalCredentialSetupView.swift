//
//  PortalCredentialSetupView.swift
//  CIT-Campus-3D
//
//  CITポータル連携の認証情報（ユーザーID・パスワード・TOTPシークレット）を登録する画面．
//  端末内Keychainに保存し，ログイン時の自動入力に用いる．友人アプリと同様に「OTP生成テスト」で
//  入力したキーが正しいか（Authenticatorと同じコードが出るか）を確認できる．
//

import SwiftUI

/// ポータル認証情報の登録・管理画面
struct PortalCredentialSetupView: View {

  @Environment(PortalCredentialStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  // MARK: - 入力状態

  /// ユーザーID入力
  @State private var userID = ""
  /// パスワード入力
  @State private var password = ""
  /// TOTPシークレット入力（base32）
  @State private var totpSecret = ""

  /// OTP生成テストを表示中か
  @State private var isTestingOTP = false
  /// 保存／テストのエラーメッセージ
  @State private var errorMessage: String?
  /// 保存完了の確認表示
  @State private var didSave = false
  /// 削除確認ダイアログ
  @State private var showDeleteConfirm = false

  var body: some View {
    Form {
      registeredSection
      inputSection
      otpTestSection
      securityNoticeSection
      howToGetSecretSection
      if store.isRegistered {
        deleteSection
      }
    }
    .navigationTitle("CITポータル連携")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      // 既登録ならユーザーIDを初期表示する（パスワード・シークレットは安全のため空のまま）
      if let registeredID = store.userID, userID.isEmpty {
        userID = registeredID
      }
    }
    .alert(
      "エラー",
      isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
    .confirmationDialog(
      "認証情報を削除しますか？",
      isPresented: $showDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button("削除する", role: .destructive) { performDelete() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("保存済みのユーザーID・パスワード・ワンタイムパスワードのキーを端末から削除します．")
    }
  }

  // MARK: - 登録状態

  @ViewBuilder
  private var registeredSection: some View {
    if store.isRegistered {
      Section {
        LabeledContent("ユーザーID", value: store.userID ?? "—")
        if let date = store.lastSyncDate {
          LabeledContent("最終同期", value: syncDateText(date))
        }
      } header: {
        Text("登録済み")
      } footer: {
        Text("ログイン時にこの情報を自動入力します．内容を変えるには下のフォームで上書き保存してください．")
      }
    }
  }

  // MARK: - 入力フォーム

  private var inputSection: some View {
    Section {
      TextField("ユーザーID（学籍番号など）", text: $userID)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      SecureField("パスワード", text: $password)
      TextField("ワンタイムパスワードのキー（base32・任意）", text: $totpSecret)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.system(.body, design: .monospaced))

      Button {
        save()
      } label: {
        if didSave {
          Label("保存しました", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Text(store.isRegistered ? "認証情報を更新" : "保存")
        }
      }
      .disabled(userID.isEmpty || password.isEmpty)
    } header: {
      Text("認証情報")
    } footer: {
      Text("ユーザーID・パスワードは必須です．ワンタイムパスワードのキーは任意で，入力するとポータルのOTPも自動入力します（manabaの課題取得はID・パスワードだけで動きます）．キーはスペースやハイフンが含まれていても自動で除去します．")
    }
  }

  // MARK: - OTP生成テスト

  private var otpTestSection: some View {
    Section {
      Button("OTP生成テスト") {
        // 入力中のキーで生成を試し，Authenticatorと同じ6桁が出るか確認する
        testOTP()
      }
      .disabled(totpSecret.isEmpty)

      if isTestingOTP {
        // 30秒ごとに更新される現在のコードを毎秒ライブ表示する
        TimelineView(.periodic(from: .now, by: 1)) { context in
          otpDisplay(at: context.date)
        }
      }
    } header: {
      Text("動作確認")
    } footer: {
      Text("Authenticatorアプリに表示される6桁と一致すれば，キーは正しく登録されています．")
    }
  }

  /// 指定時刻のOTPコードと残り秒を表示する
  @ViewBuilder
  private func otpDisplay(at date: Date) -> some View {
    if let code = try? TOTPGenerator.code(secret: totpSecret, at: date) {
      let remaining = TOTPGenerator.secondsRemaining(at: date)
      HStack {
        Text(code)
          .font(.system(.title, design: .monospaced))
          .bold()
          .monospacedDigit()
        Spacer()
        Text("残り\(remaining)秒")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    } else {
      Text("このキーからはコードを生成できません．base32として正しいか確認してください．")
        .font(.caption)
        .foregroundStyle(.red)
    }
  }

  // MARK: - セキュリティ注意

  private var securityNoticeSection: some View {
    Section {
      Label {
        Text(
          "パスワードとワンタイムパスワードのキーをこの端末内に保存します（iCloudには同期しません）．"
            + "2つの認証要素が同じ端末に揃うため，端末を他人に操作されると不正ログインの恐れがあります．"
            + "リスクを理解した上でご利用ください．"
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

  // MARK: - キーの入手手順

  private var howToGetSecretSection: some View {
    Section {
      Text(
        "「ワンタイムパスワードのキー」は，2段階認証でAuthenticatorアプリを新規登録するときに表示される"
          + "英数字（base32）の文字列です．既に登録済みのAuthenticatorからは取り出せません．"
      )
      .font(.caption)
      Text(
        "登録画面でQRコードの下にある「手動で入力」「QRコードをスキャンできない場合」などから表示される"
          + "キーを，上の入力欄に貼り付けてください．"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      // 統合認証を開くボタンつきの詳しい手順ガイドへ
      NavigationLink {
        PortalSecretGuideView()
      } label: {
        Label("キーの取得手順を見る（統合認証を開く）", systemImage: "list.number")
      }
    } header: {
      Text("キーの入手方法")
    }
  }

  // MARK: - 削除

  private var deleteSection: some View {
    Section {
      Button("認証情報を削除", role: .destructive) {
        showDeleteConfirm = true
      }
    }
  }

  // MARK: - 操作

  /// 認証情報を保存する
  private func save() {
    do {
      try store.save(
        PortalCredentials(userID: userID, password: password, totpSecret: totpSecret)
      )
      // 保存後はメモリ上の機密入力を消し，完了表示を一時的に出す
      password = ""
      totpSecret = ""
      isTestingOTP = false
      withAnimation { didSave = true }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// OTP生成テストを開始する（base32として無効ならエラー表示）
  private func testOTP() {
    do {
      _ = try TOTPGenerator.code(secret: totpSecret)
      withAnimation { isTestingOTP = true }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 認証情報を削除する
  private func performDelete() {
    do {
      try store.deleteAll()
      userID = ""
      password = ""
      totpSecret = ""
      isTestingOTP = false
      didSave = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 最終同期時刻の表示文字列
  private func syncDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
  }
}

#Preview {
  NavigationStack {
    PortalCredentialSetupView()
      .environment(PortalCredentialStore())
  }
}
