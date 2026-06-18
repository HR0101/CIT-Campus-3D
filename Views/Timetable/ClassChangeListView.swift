//
//  ClassChangeListView.swift
//  CIT-Campus-3D
//
//  ポータルから取り込んだ休講・補講・教室変更を日付順に一覧表示する画面．
//  TOTP登録済みなら「今すぐ取得」で背景同期，未登録なら登録を促す．
//

import SwiftData
import SwiftUI

/// 休講・補講・教室変更の一覧画面
struct ClassChangeListView: View {

  @Environment(\.modelContext) private var modelContext
  @Environment(PortalCredentialStore.self) private var credentialStore
  @Environment(PortalChangeSyncService.self) private var changeSync

  /// 全変更（日付の早い順．日付なしは先頭に来るためグループ化で振り分ける）
  @Query(sort: \ClassChange.date) private var changes: [ClassChange]

  @State private var errorMessage: String?

  /// 日付表示用フォーマッタ
  private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d(E)"
    return formatter
  }()

  /// 今日以降の変更（日付の早い順）
  private var upcoming: [ClassChange] {
    let today = Calendar.current.startOfDay(for: Date())
    return changes
      .filter { if let d = $0.date { return d >= today } else { return false } }
      .sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
  }

  /// 過去・日付なしの変更
  private var others: [ClassChange] {
    let today = Calendar.current.startOfDay(for: Date())
    return changes
      .filter { if let d = $0.date { return d < today } else { return true } }
      .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
  }

  var body: some View {
    VStack(spacing: 0) {
      if changeSync.canSync(credentialStore: credentialStore) {
        syncStatusBar
      }
      Group {
        if changes.isEmpty {
          emptyState
        } else {
          changeList
        }
      }
    }
    .navigationTitle("休講・補講")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        if changeSync.isSyncing {
          ProgressView()
        } else if changeSync.canSync(credentialStore: credentialStore) {
          Button {
            syncNow()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel("ポータルから取得")
        }
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
    .task {
      // CloudKit同期などで生じた重複をまず掃除する
      try? ClassChangeImporter.deduplicate(into: modelContext)
      if changeSync.canSync(credentialStore: credentialStore) {
        changeSync.syncIfStale(
          minimumInterval: 600,
          credentialStore: credentialStore,
          modelContext: modelContext
        )
      }
    }
  }

  // MARK: - 一覧

  private var changeList: some View {
    List {
      if !upcoming.isEmpty {
        Section("これから") {
          ForEach(upcoming) { changeRow($0) }
            .onDelete { deleteChanges(upcoming, at: $0) }
        }
      }
      if !others.isEmpty {
        Section("過去・日付不明") {
          ForEach(others) { changeRow($0) }
            .onDelete { deleteChanges(others, at: $0) }
        }
      }
    }
  }

  private func changeRow(_ change: ClassChange) -> some View {
    HStack(alignment: .top, spacing: 12) {
      // 種別バッジ（休講＝赤・補講＝青・教室変更＝橙）
      Text(change.type.displayName)
        .font(.caption2.bold())
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(color(for: change.type)))
      VStack(alignment: .leading, spacing: 3) {
        Text(change.subjectName.isEmpty ? change.noticeTitle : change.subjectName)
          .font(.subheadline.bold())
          .lineLimit(2)
        HStack(spacing: 10) {
          if let date = change.date {
            Label("\(Self.dateFormatter.string(from: date)) \(change.periodText)", systemImage: "calendar")
          } else {
            Label("日付不明", systemImage: "calendar")
          }
          if !change.room.isEmpty {
            Label("\(change.room)教室", systemImage: "mappin.and.ellipse")
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if !change.teacherName.isEmpty {
          Text(change.teacherName)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 2)
  }

  /// 種別の表示色
  private func color(for type: ClassChangeType) -> Color {
    switch type {
    case .canceled: return .red
    case .supplementary: return .blue
    case .roomChange: return .orange
    case .other: return .gray
    }
  }

  // MARK: - 同期コントロール

  private var syncStatusBar: some View {
    HStack(spacing: 8) {
      switch changeSync.status {
      case .syncing:
        ProgressView().controlSize(.small)
        Text("ポータル同期中…").foregroundStyle(.secondary)
      case .error:
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        Text(changeSync.lastErrorMessage ?? "同期に失敗しました")
          .foregroundStyle(.secondary).lineLimit(2)
        Spacer(minLength: 0)
        Button("再試行") { syncNow() }
      case .idle:
        Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
        Text(lastSyncText).foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 6)
    .background(.ultraThinMaterial)
  }

  private var lastSyncText: String {
    guard let date = changeSync.lastSyncDate else { return "ポータルと未同期です" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d HH:mm"
    return "最終同期 \(formatter.string(from: date))"
  }

  // MARK: - 空状態

  private var emptyState: some View {
    ContentUnavailableView {
      Label("休講・補講はありません", systemImage: "calendar.badge.checkmark")
    } description: {
      if credentialStore.isRegistered && !credentialStore.hasTOTPSecret {
        Text("ポータルの休講・補講を自動取得するには，2段階認証が必要です．設定の「CITポータル連携」でワンタイムパスワードのキーを登録してください．")
      } else if !credentialStore.isRegistered {
        Text("設定の「CITポータル連携」でMARINE ID・パスワード・ワンタイムパスワードのキーを登録すると，休講・補講を自動で取得します．")
      } else {
        Text("「今すぐ取得」を押すと，ポータルの「時間割変更」から休講・補講を取得します．")
      }
    } actions: {
      if changeSync.canSync(credentialStore: credentialStore) {
        Button("今すぐ取得") { syncNow() }
          .buttonStyle(.borderedProminent)
          .disabled(changeSync.isSyncing)
      }
    }
  }

  // MARK: - 操作

  private func syncNow() {
    changeSync.sync(credentialStore: credentialStore, modelContext: modelContext)
  }

  private func deleteChanges(_ source: [ClassChange], at offsets: IndexSet) {
    for index in offsets {
      modelContext.delete(source[index])
    }
    do {
      try modelContext.save()
    } catch {
      errorMessage = "削除に失敗しました（\(error.localizedDescription)）．"
    }
  }
}

#Preview {
  NavigationStack {
    ClassChangeListView()
      .modelContainer(for: ClassChange.self, inMemory: true)
      .environment(PortalCredentialStore())
      .environment(PortalChangeSyncService())
  }
}
