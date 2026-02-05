//
//  ClawDaddyUITests.swift
//  ClawDaddyUITests
//
//  Created by TJ Murphy on 2/2/26.
//

import XCTest

final class ClawDaddyUITests: XCTestCase {

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
        app.launchEnvironment["CLAWDADDY_LAYOUT_SELFTEST"] = "1"
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
    func testSubAgentSelfTestShowsEmojis() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLAWDADDY_SUBAGENT_SELFTEST"] = "1"
        app.launch()

        // Each sub-agent renders a 🦞 emoji; expect 4
        let lobsters = app.staticTexts.matching(NSPredicate(format: "label == %@", "🦞"))
        XCTAssertEqual(lobsters.count, 4, "Expected 4 lobster emojis for 4 sub-agents")
    }

    @MainActor
    func testSubAgentSelfTestShowsBubbles() throws {
        let app = XCUIApplication()
        app.launchEnvironment["CLAWDADDY_SUBAGENT_SELFTEST"] = "1"
        app.launch()

        // waiting_for_input agent has question bubble
        let questionBubble = app.staticTexts["What bait should I use?"]
        XCTAssertTrue(questionBubble.exists, "Expected question bubble for waiting_for_input agent")

        // done agent has result bubble
        let resultBubble = app.staticTexts["Found 3 treasure chests!"]
        XCTAssertTrue(resultBubble.exists, "Expected result bubble for done agent")

        // error agent has error bubble
        let errorBubble = app.staticTexts["Lost the anchor!"]
        XCTAssertTrue(errorBubble.exists, "Expected error bubble for error agent")
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
