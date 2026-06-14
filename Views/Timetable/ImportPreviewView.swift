//
//  ImportPreviewView.swift
//  CIT-Campus-3D
//
//  ファイル解析結果のプレビュー画面．
//  解析ミスがないかユーザーが確認してから保存することで，インポートの「信頼」を担保する．
//

import SwiftUI

/// インポート内容の確認画面
struct ImportPreviewView: View {

  /// 解析された授業ドラフト
  let drafts: [LectureDraft]

  /// 保存処理（ドラフト一覧と「既存データを置き換えるか」を渡す）
  let onSave: ([LectureDraft], _ replaceExisting: Bool) -> Void

  @Environment(\.dismiss) private var dismiss

  /// 保存前に既存の時間割を削除するかどうか
  @State private var replaceExisting = true

  /// 学期ごとにまとめたドラフト
  private var semesterGroups: [(semester: Semester, drafts: [LectureDraft])] {
    Semester.allCases.compactMap { semester in
      let items = drafts
        .filter { $0.semester == semester }
        .sorted { ($0.weekday.rawValue, $0.period) < ($1.weekday.rawValue, $1.period) }
      return items.isEmpty ? nil : (semester, items)
    }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Toggle("既存の時間割を置き換える", isOn: $replaceExisting)
        } footer: {
          Text("オフにすると，現在登録されている授業に追加します．集中講義（曜日・時限のない科目）はインポート対象外です．")
        }

        ForEach(semesterGroups, id: \.semester) { group in
          Section("\(group.semester.displayName)（\(group.drafts.count)コマ）") {
            ForEach(group.drafts) { draft in
              DraftRow(draft: draft)
            }
          }
        }
      }
      .navigationTitle("インポート内容の確認")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") {
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("\(drafts.count)コマを登録") {
            onSave(drafts, replaceExisting)
            dismiss()
          }
        }
      }
    }
  }
}

/// プレビューの1行（曜日時限バッジ＋科目情報）
private struct DraftRow: View {

  let draft: LectureDraft

  /// 場所の表示文字列（キャンパス名つき）
  private var placeText: String {
    let campusName = draft.campus.displayName
    if draft.buildingName.isEmpty && draft.roomNumber.isEmpty {
      return "\(campusName)・教室未定"
    }
    if draft.buildingName.isEmpty {
      return "\(campusName) \(draft.roomNumber)教室"
    }
    return "\(campusName) \(draft.buildingName) \(draft.roomNumber)教室"
  }

  var body: some View {
    HStack(spacing: 12) {
      Text("\(draft.weekday.shortName)\(draft.period)")
        .font(.subheadline.bold())
        .frame(width: 44, height: 32)
        .background(Color.cyan.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.cyan)

      VStack(alignment: .leading, spacing: 2) {
        Text(draft.subjectName)
          .font(.subheadline)
        HStack(spacing: 8) {
          Text(placeText)
          if !draft.teacherName.isEmpty {
            Text(draft.teacherName)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
  }
}
