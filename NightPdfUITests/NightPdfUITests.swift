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

    func testSearch() {
        open()
        // Off-center, so the whole circle must be tappable, not just the glyph.
        app.buttons["Search"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.8)).tap()
        sleep(1)
        XCTAssertEqual(app.keyboards.count, 1, "search starts with the keyboard up")
        app.typeText("conclusion")
        snap("search-typing")
        app.typeText("\n")
        sleep(1)
        snap("search-results")
        XCTAssertEqual(app.keyboards.count, 0, "Return puts the keyboard away")
        let count = app.staticTexts.matching(NSPredicate(format: "label MATCHES '1 of [0-9]+'")).firstMatch
        XCTAssert(count.waitForExistence(timeout: 3))

        app.buttons["Next Match"].tap()
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label MATCHES '2 of [0-9]+'")).firstMatch.exists)
        sleep(1)
        snap("search-next")

        app.buttons["All Results"].tap()
        XCTAssert(app.staticTexts["Page 7"].waitForExistence(timeout: 3))
        snap("search-list")
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'conclusion'")).element(boundBy: 0).tap()
        sleep(1)
        XCTAssert(app.staticTexts.matching(NSPredicate(format: "label MATCHES '1 of [0-9]+'")).firstMatch.exists)

        // Tapping the field brings the keyboard back to refine the search.
        app.textFields["Search"].tap()
        XCTAssertEqual(app.keyboards.count, 1)
        app.buttons["Done"].firstMatch.tap()
        sleep(1)
        XCTAssert(app.buttons["Search"].exists, "Done brings the bottom bar back")
    }

    func testLayout() {
        open()

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Page by Page"].tap()
        sleep(1)
        app.swipeLeft()
        sleep(1)
        snap("paged")
        XCTAssert(app.buttons["Page 2 of 9"].exists)

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Vertical Scrolling"].tap()
    }

    /// The simulator has no accelerometer, so this drives the scroll a knock
    /// triggers through the sheet's Try It buttons.
    func testKnockScrolling() {
        open()
        app.buttons["More"].tap()
        app.buttons["Knock to Scroll…"].tap()
        XCTAssert(app.switches["Knock to Scroll"].waitForExistence(timeout: 3))
        snap("knock-settings")
        knockSheetShowsTryIt()

        for _ in 1...3 {
            app.buttons["Double Knock"].tap()
            sleep(1)
        }
        snap("knock-forward")
        app.buttons["Done"].tap()
        sleep(1)
        let forward = currentPage()
        XCTAssertGreaterThan(forward, 1, "knocks scroll forward")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Back to page'")).firstMatch.exists,
                       "scrolling isn't a jump to return from")

        app.buttons["More"].tap()
        app.buttons["Knock to Scroll…"].tap()
        knockSheetShowsTryIt()
        app.buttons["Triple Knock"].tap()
        sleep(1)
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertLessThan(currentPage(), forward, "a triple knock scrolls back")

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Page by Page"].tap()
        sleep(1)
        let paged = currentPage()
        app.buttons["More"].tap()
        app.buttons["Knock to Scroll…"].tap()
        knockSheetShowsTryIt()
        app.buttons["Double Knock"].tap()
        sleep(1)
        snap("knock-paged")
        app.buttons["Done"].tap()
        sleep(1)
        XCTAssertEqual(currentPage(), paged + 1, "a knock turns the page")

        app.buttons["More"].tap()
        app.buttons["Layout"].tap()
        app.buttons["Vertical Scrolling"].tap()
    }

    /// The Try It section sits below the half-height sheet's fold.
    private func knockSheetShowsTryIt() {
        let button = app.buttons["Triple Knock"]   // the last row
        XCTAssert(app.switches["Knock to Scroll"].waitForExistence(timeout: 3))
        for _ in 0..<4 where !button.isHittable {
            app.collectionViews.firstMatch.swipeUp()
        }
    }

    private func currentPage() -> Int {
        let label = app.buttons.matching(NSPredicate(format: "label MATCHES 'Page [0-9]+ of [0-9]+'")).firstMatch.label
        return Int(label.split(separator: " ")[1]) ?? 0
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
