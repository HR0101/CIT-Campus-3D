//
//  AssignmentListView.swift
//  CIT-Campus-3D
//
//  manabaから取り込んだ課題を未提出・完了・期限切れの順に一覧表示する画面．
//  manaba自動ログイン取り込み・スワイプでの完了／削除・締切リマインダーの再予約を行う．
//

import SwiftData
import SwiftUI
import UIKit

/// 課題一覧画面
struct AssignmentListView: View {

  @Environment(\.modelContext) private var modelContext
  @Environment(AppSettings.self) private var settings
  @Environment(NotificationService.self) private var notifications
  @Environment(PortalCredentialStore.self) private var credentialStore
  @Environment(ManabaSyncService.self) private var manabaSync
  @Environment(\.openURL) private var openURL

  /// 全課題（締切の早い順．締切なしは先頭に来るためグループ化で振り分ける）
  @Query(sort: \Assignment.dueDate) private var assignments: [Assignment]

  /// manaba取り込み画面の表示フラグ
  @State private var isShowingManabaImport = false

  /// エラーアラート
  @State private var errorMessage: String?

  /// 締切表示用フォーマッタ
  private static let dueFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d(E) HH:mm"
    return formatter
  }()

  /// 未完了の課題
  private var activeAssignments: [Assignment] {
    assignments.filter { !$0.isDone }
  }

  /// 期限切れ（未完了・締切が過去）
  private var overdue: [Assignment] {
    activeAssignments.filter { $0.isOverdue() }.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
  }

  /// 未提出（期限内・期限なし）．締切が近い順で，期限なしは末尾に置く．
  private var pending: [Assignment] {
    let now = Date()
    return activeAssignments
      .filter { !$0.isOverdue(from: now) }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }

  /// 完了済みは締切を過ぎても「完了」に表示する．
  private var completed: [Assignment] {
    assignments.filter { $0.isDone }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }

  var body: some View {
    VStack(spacing: 0) {
      if credentialStore.isRegistered {
        syncStatusBar
      }
      assignmentReminderStatusBar
      Group {
        if assignments.isEmpty {
          emptyState
        } else {
          assignmentList
        }
      }
    }
    .navigationTitle("課題")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        NavigationLink("ID・パスワード") { ManabaCredentialSetupView() }
      }
      ToolbarItem(placement: .primaryAction) {
        syncToolbarControl
      }
    }
    .fullScreenCover(isPresented: $isShowingManabaImport) {
      ManabaImportView { drafts in
        importAssignments(drafts)
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
      // CloudKit同期などで生じた重複課題をまず掃除する
      try? AssignmentImporter.deduplicate(into: modelContext)
      // 通知許可状態を反映し，締切リマインダーを最新化する
      await notifications.refreshAuthorizationStatus()
      if settings.enableAssignmentReminder && notifications.authorizationStatus == .notDetermined {
        await notifications.requestAuthorization()
      }
      rescheduleReminders()
      // 画面を開いたとき，前回同期から5分以上空いていれば自動で同期する
      if credentialStore.isRegistered {
        manabaSync.syncIfStale(
          minimumInterval: 300,
          credentialStore: credentialStore,
          modelContext: modelContext,
          settings: settings,
          notifications: notifications
        )
      }
    }
  }

  // MARK: - 同期コントロール

  /// ツールバーの同期ボタン（登録済み＝今すぐ同期メニュー／未登録＝手動取り込み）
  @ViewBuilder
  private var syncToolbarControl: some View {
    if manabaSync.isSyncing {
      ProgressView()
    } else if credentialStore.isRegistered {
      Menu {
        Button {
          syncNow()
        } label: {
          Label("今すぐ同期", systemImage: "arrow.clockwise")
        }
        Button {
          isShowingManabaImport = true
        } label: {
          Label("ブラウザで取り込む", systemImage: "globe")
        }
      } label: {
        Text("同期")
      }
      .accessibilityLabel("manabaと同期")
    } else {
      Button {
        isShowingManabaImport = true
      } label: {
        Text("課題を取り込む")
      }
      .accessibilityLabel("manabaから課題を取り込む")
    }
  }

  /// 同期状態バー（同期中・最終同期・エラー）
  private var syncStatusBar: some View {
    HStack(spacing: 8) {
      switch manabaSync.status {
      case .syncing:
        ProgressView().controlSize(.small)
        Text("manaba同期中…")
          .foregroundStyle(.secondary)
      case .error:
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(CampusTheme.warning)
        Text(manabaSync.lastErrorMessage ?? "同期に失敗しました")
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Spacer(minLength: 0)
        Button("再試行") { syncNow() }
      case .idle:
        Image(systemName: "checkmark.icloud")
          .foregroundStyle(.secondary)
        Text(lastSyncText)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  /// 最終同期日時の表示文字列
  private var lastSyncText: String {
    guard let date = manabaSync.lastSyncDate else { return "manabaと未同期です" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ja_JP")
    formatter.dateFormat = "M/d HH:mm"
    return "最終同期 \(formatter.string(from: date))"
  }

  /// 今すぐ同期する
  private func syncNow() {
    manabaSync.sync(
      credentialStore: credentialStore,
      modelContext: modelContext,
      settings: settings,
      notifications: notifications
    )
  }

  // MARK: - 一覧

  private var assignmentList: some View {
    List {
      if !pending.isEmpty {
        Section("未提出") {
          ForEach(pending) { assignmentRow($0) }
        }
      }
      if !completed.isEmpty {
        Section("完了") {
          ForEach(completed) { assignmentRow($0) }
        }
      }
      if !overdue.isEmpty {
        Section("期限切れ") {
          ForEach(overdue) { assignmentRow($0) }
        }
      }
    }
  }

  /// 課題1行（タップでmanabaの該当ページを開く・スワイプで完了／削除）
  private func assignmentRow(_ assignment: Assignment) -> some View {
    Button {
      if let url = URL(string: assignment.manabaURL) {
        openURL(url)
      }
    } label: {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: assignment.iconName)
          .foregroundStyle(CampusTheme.accent)
          .frame(width: 24)
        VStack(alignment: .leading, spacing: 4) {
          Text(assignment.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
          if !assignment.courseName.isEmpty {
            Text(assignment.courseName)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          dueLabel(for: assignment)
          if !assignment.isDone, let reminderDate = notifications.nextReminderDate(for: assignment) {
            Label("通知 \(Self.dueFormatter.string(from: reminderDate))", systemImage: "bell.fill")
              .font(.caption2)
              .monospacedDigit()
              .foregroundStyle(CampusTheme.accent)
          }
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
      Button(role: .destructive) {
        deleteAssignment(assignment)
      } label: {
        Label("削除", systemImage: "trash")
      }
    }
    .swipeActions(edge: .leading) {
      Button {
        toggleDone(assignment)
      } label: {
        Label(assignment.isDone ? "未完了に戻す" : "完了",
              systemImage: assignment.isDone ? "arrow.uturn.backward" : "checkmark")
      }
      .tint(.green)
    }
  }

  /// 締切ラベル（期限切れ＝赤・24時間以内＝オレンジ・それ以外＝灰）
  @ViewBuilder
  private func dueLabel(for assignment: Assignment) -> some View {
    if let due = assignment.dueDate {
      let now = Date()
      let color: Color = assignment.isDone ? .secondary
        : (due < now ? CampusTheme.danger : (due.timeIntervalSince(now) < 86400 ? CampusTheme.warning : .secondary))
      Label("締切 \(Self.dueFormatter.string(from: due))", systemImage: "clock")
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(color)
    } else {
      Label("締切なし", systemImage: "clock")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - 空状態

  private var emptyState: some View {
    ContentUnavailableView {
      Label("未提出の課題はありません", systemImage: "checkmark.circle")
    } description: {
      if credentialStore.isRegistered {
        Text("「今すぐ同期」を押すと、manabaから未提出課題を取得します。")
      } else {
        Text("manabaから課題を取得するには、上の「ID・パスワード」からMARINE ID・パスワードを登録してください。未登録の場合は手動でログインして取り込めます。")
      }
    } actions: {
      if credentialStore.isRegistered {
        Button("今すぐ同期") {
          syncNow()
        }
        .buttonStyle(.borderedProminent)
        .disabled(manabaSync.isSyncing)
      } else {
        Button("manabaから取り込む") {
          isShowingManabaImport = true
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  // MARK: - 操作

  /// 取り込んだドラフトをupsertし，締切リマインダーを再予約する
  private func importAssignments(_ drafts: [AssignmentDraft]) {
    do {
      try AssignmentImporter.upsert(drafts, into: modelContext)
      rescheduleReminders()
    } catch {
      errorMessage = "課題の保存に失敗しました（\(error.localizedDescription)）．"
    }
  }

  /// 完了状態を切り替え，該当するセクションへ移す．
  private func toggleDone(_ assignment: Assignment) {
    assignment.isDone.toggle()
    saveAndReschedule(failureTitle: "更新に失敗しました")
  }

  /// 課題を削除する
  private func deleteAssignment(_ assignment: Assignment) {
    modelContext.delete(assignment)
    saveAndReschedule(failureTitle: "削除に失敗しました")
  }

  /// 保存して締切リマインダーを再予約する
  private func saveAndReschedule(failureTitle: String) {
    do {
      try modelContext.save()
      rescheduleReminders()
    } catch {
      errorMessage = "\(failureTitle)（\(error.localizedDescription)）．"
    }
  }

  /// 課題リマインダーの状態・クイック設定バー
  private var assignmentReminderStatusBar: some View {
    HStack(spacing: 8) {
      if !settings.enableAssignmentReminder {
        Image(systemName: "bell.slash")
          .foregroundStyle(.secondary)
        Text("課題の締切通知はオフです")
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("オンにする") {
          settings.enableAssignmentReminder = true
          Task {
            if notifications.authorizationStatus == .notDetermined {
              await notifications.requestAuthorization()
            } else {
              await notifications.refreshAuthorizationStatus()
            }
            rescheduleReminders()
          }
        }
      } else if notifications.authorizationStatus == .denied {
        Image(systemName: "bell.badge.slash")
          .foregroundStyle(CampusTheme.warning)
        Text("通知がオフのため課題前に通知できません")
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Button("設定を開く") {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
          }
        }
      } else {
        Image(systemName: "bell.badge.fill")
          .foregroundStyle(CampusTheme.accent)
        Text("\(reminderSummaryText)（\(notifications.scheduledAssignmentReminderCount)件予約）")
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
        Menu("変更") {
          Section("メイン通知") {
            ForEach(AppSettings.assignmentReminderOffsetOptions, id: \.self) { hours in
              Button {
                settings.assignmentReminderOffsetHours = hours
                rescheduleReminders()
              } label: {
                if settings.assignmentReminderOffsetHours == hours {
                  Label(AppSettings.assignmentOffsetLabel(hours: hours), systemImage: "checkmark")
                } else {
                  Text(AppSettings.assignmentOffsetLabel(hours: hours))
                }
              }
            }
          }
          Section("直前リマインダー") {
            ForEach(AppSettings.assignmentFinalReminderOptions, id: \.self) { minutes in
              Button {
                settings.assignmentFinalReminderMinutes = minutes
                rescheduleReminders()
              } label: {
                if settings.assignmentFinalReminderMinutes == minutes {
                  Label(AppSettings.assignmentFinalReminderLabel(minutes: minutes), systemImage: "checkmark")
                } else {
                  Text(AppSettings.assignmentFinalReminderLabel(minutes: minutes))
                }
              }
            }
          }
          Section {
            Button(role: .destructive) {
              settings.enableAssignmentReminder = false
              rescheduleReminders()
            } label: {
              Label("課題通知をオフ", systemImage: "bell.slash")
            }
          }
        }
      }
    }
    .font(.caption)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(.ultraThinMaterial)
  }

  private var reminderSummaryText: String {
    let primary = AppSettings.assignmentOffsetLabel(hours: settings.assignmentReminderOffsetHours)
    if settings.assignmentFinalReminderMinutes > 0,
       settings.assignmentFinalReminderMinutes != settings.assignmentReminderOffsetHours * 60 {
      let final = AppSettings.assignmentFinalReminderLabel(minutes: settings.assignmentFinalReminderMinutes)
      return "通知 \(primary)・\(final)"
    }
    return "通知 \(primary)"
  }

  /// 現在の全課題で締切リマインダーを予約し直す
  private func rescheduleReminders() {
    let all = (try? modelContext.fetch(FetchDescriptor<Assignment>())) ?? []
    notifications.rescheduleAssignmentReminders(assignments: all, settings: settings)
  }
}

#Preview {
  NavigationStack {
    AssignmentListView()
      .modelContainer(for: Assignment.self, inMemory: true)
      .environment(AppSettings())
      .environment(NotificationService())
      .environment(PortalCredentialStore())
      .environment(ManabaSyncService())
  }
}
