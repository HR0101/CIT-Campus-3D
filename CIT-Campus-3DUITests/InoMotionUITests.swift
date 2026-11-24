import XCTest

final class InoMotionUITests: XCTestCase {
  @MainActor
  func testLiquidCancelDraftAndRoomAttendanceDetection() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()

    let timetableTab = app.tabBars.buttons["時間割"]
    XCTAssertTrue(timetableTab.waitForExistence(timeout: 15))
    timetableTab.tap()
    XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

    // 1. 教室番号から出席：入力連動活性 + 因果ピル（731 -> 出席ID 7301）
    app.buttons["教室番号から出席"].tap()
    let roomField = app.textFields["教室番号（例：731、642、1024）"]
    XCTAssertTrue(roomField.waitForExistence(timeout: 5))
    roomField.tap()
    roomField.typeText("731")

    let openAttendance = app.buttons["この教室の出席画面を開く"]
    XCTAssertTrue(openAttendance.isEnabled)
    XCTAssertTrue(app.staticTexts["出席ID 7301"].waitForExistence(timeout: 4))
    app.navigationBars.buttons["閉じる"].tap()
    XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

    // 2. 授業を追加：未保存入力時のリキッドキャンセル（捨てる / 下書きに保存）
    app.buttons["授業を追加"].tap()
    let subjectField = app.textFields["科目名（必須）"]
    XCTAssertTrue(subjectField.waitForExistence(timeout: 5))
    subjectField.tap()
    subjectField.typeText("モーション検証")

    app.navigationBars.buttons["キャンセル"].tap()
    let discardButton = app.buttons["捨てる"]
    let saveDraftButton = app.buttons["下書きに保存"]
    XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
    XCTAssertTrue(saveDraftButton.waitForExistence(timeout: 3))

    saveDraftButton.tap()
    XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

    // 再オープンで下書き復元 → 捨てるで破棄されること
    app.buttons["授業を追加"].tap()
    XCTAssertTrue(app.staticTexts["保存した下書きを復元しました"].waitForExistence(timeout: 5))
    app.navigationBars.buttons["キャンセル"].tap()
    XCTAssertTrue(discardButton.waitForExistence(timeout: 3))
    discardButton.tap()
    XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

    // 破棄後の再オープンでは空フォームになり、キャンセルで即閉じること
    app.buttons["授業を追加"].tap()
    XCTAssertTrue(subjectField.waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["保存した下書きを復元しました"].exists)
    app.navigationBars.buttons["キャンセル"].tap()
    XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))
  }
}
