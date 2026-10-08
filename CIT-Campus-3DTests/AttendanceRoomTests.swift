import Foundation
import Testing
@testable import CIT_Campus_3D

struct AttendanceRoomTests {
  @Test(arguments: [("731", "7301"), ("７３１", "7301"), (" 642\n", "642"),
                    ("1024", "1024"), ("7301", "7301")])
  func convertsRoomNumber(input: String, expected: String) {
    #expect(AttendanceRoom.roomID(for: input) == expected)
    #expect(AttendanceRoom.url(for: input)?.absoluteString ==
      "https://attendance.is.chibatech.ac.jp/attendance/class_room/\(expected)")
  }

  @Test(arguments: ["", "12", "123456", "731/other", "73a", "731?x=1"])
  func rejectsInvalidRoom(input: String) {
    #expect(AttendanceRoom.url(for: input) == nil)
  }
}
