//
//  AssignmentImporter.swift
//  CIT-Campus-3D
//
//  manabaから取り込んだ課題ドラフトを，既存データと重複させずにSwiftDataへ保存する．
//  重複排除キー（manabaURL．無ければmanabaId）で upsert する．
//
//  CloudKit同期では一意制約を付けられないため，別端末での取り込みが合流すると同じ課題が
//  複数レコードになりうる．そのため取り込み時・表示時に重複掃除（deduplicate）も行う．
//

import Foundation
import SwiftData

/// 課題の取り込み（upsert）結果
struct AssignmentImportResult {
  /// 新規に追加した件数
  let inserted: Int
  /// 既存を更新した件数
  let updated: Int
}

/// 課題ドラフトをSwiftDataへ保存するインポータ
enum AssignmentImporter {

  /// 重複排除キー（URLが最も安定するため優先．無ければID）
  private static func key(url: String, id: String) -> String {
    url.isEmpty ? id : url
  }

  /// 既存の課題を重複排除キー順に1件へ畳む（余分は削除．完了フラグは引き継ぐ）．
  /// - Returns: キー→残した課題 の辞書
  @MainActor
  private static func collapseDuplicates(
    _ existing: [Assignment],
    in context: ModelContext
  ) -> [String: Assignment] {
    var byKey: [String: Assignment] = [:]
    for assignment in existing {
      let assignmentKey = key(url: assignment.manabaURL, id: assignment.manabaId)
      guard !assignmentKey.isEmpty else { continue }
      if let kept = byKey[assignmentKey] {
        // 重複: どちらかが完了済みなら完了を残し，余分なレコードを削除する
        if assignment.isDone { kept.isDone = true }
        context.delete(assignment)
      } else {
        byKey[assignmentKey] = assignment
      }
    }
    return byKey
  }

  /// ドラフトを upsert する（保存まで行う．既存の重複も掃除する）
  @MainActor
  @discardableResult
  static func upsert(_ drafts: [AssignmentDraft], into context: ModelContext) throws -> AssignmentImportResult {
    let existing = try context.fetch(FetchDescriptor<Assignment>())
    // 既存の重複を畳んでからキー辞書を得る
    var byKey = collapseDuplicates(existing, in: context)

    let now = Date()
    var inserted = 0
    var updated = 0

    for draft in drafts {
      let draftKey = key(url: draft.manabaURL, id: draft.manabaId)
      guard !draftKey.isEmpty else { continue }
      if let current = byKey[draftKey] {
        // 既存は内容を最新へ更新する（提出済みフラグ isDone は維持する）
        current.type = draft.type
        current.title = draft.title
        current.courseName = draft.courseName
        current.dueDate = draft.dueDate
        current.startDate = draft.startDate
        current.manabaURL = draft.manabaURL
        current.courseURL = draft.courseURL
        current.manabaId = draft.manabaId
        current.importedAt = now
        updated += 1
      } else {
        let assignment = draft.makeAssignment(importedAt: now)
        context.insert(assignment)
        byKey[draftKey] = assignment
        inserted += 1
      }
    }

    try context.save()
    return AssignmentImportResult(inserted: inserted, updated: updated)
  }

  /// 既存の重複課題を掃除する（取り込みを伴わない．画面表示時などに呼ぶ）
  @MainActor
  static func deduplicate(into context: ModelContext) throws {
    let existing = try context.fetch(FetchDescriptor<Assignment>())
    _ = collapseDuplicates(existing, in: context)
    // 重複の削除（＝変更）が発生した場合のみ保存する
    if context.hasChanges {
      try context.save()
    }
  }
}
