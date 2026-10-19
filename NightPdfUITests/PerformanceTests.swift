//
//  PerformanceTests.swift
//  NightPdfUITests
//
//  Run with scripts/run-perf-tests.sh, which builds Release and seeds
//  TestAssets/large.pdf (1,500 pages) along with the other test PDFs.
//
//  While the large PDF is open, UI queries can take minutes: PDFKit answers the
//  accessibility snapshot with the text of the whole document. So those tests
//  tap by coordinate (iPhone 17 Pro) and time themselves with the app's signposts.
//

import XCTest

final class PerformanceTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetState"]
    }

    func testLaunch() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
    }

    func testOpenSmallDocument() {
        measureOpening("Sample Paper")
    }

    func testOpenLargeDocument() {
        measureOpening("Large")
    }

    func testScrollLargeDocument() {
        app.launch()
        open("Large")
        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
    }

    func testShowLargeContents() {
        app.launch()
        open("Large")
        measure(metrics: [signpost("Show Contents")]) {
            tap(x: 0.109, y: 0.929)   // Contents
            sleep(2)
            app.swipeDown(velocity: .fast)   // dismiss the sheet
            sleep(1)
        }
    }

    func testScrollLargePageThumbnails() {
        app.launch()
        open("Large")
        tap(x: 0.109, y: 0.929)   // Contents
        sleep(2)
        app.buttons["Pages"].tap()   // the sheet covers the document, so queries are quick here
        sleep(2)
        app.swipeUp(velocity: .fast)   // expand the sheet
        measure(metrics: [signpost("Render Thumbnail")]) {
            app.swipeUp(velocity: .fast)
            sleep(2)
        }
    }

    // MARK: - Helpers

    private func signpost(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "ucdavis.NightPdf", category: "Performance", name: name)
    }

    private func measureOpening(_ name: String) {
        app.launch()
        showBrowser(containing: name)
        measure(metrics: [signpost("Open Document"), signpost("Load Document"), signpost("Build Outline")]) {
            open(name)
            tap(x: 0.095, y: 0.096)   // Back to the browser
            showBrowser(containing: name)
        }
    }

    private func showBrowser(containing name: String) {
        let cell = app.cells["\(name), pdf"]
        if !cell.waitForExistence(timeout: 5) {
            app.buttons["Browse"].firstMatch.tap()
        }
        XCTAssert(cell.waitForExistence(timeout: 5), "Seed the TestAssets PDFs first")
        sleep(2)   // let the browser settle, or the tap can be dropped
    }

    /// Opens a document and waits a fixed time, without querying its UI.
    private func open(_ name: String) {
        showBrowser(containing: name)
        app.cells["\(name), pdf"].tap()
        sleep(4)
    }

    private func tap(x: Double, y: Double) {
        app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
    }
}
