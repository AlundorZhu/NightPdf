//
//  OutlineJumpTests.swift
//  NightPdfTests
//

import PDFKit
import Testing
@testable import NightPdf

/// Choosing a contents entry goes to its page, and to its spot on the page
/// when the entry names one, wherever the reader was before.
@MainActor
struct OutlineJumpTests {
    private static let unspecified = CGFloat(kPDFDestinationUnspecifiedValue)

    /// Entries as (page, y), some at a spot and some at the page only, two on one page.
    private static let entries: [(page: Int, y: CGFloat)] = [
        (0, unspecified), (1, 700), (1, 300), (3, unspecified), (4, 150), (6, 720), (8, unspecified), (10, 400),
    ]

    /// Thirty blank letter-size pages with an outline, written out as a file
    /// would have it: `/XYZ` destinations, `null` for an unspecified top.
    private static func makeDocument() throws -> PDFDocument {
        let pageCount = 30
        // Objects: catalog, page tree, the pages, the outline root, its entries.
        let firstPage = 3, firstEntry = firstPage + pageCount + 1
        var objects = [
            "<< /Type /Catalog /Pages 2 0 R /Outlines \(firstEntry - 1) 0 R /PageMode /UseOutlines >>",
            "<< /Type /Pages /Kids [\((0..<pageCount).map { "\(firstPage + $0) 0 R" }.joined(separator: " "))] /Count \(pageCount) >>",
        ]
        objects += (0..<pageCount).map { _ in "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>" }
        objects.append("<< /Type /Outlines /First \(firstEntry) 0 R /Last \(firstEntry + entries.count - 1) 0 R /Count \(entries.count) >>")
        for (index, entry) in entries.enumerated() {
            let top = entry.y == unspecified ? "null" : "\(Int(entry.y))"
            var item = "<< /Title (Entry \(index)) /Parent \(firstEntry - 1) 0 R /Dest [\(firstPage + entry.page) 0 R /XYZ null \(top) null]"
            if index > 0 { item += " /Prev \(firstEntry + index - 1) 0 R" }
            if index < entries.count - 1 { item += " /Next \(firstEntry + index + 1) 0 R" }
            objects.append(item + " >>")
        }
        var file = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(file.utf8.count)
            file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xref = file.utf8.count
        file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        file += offsets.map { String(format: "%010d 00000 n \n", $0) }.joined()
        file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return try #require(PDFDocument(data: Data(file.utf8)))
    }

    private static func makeView(_ document: PDFDocument, mode: PDFDisplayMode, width: CGFloat) throws -> (NightPDFView, AnyObject) {
        let frame = CGRect(x: 0, y: 0, width: width, height: 700)
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
        // Alignment deferred out of a layout pass runs on the next main queue turn.
        RunLoop.main.run(until: .now + 0.05)
    }

    /// Widths that fit the page zoomed out, near actual size, and zoomed in.
    @Test(arguments: [PDFDisplayMode.singlePageContinuous, .twoUpContinuous, .singlePage], [300.0, 640.0, 1400.0])
    func entryGoesToItsPageAndSpot(mode: PDFDisplayMode, width: CGFloat) throws {
        let document = try Self.makeDocument()
        let (view, window) = try Self.makeView(document, mode: mode, width: width)
        defer { withExtendedLifetime(window) {} }
        let outline = try #require(document.outlineRoot)
        #expect(outline.numberOfChildren == Self.entries.count)

        // From the start, from the end, and from each entry to the next.
        for start in [0, document.pageCount - 1, nil] {
            for index in 0..<outline.numberOfChildren {
                if let start, let page = document.page(at: start) {
                    view.go(to: page)
                    Self.settle(view)
                }
                let item = try #require(outline.child(at: index))
                let destination = try #require(item.destination ?? (item.action as? PDFActionGoTo)?.destination)
                let expectedPage = try #require(destination.page)
                view.go(to: destination)
                Self.settle(view)

                let label = "entry \(index) (page \(Self.entries[index].page)), \(mode) \(Int(width))pt wide, from \(start.map(String.init) ?? "previous")"
                // Two-up shows a spread; the current page can be either side of it.
                #if os(macOS)
                let shown = view.currentPage.map(document.index(for:)) ?? -1
                #else
                // When several small pages fit on screen, PDFKit's current page on
                // iOS is the one at the centre; what matters is the page at the top.
                let shown = view.visibleDestination?.page.map(document.index(for:)) ?? -1
                #endif
                let onPage = mode == .twoUpContinuous ? shown / 2 == Self.entries[index].page / 2 : shown == Self.entries[index].page
                #expect(onPage, "\(label): on page \(shown)")
                // Only the continuous layouts scroll to a spot. (Every entry is far
                // enough from the end for its page to scroll up to the top.)
                guard view.isScrollingLayout else { continue }
                // Measured on screen, in view points: the spot, or the top of the
                // page for an entry without one, just below the top of the view.
                let y = destination.point.y == Self.unspecified ? expectedPage.bounds(for: .cropBox).maxY : destination.point.y
                let target = view.convert(CGPoint(x: 0, y: y), from: expectedPage)
                #if os(macOS)
                let fromTop = view.bounds.maxY - target.y
                #else
                // Below the safe area, where the navigation bar sits in the app.
                let fromTop = target.y - view.bounds.minY - view.safeAreaInsets.top
                #endif
                if destination.point.y == Self.unspecified {
                    #expect((-1...NightPDFView.jumpMargin + 20).contains(fromTop), "\(label): page top \(fromTop)pt from the view's top")
                } else {
                    #expect(abs(fromTop - NightPDFView.jumpMargin) < 2,
                            "\(label): spot \(fromTop)pt from the view's top, wanted \(NightPDFView.jumpMargin)")
                }
            }
        }
    }
}
