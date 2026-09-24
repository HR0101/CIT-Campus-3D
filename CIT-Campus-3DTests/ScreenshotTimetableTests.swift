import Foundation
import Testing
@testable import CIT_Campus_3D

struct ScreenshotTimetableTests {
  @Test func rejectsInvalidImage() {
    #expect(throws: (any Error).self) {
      try ScreenshotTimetableParser().parse(data: Data("not an image".utf8))
    }
  }

  @Test @MainActor func normalizesRoomDigitsWithoutChangingJapaneseTitle() {
    let entry = ScreenshotLectureEntry(cell: .init(weekday: 5, period: 3, lines: [
      "データベース 情工3年", "白木 詩乃", "６４ ２ 講義室／津田沼キャ", "ンパス", "2単位"
    ]))
    let draft = entry.draft(semester: .secondHalf)
    #expect(draft.subjectName == "データベース")
    #expect(draft.teacherName == "白木 詩乃")
    #expect(draft.roomNumber == "642")
    #expect(draft.weekday == .thursday)
    #expect(draft.period == 3)
    #expect(draft.semester == .secondHalf)
  }

  @Test @MainActor func preservesWrappedSubjectAndLongVowel() {
    let entry = ScreenshotLectureEntry(cell: .init(weekday: 5, period: 7, lines: [
      "総合科学特論 PERCが", "拓くアストロバイオロジ", "ー", "小林正規",
      "611講義室／津田沼キャ", "ンパス", "2単位"
    ]))
    #expect(entry.subject == "総合科学特論 PERCが拓くアストロバイオロジー")
    #expect(entry.teacher == "小林正規")
    #expect(entry.room == "611")
  }

  @Test @MainActor func allowsCorrectionBeforeCreatingDraft() {
    var entry = ScreenshotLectureEntry(cell: .init(weekday: 2, period: 10, lines: [
      "情報理論 情エ3年 ※情", "報", "中村 あすか", "731講義室／津田沼キャンパス"
    ]))
    #expect(entry.subject == "情報理論")
    entry.weekday = .friday
    entry.period = 6
    entry.subject = "修正した科目"
    entry.room = " 732 "
    let draft = entry.draft(semester: .firstHalf)
    #expect(draft.subjectName == "修正した科目")
    #expect(draft.weekday == .friday)
    #expect(draft.period == 6)
    #expect(draft.roomNumber == "732")
  }
}
