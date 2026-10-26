//
//  CIT_Campus_3DUITests.swift
//  CIT-Campus-3DUITests
//
//  Created by hara ryuto   on 2026/06/12.
//

import XCTest

final class CIT_Campus_3DUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testTimetableTabWithSavedLectures() throws {
        let app = XCUIApplication()
        app.launch()

        let timetableTab = app.tabBars.buttons["時間割"]
        XCTAssertTrue(timetableTab.waitForExistence(timeout: 15))
        timetableTab.tap()
        XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 10))

        app.buttons["授業を追加"].tap()
        let subjectField = app.textFields["科目名（必須）"]
        XCTAssertTrue(subjectField.waitForExistence(timeout: 5))
        subjectField.tap()
        let subjectName = "時間割確認 \(UUID().uuidString.prefix(8))"
        subjectField.typeText(subjectName)
        app.navigationBars.buttons["保存"].tap()
        XCTAssertTrue(app.navigationBars["時間割"].waitForExistence(timeout: 10))

        let layoutPicker = app.segmentedControls.containing(.button, identifier: "一覧").firstMatch
        XCTAssertTrue(layoutPicker.waitForExistence(timeout: 5))
        for layout in ["表", "一覧", "表"] {
            layoutPicker.buttons[layout].tap()
            XCTAssertTrue(app.staticTexts[subjectName].firstMatch.waitForExistence(timeout: 5))
        }

        for _ in 0..<3 {
            app.tabBars.buttons["マップ"].tap()
            timetableTab.tap()
            XCTAssertTrue(app.staticTexts[subjectName].firstMatch.waitForExistence(timeout: 5))
        }

        app.terminate()
        app.launch()
        XCTAssertTrue(timetableTab.waitForExistence(timeout: 15))
        timetableTab.tap()
        XCTAssertTrue(app.staticTexts[subjectName].firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
