import Foundation
import Testing
@testable import CIT_Campus_3D

struct SemesterTests {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return calendar
  }

  @Test(arguments: [
    (20260401, Semester.firstHalf),
    (20260411, .firstHalf),
    (20260504, .firstHalf), // 前期の休講日
    (20260717, .firstHalf),
    (20260718, .secondHalf), // 夏季休業中は次の学期
    (20260917, .secondHalf),
    (20260918, .secondHalf),
    (20260922, .secondHalf), // 9月でも後期
    (20261120, .secondHalf), // 後期の休講日
    (20261221, .secondHalf),
    (20270115, .secondHalf),
    (20270331, .secondHalf),
    (20270401, .firstHalf), // 未登録年度は月単位の判定
  ])
  func choosesSemesterFromAcademicCalendar(key: Int, expected: Semester) throws {
    let date = try #require(AcademicCalendar.current.date(forKey: key, calendar: calendar))
    #expect(Semester.current(on: date, calendar: calendar) == expected)
  }

  @Test func respectsProvidedCalendar() throws {
    let custom = AcademicCalendar(
      academicYear: 2027, spanStartKey: 20270401, spanEndKey: 20280331,
      terms: [
        .init(semester: .firstHalf, startKey: 20270410, endKey: 20270720),
        .init(semester: .secondHalf, startKey: 20270915, endKey: 20280120),
      ], closureDays: [], notableDays: []
    )
    let date = try #require(custom.date(forKey: 20270916, calendar: calendar))
    #expect(Semester.current(on: date, calendar: calendar, academicCalendar: custom) == .secondHalf)
  }

  @Test func doesNotTreatVacationAsClassDay() throws {
    let date = try #require(AcademicCalendar.current.date(forKey: 20260820, calendar: calendar))
    #expect(Semester.current(on: date, calendar: calendar) == .secondHalf)
    #expect(!AcademicCalendar.current.isClassDay(date, calendar: calendar))
  }
}
