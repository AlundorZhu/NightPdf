//
//  VisibleDestinationTests.swift
//  NightPdfTests
//

import PDFKit
import Testing
@testable import NightPdf

/// The reading position is saved with `visibleDestination` and restored with
/// `go(to:)`; the two have to agree, or every reopen drifts a little.
@MainActor
struct VisibleDestinationTests {
    /// Ten blank letter-size pages.
    private static func makeDocument() throws -> PDFDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<10 {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(PDFDocument(data: data as Data))
    }

    /// A PDF view in an offscreen window, so it lays out its scroll view.
    private static func makeView(_ document: PDFDocument, mode: PDFDisplayMode) throws -> (NightPDFView, AnyObject) {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 700)
        let view = NightPDFView(frame: frame)
        #if os(macOS)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        #else
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.addSubview(view)
        #endif
        view.displayMode = mode
        view.document = document
        view.autoScales = true
        settle(view)
        return (view, window)
    }

    private static func settle(_ view: NightPDFView) {
        #if os(macOS)
        view.layoutSubtreeIfNeeded()
        #else
        view.layoutIfNeeded()
        #endif
    }

    @Test(arguments: [PDFDisplayMode.singlePageContinuous, .twoUpContinuous])
    func savedPositionComesBackToTheSameSpot(mode: PDFDisplayMode) throws {
        let document = try Self.makeDocument()
        let (view, window) = try Self.makeView(document, mode: mode)
        defer { withExtendedLifetime(window) {} }

        // Even pages, which are on the left in two-up, where the position is
        // read; and far enough from the end that the view can scroll them up.
        for (pageIndex, y) in [(2, 400.0), (4, 120.0), (4, 700.0)] {
            let page = try #require(document.page(at: pageIndex))
            view.go(to: PDFDestination(page: page, at: CGPoint(x: 0, y: y)))
            Self.settle(view)
            let saved = try #require(view.visibleDestination)
            #expect(saved.page == page, "page \(pageIndex) is at the top")
            #expect(abs(saved.point.y - y) < 1, "the spot jumped to is where the position is read")

            // Somewhere else, then back.
            let first = try #require(document.page(at: 0))
            view.go(to: PDFDestination(page: first, at: CGPoint(x: 0, y: 792)))
            Self.settle(view)
            view.go(to: saved)
            Self.settle(view)
            let restored = try #require(view.visibleDestination)
            #expect(restored.page == saved.page)
            #expect(abs(restored.point.y - saved.point.y) < 1, "no drift on page \(pageIndex) at \(y)")
        }
    }
}
