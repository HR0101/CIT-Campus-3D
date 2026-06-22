//
//  AssignmentLectureMatcher.swift
//  CIT-Campus-3D
//
//  時間割の授業（Lecture.subjectName）とmanaba課題（Assignment.courseName）を
//  表記差を吸収して結びつけるユーティリティ．
//  manabaのコース名は「2026前期_デジタル通信【情報】」のように年度・学期・クラス情報が付くため，
//  正規化（括弧内・年度学期・空白記号を除去）したうえで，休講判定と同じ双方向の部分一致で照合する．
//

import Foundation

/// 授業と課題を結びつける照合ロジック
enum AssignmentLectureMatcher {

  /// 部分一致での誤検出を防ぐための最短キー長（日本語2文字以上）
  private static let minimumKeyLength = 2

  /// 指定した授業に紐づく未提出（未完了）の課題を，締切の早い順で返す．
  /// - Parameters:
  ///   - lecture: 対象の授業
  ///   - assignments: 全課題（完了済みも含めてよい．内部で未完了のみ抽出する）
  /// - Returns: その授業の科目名に一致する未提出課題（締切の早い順）
  static func activeAssignments(
    for lecture: Lecture,
    in assignments: [Assignment]
  ) -> [Assignment] {
    let subjectKey = normalizedKey(lecture.subjectName)
    guard subjectKey.count >= minimumKeyLength else { return [] }

    return assignments
      .filter { assignment in
        guard !assignment.isDone else { return false }
        let courseKey = normalizedKey(assignment.courseName)
        guard courseKey.count >= minimumKeyLength else { return false }
        // 双方向の部分一致（休講判定 isCancellation と同じ方針で表記差を吸収する）
        return courseKey.contains(subjectKey) || subjectKey.contains(courseKey)
      }
      .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
  }

  /// 科目名・コース名を比較用に正規化する．
  /// 括弧内・年度学期トークン・空白記号を取り除き，全角英数を半角化・小文字化して表記差をならす．
  /// - Parameter raw: 元の科目名またはコース名
  /// - Returns: 比較に使う正規化済みキー
  static func normalizedKey(_ raw: String) -> String {
    var text = raw

    // 括弧（全角・半角）とその中身を除去する（例: 【情報】（再）(2) 〔...〕［...］）
    let bracketPattern = "[【（(〔［\\[].*?[】）)〕］\\]]"
    text = text.replacingOccurrences(
      of: bracketPattern, with: "", options: .regularExpression
    )

    // 年度・学期を表すトークンを除去する（例: 2026 前期 後期 通年 集中）
    let semesterPattern = "(19|20)\\d{2}|[前後]期|通年|集中"
    text = text.replacingOccurrences(
      of: semesterPattern, with: "", options: .regularExpression
    )

    // 全角英数記号を半角へ統一する（両辺に同じ変換をかけるため整合は保たれる）
    if let halfWidth = text.applyingTransform(.fullwidthToHalfwidth, reverse: false) {
      text = halfWidth
    }

    // 空白・区切り記号を除去する（例: _ - ・ ， 、 ／ /）
    let separatorPattern = "[\\s_\\-・,，、.／/]+"
    text = text.replacingOccurrences(
      of: separatorPattern, with: "", options: .regularExpression
    )

    return text.lowercased()
  }
}
