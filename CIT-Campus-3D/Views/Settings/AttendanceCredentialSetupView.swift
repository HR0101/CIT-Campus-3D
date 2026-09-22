//
//  AttendanceCredentialSetupView.swift
//  CIT-Campus-3D
//
//  出席システム（attendance.is.chibatech.ac.jp）専用の認証情報を登録する画面．
//  CITポータルとID・パスワードが同じ学生と異なる学生の双方がいるため，
//  「ポータルと同じものを使う」か「専用に登録する」かを切り替えられるようにする．
//

import SwiftUI

/// 出席システム認証情報の登録・管理画面
struct AttendanceCredentialSetupView: View {

  @Environment(PortalCredentialStore.self) private var portalStore
  @Environment(AttendanceCredentialStore.self) private var attendanceStore

  /// ユーザーID入力（専用登録時のみ使用）
  @State private var userID = ""
  /// パスワード入力（専用登録時のみ使用）
  @State private var password = ""

  /// 保存／削除のエラーメッセージ
  @State private var errorMessage: String?
  /// 保存完了の確認表示
  @State private var didSave = false
  /// 削除確認ダイアログ
  @State private var showDeleteConfirm = false

  var body: some View {
    @Bindable var attendanceStore = attendanceStore

    Form {
      Section {
        Toggle("ポータルと同じID・パスワードを使う", isOn: $attendanceStore.useSamePortalCredentials)
      } footer: {
        Text("CITポータルと出席システムのID・パスワードが同じ場合はオンのままにしてください．異なる場合はオフにして，出席システム専用の認証情報を登録します．")
      }

      if attendanceStore.useSamePortalCredentials {
        portalStatusSection
      } else {
        registeredSection
        inputSection
        if attendanceStore.isRegistered {
          deleteSection
        }
      }
    }
    .navigationTitle("出席システム連携")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      // 専用登録済みならユーザーIDを初期表示する（パスワードは安全のため空のまま）
      if let registeredID = attendanceStore.userID, userID.isEmpty {
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
      "専用の認証情報を削除しますか？",
      isPresented: $showDeleteConfirm,
      titleVisibility: .visible
    ) {
      Button("削除する", role: .destructive) { performDelete() }
      Button("キャンセル", role: .cancel) {}
    } message: {
      Text("保存済みの出席システム専用のユーザーID・パスワードを端末から削除します．")
    }
  }

  // MARK: - 「ポータルと同じ」場合の状態表示

  private var portalStatusSection: some View {
    Section {
      if portalStore.isRegistered {
        LabeledContent("使用するユーザーID", value: portalStore.userID ?? "—")
      } else {
        Text("ポータルの認証情報が未登録です．設定の「CITポータル連携」で先に登録してください．")
          .foregroundStyle(.secondary)
      }
    } header: {
      Text("使用中の認証情報")
    } footer: {
      Text("「CITポータル連携」で登録したID・パスワードを，出席の自動チェック・自動ログインにそのまま使用します．")
    }
  }

  // MARK: - 専用登録の状態表示

  @ViewBuilder
  private var registeredSection: some View {
    if attendanceStore.isRegistered {
      Section {
        LabeledContent("ユーザーID", value: attendanceStore.userID ?? "—")
      } header: {
        Text("登録済み")
      } footer: {
        Text("内容を変えるには下のフォームで上書き保存してください．")
      }
    }
  }

  // MARK: - 専用入力フォーム

  private var inputSection: some View {
    Section {
      TextField("ユーザーID（学籍番号など）", text: $userID)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
      SecureField("パスワード", text: $password)

      Button {
        save()
      } label: {
        if didSave {
          Label("保存しました", systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Text(attendanceStore.isRegistered ? "認証情報を更新" : "保存")
        }
      }
      .disabled(userID.isEmpty || password.isEmpty)
    } header: {
      Text("出席システム専用の認証情報")
    } footer: {
      Text("出席システム（attendance.is.chibatech.ac.jp）へのログインにのみ使用します．認証情報はこの端末内にのみ保存します．")
    }
  }

  // MARK: - 削除

  private var deleteSection: some View {
    Section {
      Button("専用の認証情報を削除", role: .destructive) {
        showDeleteConfirm = true
      }
    }
  }

  // MARK: - 操作

  /// 専用の認証情報を保存する
  private func save() {
    do {
      try attendanceStore.save(userID: userID, password: password)
      // 保存後はメモリ上の機密入力を消し，完了表示を一時的に出す
      password = ""
      withAnimation { didSave = true }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  /// 専用の認証情報を削除する
  private func performDelete() {
    do {
      try attendanceStore.deleteAll()
      userID = ""
      password = ""
      didSave = false
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

#Preview {
  NavigationStack {
    AttendanceCredentialSetupView()
      .environment(PortalCredentialStore())
      .environment(AttendanceCredentialStore())
  }
}
