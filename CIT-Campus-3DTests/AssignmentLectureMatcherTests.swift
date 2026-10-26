import Foundation
import Testing
@testable import CIT_Campus_3D

struct AssignmentLectureMatcherTests {
  @Test @MainActor
  func batchMatchingPreservesBadgesAndDeadlineOrder() {
    let subjects = ["デジタル通信", "情報数学", "数学", "A", "未登録科目", "デジタル通信"]
    let lectures = subjects.map {
      Lecture(semester: .firstHalf, weekday: .monday, period: 1,
              subjectName: $0, teacherName: "", campus: .tsudanuma,
              buildingName: "", roomNumber: "")
    }
    let assignments = [
      makeAssignment("2026前期_デジタル通信【情報】", due: 200),
      makeAssignment("2026前期_デジタル通信【情報】", due: 100),
      makeAssignment("情報数学（再）", due: nil),
      makeAssignment("デジタル通信", due: 50, isDone: true),
      makeAssignment("A", due: 100),
    ]
    let batch = AssignmentLectureMatcher.activeAssignmentsBySubject(
      for: lectures, in: assignments
    )
    for lecture in lectures {
      let expected = AssignmentLectureMatcher.activeAssignments(for: lecture, in: assignments)
      #expect(batch[lecture.subjectName, default: []].map(\.manabaId) == expected.map(\.manabaId))
    }
    #expect(batch["デジタル通信"]?.count == 2)
    #expect(batch["数学"]?.count == 1)
    #expect(batch["デジタル通信"]?.first?.dueDate == Date(timeIntervalSince1970: 100))
  }

  private func makeAssignment(_ course: String, due: TimeInterval?, isDone: Bool = false) -> Assignment {
    Assignment(type: "レポート", title: "課題", courseName: course,
               dueDate: due.map { Date(timeIntervalSince1970: $0) }, startDate: nil,
               manabaURL: "", courseURL: "", manabaId: UUID().uuidString, isDone: isDone)
  }
}
