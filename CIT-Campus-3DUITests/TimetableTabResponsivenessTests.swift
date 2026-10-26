import XCTest

final class TimetableTabResponsivenessTests: XCTestCase {
  @MainActor
  func testImportMenuAndCompactSheets() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let timetableTab = app.tabBars.buttons["時間割"]
    XCTAssertTrue(timetableTab.waitForExistence(timeout: 15))
    timetableTab.tap()

    app.buttons["時間割を取り込む"].tap()
    for source in ["ポータル", "PDF / Excel", "スクショ"] {
      XCTAssertTrue(app.buttons[source].waitForExistence(timeout: 5))
    }
    // メニューの外を押して閉じ，認証やファイルの読み込みは開始しない．
    app.navigationBars["時間割"].tap()

    app.buttons["教室番号から出席"].tap()
    let roomField = app.textFields["教室番号（例：731、642、1024）"]
    XCTAssertTrue(roomField.waitForExistence(timeout: 5))
    roomField.tap()
    roomField.typeText("12")
    let openAttendance = app.buttons["この教室の出席画面を開く"]
    XCTAssertFalse(openAttendance.isEnabled)
    roomField.typeText("3")
    XCTAssertTrue(openAttendance.isEnabled)
    // 出席を送信せず，入力と閉じる操作だけを検証する．
    app.navigationBars.buttons["閉じる"].tap()

    app.tabBars.buttons["マップ"].tap()
    app.buttons["場所一覧"].tap()
    let placeNavigation = app.navigationBars["場所を選んで案内"]
    XCTAssertTrue(placeNavigation.waitForExistence(timeout: 5))
    let searchField = app.searchFields.firstMatch
    XCTAssertTrue(searchField.waitForExistence(timeout: 5))
    searchField.tap()
    searchField.typeText("7号館")
    XCTAssertTrue(app.staticTexts["7号館"].firstMatch.waitForExistence(timeout: 5))
    // 検索中はナビゲーションバーが隠れ，検索欄横の閉じるボタンが表示される．
    let endSearch = app.buttons.matching(
      NSPredicate(format: "label IN %@", ["close", "Cancel", "キャンセル"])
    ).firstMatch
    XCTAssertTrue(endSearch.waitForExistence(timeout: 5))
    endSearch.tap()
    XCTAssertTrue(placeNavigation.waitForExistence(timeout: 5))
    placeNavigation.buttons["キャンセル"].tap()
    XCTAssertTrue(app.buttons["場所一覧"].waitForExistence(timeout: 5))
  }

  @MainActor
  func testTabSwitchAndTimetableControlsRespond() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    let timetableTab = app.tabBars.buttons["時間割"]
    XCTAssertTrue(timetableTab.waitForExistence(timeout: 15))

    for _ in 0..<3 {
      timetableTab.tap()
      XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

      let layout = app.segmentedControls.containing(.button, identifier: "一覧").firstMatch
      XCTAssertTrue(layout.waitForExistence(timeout: 5))
      layout.buttons["一覧"].tap()
      layout.buttons["表"].tap()

      // 画面が出るだけでなく，表示後もメインスレッドが操作に応答することを確認．
      app.buttons["授業を追加"].tap()
      XCTAssertTrue(app.textFields["科目名（必須）"].waitForExistence(timeout: 5))
      app.navigationBars.buttons["キャンセル"].tap()
      XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 5))

      app.tabBars.buttons["設定"].tap()
      XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
    }
  }
}
