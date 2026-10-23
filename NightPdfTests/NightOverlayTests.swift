//
//  NightOverlayTests.swift
//  NightPdfTests
//

import PDFKit
import Testing
@testable import NightPdf

/// In dark mode each page gets an opaque, dark overlay that draws the
/// inverted page, so PDFKit's white page backing never shows while tiles
/// render. In light mode the overlay is clear.
@MainActor
struct NightOverlayTests {
    private static func makeDocument() throws -> NightDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for _ in 0..<3 {
            context.beginPDFPage(nil)
            context.setFillColor(gray: 0, alpha: 1)
            context.fill(CGRect(x: 100, y: 100, width: 400, height: 600))
            context.endPDFPage()
        }
        context.closePDF()
        return try #require(NightDocument(data: data as Data))
    }

    private static func makeView(_ document: PDFDocument) -> (NightPDFView, AnyObject) {
        let frame = CGRect(x: 0, y: 0, width: 500, height: 700)
        let view = NightPDFView(frame: frame)
        #if os(macOS)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        #else
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: frame)
        window.frame = frame
        window.addSubview(view)
        #endif
        view.pageOverlayViewProvider = view.overlays
        view.displayMode = .singlePageContinuous
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

    /// The overlays PDFKit has placed over its page views: the views whose
    /// layer holds a tiled layer.
    private static func overlays(in view: NightPDFView) -> [CALayer] {
        func visit(_ view: PlatformView) -> [CALayer] {
            #if os(macOS)
            let layer = view.layer
            #else
            let layer = Optional(view.layer)
            #endif
            var found: [CALayer] = []
            if let layer, layer.sublayers?.contains(where: { $0 is CATiledLayer }) == true {
                found.append(layer)
            }
            return found + view.subviews.flatMap(visit)
        }
        return visit(view)
    }

    @Test func darkModeOverlaysAreOpaqueAndDark() throws {
        let document = try Self.makeDocument()
        let (view, window) = Self.makeView(document)
        defer { withExtendedLifetime(window) {} }
        let light = Self.overlays(in: view)
        #expect(!light.isEmpty)
        #expect(light.allSatisfy { $0.backgroundColor == nil })
        #expect(light.allSatisfy { ($0.sublayers ?? []).allSatisfy { !($0 is CATiledLayer) || $0.isHidden } })

        document.invertsPages = true
        view.overlays.invertsPages = true
        view.redrawPages()
        Self.settle(view)
        let dark = Self.overlays(in: view)
        #expect(dark.count == light.count)
        #expect(dark.allSatisfy { $0.backgroundColor.map { $0.alpha == 1 && $0.components?.first == 1 - NightPage.inkLevel } == true })
        #expect(dark.allSatisfy { ($0.sublayers ?? []).contains { $0 is CATiledLayer && !$0.isHidden } })

        // Zooming in brings new page views, with overlays of their own.
        view.scaleFactor = 2.5
        Self.settle(view)
        #expect(Self.overlays(in: view).allSatisfy { $0.backgroundColor?.alpha == 1 })

        document.invertsPages = false
        view.overlays.invertsPages = false
        #expect(Self.overlays(in: view).allSatisfy { $0.backgroundColor == nil })
    }

    @Test func pageDrawsNothingUnderTheOverlayInDarkMode() throws {
        let document = try Self.makeDocument()
        let page = try #require(document.page(at: 0) as? NightPage)
        func centerGray(inverted: Bool, forDisplay: Bool) throws -> UInt8 {
            document.invertsPages = inverted
            let context = try #require(CGContext(
                data: nil, width: 61, height: 79, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 61, height: 79))
            context.scaleBy(x: 0.1, y: 0.1)
            if forDisplay { page.drawForDisplay(with: .cropBox, to: context) } else { page.draw(with: .cropBox, to: context) }
            let data = try #require(context.data)
            return data.assumingMemoryBound(to: UInt8.self)[40 * context.bytesPerRow + 30]
        }
        #expect(try centerGray(inverted: false, forDisplay: false) == 0)   // the black box, as printed
        #expect(try centerGray(inverted: true, forDisplay: false) == 255)  // untouched: the overlay draws
        #expect(try centerGray(inverted: true, forDisplay: true) > 200)    // the box, inverted to light
    }
}

/// The tiles follow the zoom: PDFView zooms by scaling the page layer, so a
/// tile drawn at 3x must hold 3x the pixels, not a scaled-up 1x render.
@MainActor
struct NightTileTests {
    @Test func tilesAreDrawnAtTheContextsScale() throws {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try #require(CGDataConsumer(data: data))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        pdf.beginPDFPage(nil)
        pdf.setFillColor(gray: 0, alpha: 1)
        pdf.fill(CGRect(x: 50, y: 0, width: 50, height: 100))   // right half black
        pdf.endPDFPage()
        pdf.closePDF()
        let document = try #require(NightDocument(data: data as Data))
        document.invertsPages = true
        let page = try #require(document.page(at: 0) as? NightPage)

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        layer.contentsScale = 2
        let drawer = NightTileDrawer(page: page, box: .cropBox)
        // A 3x zoom on a 2x screen: 600 pixels across for the 100-point page.
        let context = try #require(CGContext(
            data: nil, width: 600, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.scaleBy(x: 6, y: 6)
        drawer.draw(layer, in: context)
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func red(x: Int, y: Int) -> UInt8 { pixels[y * context.bytesPerRow + x * 4] }
        // Sharp at the 3x edge: pixels one apart straddle it, and left is dark paper, right is light ink.
        #expect(red(x: 150, y: 300) < 40)
        #expect(red(x: 298, y: 300) < 40)
        #expect(red(x: 301, y: 300) > 200)
        #expect(red(x: 450, y: 300) > 200)
    }
}
