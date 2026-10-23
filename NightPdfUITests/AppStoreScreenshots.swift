//
//  AppStoreScreenshots.swift
//  NightPdfUITests
//
//  Captures the App Store screenshots. Run with scripts/take-screenshots.sh,
//  which seeds AppStore/showcase.pdf and sets NIGHTPDF_APPSTORE; skipped otherwise.
//

import XCTest

final class AppStoreScreenshots: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NIGHTPDF_APPSTORE"] != nil,
                          "Run with scripts/take-screenshots.sh")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
        app.launch()
    }

    func testScreenshots() {
        let cell = app.cells["How Owls See in the Dark, pdf"]
        if !cell.waitForExistence(timeout: 5) {
            app.buttons["Browse"].firstMatch.tap()
        }
        XCTAssert(cell.waitForExistence(timeout: 5))
        sleep(2)
        cell.tap()
        sleep(3)

        app.buttons["More"].tap()
        app.buttons["Page Color"].tap()
        app.buttons["Dark"].tap()
        sleep(2)
        snap("1-night")

        app.buttons["Contents"].tap()
        app.buttons["Pages"].tap()
        sleep(2)
        snap("5-pages")
        app.buttons["Page 2"].tap()
        sleep(1)

        app.buttons["Contents"].tap()
        sleep(1)
        snap("3-contents")
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'Sensitivity at Night'")).firstMatch.tap()
        sleep(2)
        snap("2-figure")

        app.buttons["Search"].tap()
        sleep(1)
        app.typeText("eyes\n")
        sleep(2)
        app.buttons["All Results"].tap()
        sleep(2)
        snap("4-search")
    }

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
