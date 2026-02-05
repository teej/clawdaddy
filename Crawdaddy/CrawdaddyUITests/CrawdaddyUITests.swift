//
//  CrawdaddyUITests.swift
//  CrawdaddyUITests
//
//  Created by TJ Murphy on 2/2/26.
//

import XCTest

final class CrawdaddyUITests: XCTestCase {

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
    }

    @MainActor
    func testToastStackShowsMultipleBubbles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CRAWDADDY_LAYOUT_SELFTEST"] = "1"
        app.launch()

        let bubbles = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "SELFTEST:"))
        XCTAssertEqual(bubbles.count, 4)

        let window = app.windows.element(boundBy: 0)
        let windowFrame = window.frame
        for index in 0..<bubbles.count {
            let bubble = bubbles.element(boundBy: index)
            XCTAssertTrue(bubble.exists)
            XCTAssertGreaterThanOrEqual(bubble.frame.minY, windowFrame.minY)
            XCTAssertLessThanOrEqual(bubble.frame.maxY, windowFrame.maxY)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
