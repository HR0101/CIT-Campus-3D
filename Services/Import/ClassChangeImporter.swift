//
//  ClassChangeImporter.swift
//  CIT-Campus-3D
//
//  時間割変更ドラフト（休講・補講・教室変更）を changeKey で重複排除して保存する．
//  併せて，掲載から一定期間を過ぎた古い変更は掃除する（実施日が過去のもの）．
//

import Foundation
import SwiftData

/// 時間割変更の取り込み結果
struct ClassChangeImportResult {
  let inserted: Int
  let updated: Int
}

/// 時間割変更ドラフトをSwiftDataへ保存するインポータ
enum ClassChangeImporter {

  /// 既存の変更を changeKey ごとに1件へ畳む（CloudKit同期で生じる重複の掃除）
  @MainActor
  private static func collapseDuplicates(
    _ existing: [ClassChange],
    in context: ModelContext
  ) -> [String: ClassChange] {
    var byKey: [String: ClassChange] = [:]
    for change in existing where !change.changeKey.isEmpty {
      if byKey[change.changeKey] != nil {
        context.delete(change)
      } else {
        byKey[change.changeKey] = change
      }
    }
    return byKey
  }

  /// 既存の重複を掃除する（取り込みを伴わない．画面表示時などに呼ぶ）
  @MainActor
  static func deduplicate(into context: ModelContext) throws {
    let existing = try context.fetch(FetchDescriptor<ClassChange>())
    _ = collapseDuplicates(existing, in: context)
    if context.hasChanges {
      try context.save()
    }
  }

  /// ドラフトを upsert する（changeKeyで突合．既存の重複も掃除する．保存まで行う）
  @MainActor
  @discardableResult
  static func upsert(_ drafts: [ClassChangeDraft], into context: ModelContext) throws -> ClassChangeImportResult {
    let existing = try context.fetch(FetchDescriptor<ClassChange>())
    var byKey = collapseDuplicates(existing, in: context)

    let now = Date()
    var inserted = 0
    var updated = 0

    for draft in drafts {
      if let current = byKey[draft.changeKey] {
        current.type = draft.type
        current.subjectName = draft.subjectName
        current.teacherName = draft.teacherName
        current.date = draft.date
        current.startPeriod = draft.startPeriod
        current.endPeriod = draft.endPeriod
        current.room = draft.room
        current.noticeTitle = draft.noticeTitle
        current.postedDate = draft.postedDate
        current.importedAt = now
        updated += 1
      } else {
        let change = draft.makeChange(importedAt: now)
        context.insert(change)
        byKey[draft.changeKey] = change
        inserted += 1
      }
    }

    try context.save()
    return ClassChangeImportResult(inserted: inserted, updated: updated)
  }
}
