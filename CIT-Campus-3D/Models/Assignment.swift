//
//  Assignment.swift
//  CIT-Campus-3D
//
//  manaba（cit.manaba.jp）から取り込んだ課題を表すSwiftDataモデル．
//  未提出課題一覧（home_library_query）の各行に対応する．
//  CloudKit同期に対応するため，全プロパティに既定値を持たせ，ユニーク制約・リレーションは持たない
//  （重複排除は取り込み時に manabaId で行う）．
//

import Foundation
import SwiftData

/// manabaの課題1件
@Model
final class Assignment {
  /// 課題のタイプ（例: レポート／プロジェクト／小テスト／アンケート）
  var type: String = ""
  /// 課題タイトル
  var title: String = ""
  /// コース名（科目名）
  var courseName: String = ""
  /// 受付終了日時（締切．不明な場合はnil）
  var dueDate: Date? = nil
  /// 受付開始日時（不明な場合はnil）
  var startDate: Date? = nil
  /// 課題ページのURL（manaba上の安定リンク．重複排除の基準）
  var manabaURL: String = ""
  /// コースページのURL
  var courseURL: String = ""
  /// 課題ID（URL末尾の数値．重複排除・通知IDに使う）
  var manabaId: String = ""
  /// 完了（提出済み・非表示）としてユーザーが消したか
  var isDone: Bool = false
  /// 取り込んだ日時
  var importedAt: Date = Date.distantPast

  init(
    type: String,
    title: String,
    courseName: String,
    dueDate: Date?,
    startDate: Date?,
    manabaURL: String,
    courseURL: String,
    manabaId: String,
    isDone: Bool = false,
    importedAt: Date = Date()
  ) {
    self.type = type
    self.title = title
    self.courseName = courseName
    self.dueDate = dueDate
    self.startDate = startDate
    self.manabaURL = manabaURL
    self.courseURL = courseURL
    self.manabaId = manabaId
    self.isDone = isDone
    self.importedAt = importedAt
  }

  /// 締切までの残り（現在時刻基準．締切不明・超過時はnil）
  func timeRemaining(from now: Date = Date()) -> TimeInterval? {
    guard let dueDate, dueDate > now else { return nil }
    return dueDate.timeIntervalSince(now)
  }

  /// 締切を過ぎているか（締切不明なら false）
  func isOverdue(from now: Date = Date()) -> Bool {
    guard let dueDate else { return false }
    return dueDate < now
  }

  /// タイプに対応するSF Symbol名（一覧の見栄え用）
  var iconName: String {
    switch type {
    case let t where t.contains("レポート"): return "doc.text"
    case let t where t.contains("小テスト"), let t where t.contains("テスト"): return "checkmark.square"
    case let t where t.contains("アンケート"): return "list.bullet.clipboard"
    case let t where t.contains("プロジェクト"): return "person.3"
    default: return "tray.full"
    }
  }
}
