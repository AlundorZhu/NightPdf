//
//  NightPdfUITests.swift
//  NightPdfUITests
//
//  Run with scripts/run-ui-tests.sh, which copies the TestAssets PDFs into the
//  app's Documents folder first. Tap coordinates assume an iPhone 17 Pro.
//

import XCTest

final class NightPdfUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    private func open(_ name: String = "Sample Paper") {
        let cell = app.cells["\(name), pdf"]
        if !cell.waitForExistence(timeout: 5) {
            app.buttons["Browse"].firstMatch.tap()
        }
        XCTAssert(cell.waitForExistence(timeout: 5), "Seed the TestAssets PDFs first")
        sleep(2)   // let the browser settle, or the tap can be dropped
        cell.tap()
        sleep(3)
    }

    func testLinkJumpAndReturn() {
        open()
        snap("open")
        tapPoint(x: 0.177, y: 0.391)   // "3 Figures" in the table of contents
        sleep(1)
        snap("after-link")

        let back = app.buttons["Back to page 1"]
        XCTAssert(back.waitForExistence(timeout: 3))
        back.tap()
        sleep(1)
        snap("after-back")
        XCTAssertFalse(back.exists)
    }

    func testChromeContentsAndMenu() {
        open()
        tapPoint(x: 0.5, y: 0.575)   // blank area of page 1
        sleep(1)
        snap("chrome-hidden")
        XCTAssertFalse(app.buttons["Contents"].exists)
        tapPoint(x: 0.5, y: 0.575)
        sleep(1)

        app.buttons["Contents"].tap()
        sleep(1)
        snap("contents")
        app.buttons["Pages"].tap()
        sleep(1)
        snap("pages")
        app.buttons["Page 6"].tap()
        sleep(1)
        XCTAssert(app.buttons["Back to page 1"].exists)

        app.buttons["More"].tap()
        app.buttons["Page Color"].tap()
        snap("page-color-menu")
        app.buttons["Dark"].tap()
        sleep(1)
        snap("dark-pages")
        app.buttons["More"].tap()
        app.buttons["Page Color"].tap()
        app.buttons["Match System"].tap()
    }

    func testSearchLayoutAndBookmarks() {
        open()
        app.buttons["Search"].tap()
        sleep(1)
        app.typeText("Conclusion\n")
        sleep(1)
        snap("search")
        app.buttons["Done"].firstMatch.tap()
        sleep(1)

        app.buttons["Add Bookmark"].tap()
        XCTAssert(app.buttons["Remove Bookmark"].waitForExistence(timeout: 2))

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Page by Page"].tap()
        sleep(1)
        app.swipeLeft()
        sleep(1)
        snap("paged")
        XCTAssert(app.buttons["Page 2 of 9"].exists)

        app.buttons["Contents"].tap()
        app.buttons["Bookmarks"].tap()
        XCTAssert(app.staticTexts["Page 1"].waitForExistence(timeout: 2))
        snap("bookmarks")
        app.buttons["Done"].tap()

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Vertical Scrolling"].tap()
    }

    /// Rotated and cropped pages; screenshots show whether dark mode covers them fully.
    func testRotatedAndCroppedPages() {
        open("Edge Cases")
        XCTAssert(app.buttons["Page 1 of 4"].exists)
        for step in 1...3 {
            app.swipeUp(velocity: .slow)
            sleep(1)
            snap("edge-\(step)")
        }
        app.buttons["Contents"].tap()
        app.buttons["Pages"].tap()
        sleep(1)
        snap("edge-thumbnails")
    }

    private func tapPoint(x: Double, y: Double) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }

    /// Attaches a screenshot, and also writes it to $NIGHTPDF_SCREENSHOTS if set
    /// (pass TEST_RUNNER_NIGHTPDF_SCREENSHOTS to xcodebuild).
    private func snap(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["NIGHTPDF_SCREENSHOTS"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
