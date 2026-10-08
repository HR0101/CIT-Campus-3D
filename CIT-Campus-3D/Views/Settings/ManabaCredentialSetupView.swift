import SwiftUI

/// manabaで必要なID・パスワードだけを登録する．ポータルのOTP設定は保持する．
struct ManabaCredentialSetupView: View {
  @Environment(PortalCredentialStore.self) private var store
  @State private var userID = ""
  @State private var password = ""
  @State private var didSave = false
  @State private var errorMessage: String?

  var body: some View {
    Form {
      if store.isRegistered {
        Section("登録済み") {
          LabeledContent("ユーザーID", value: store.userID ?? "")
        }
      }
      Section {
        TextField("MARINE ID（学籍番号など）", text: $userID)
          .textContentType(.username)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
        SecureField("manabaのパスワード", text: $password)
          .textContentType(.password)
        Button("ID・パスワードを保存") {
          do {
            try store.saveLoginCredentials(userID: userID, password: password)
            password = ""
            didSave = true
          } catch { errorMessage = error.localizedDescription }
        }
        .disabled(userID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
        if didSave { Text("保存しました").foregroundStyle(.green) }
      } header: {
        Text("manabaのログイン情報")
      } footer: {
        Text("アプリ起動時に課題を自動取得します。ワンタイムパスワードのキーは不要です。ID・パスワードはCITポータルと共通で、登録済みのワンタイムパスワードの設定は保持します。出席システムで共通の認証情報を選んでいる場合も、この情報を使用します。認証情報はこの端末のKeychainに保存します。")
      }
    }
    .navigationTitle("manabaのID・パスワード")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { userID = store.userID ?? "" }
    .onChange(of: password) { _, value in if !value.isEmpty { didSave = false } }
    .alert("保存できませんでした", isPresented: Binding(
      get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
    )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
  }
}
