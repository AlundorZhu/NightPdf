//
//  MatchHighlighter.swift
//  NightPdf
//

import PDFKit

/// Draws search highlights in overlay views above each page. PDFKit's own
/// `highlightedSelections` render into the page, where dark mode's inversion
/// turns them into barely visible tinted text.
final class MatchHighlighter: NSObject, PDFPageOverlayViewProvider {
    /// Translucent so the matched word stays readable on light and dark pages.
    static let matchColor = PlatformColor.systemYellow.withAlphaComponent(0.3)
    static let currentColor = PlatformColor.systemOrange.withAlphaComponent(0.55)

    /// Line rects in page space, by page index.
    private var matches: [Int: [CGRect]] = [:]
    private var current: (pageIndex: Int, rects: [CGRect])?
    private var overlays: [Int: MatchOverlayView] = [:]

    /// Adds matches as the search finds them; only pages that changed redraw.
    func add(_ newMatches: [(pageIndex: Int, rects: [CGRect])]) {
        var changed: Set<Int> = []
        for (pageIndex, rects) in newMatches {
            matches[pageIndex, default: []].append(contentsOf: rects)
            changed.insert(pageIndex)
        }
        changed.forEach { overlays[$0]?.redraw() }
    }

    func removeAll() {
        matches = [:]
        current = nil
        overlays.values.forEach { $0.redraw() }
    }

    func setCurrent(_ rects: [CGRect], onPage pageIndex: Int) {
        let old = current?.pageIndex
        current = (pageIndex, rects)
        for page in Set([old, pageIndex].compactMap { $0 }) {
            overlays[page]?.redraw()
        }
    }

    fileprivate func highlights(forPage pageIndex: Int) -> (matches: [CGRect], current: [CGRect]) {
        (matches[pageIndex] ?? [], current?.pageIndex == pageIndex ? current?.rects ?? [] : [])
    }

    // MARK: - PDFPageOverlayViewProvider

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> PlatformView? {
        guard let pageIndex = view.document?.index(for: page) else { return nil }
        let overlay = MatchOverlayView(highlighter: self, pdfView: view, page: page, pageIndex: pageIndex)
        overlays[pageIndex] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: PlatformView, for page: PDFPage) {
        // A layout change can make the page's new overlay before ending the old one.
        guard let pageIndex = pdfView.document?.index(for: page), overlays[pageIndex] === overlayView else { return }
        overlays[pageIndex] = nil
    }
}

private final class MatchOverlayView: PlatformView {
    private weak var highlighter: MatchHighlighter?
    private weak var pdfView: PDFView?
    private weak var page: PDFPage?
    private let pageIndex: Int

    init(highlighter: MatchHighlighter, pdfView: PDFView, page: PDFPage, pageIndex: Int) {
        self.highlighter = highlighter
        self.pdfView = pdfView
        self.page = page
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        #if os(macOS)
        // Its own layer, redrawn at the new size rather than stretched, so it
        // stays sharp when zooming whether or not PDFKit's views are layer-backed.
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        #else
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw   // stay sharp when zooming
        isUserInteractionEnabled = false
        #endif
    }

    func redraw() {
        #if os(macOS)
        needsDisplay = true
        #else
        setNeedsDisplay()
        #endif
    }

    #if os(macOS)
    override var isOpaque: Bool { false }

    /// Clicks go through to the page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // Zooming resizes the overlay with its page; draw again at the new size.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func setBoundsSize(_ newSize: NSSize) {
        super.setBoundsSize(newSize)
        needsDisplay = true
    }

    /// Moving to a display with another scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }
    #endif

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let highlighter, let pdfView, let page else { return }
        let (matches, current) = highlighter.highlights(forPage: pageIndex)
        // Through the PDF view, which knows the page's rotation, crop and zoom.
        func fill(_ pageRect: CGRect, _ color: PlatformColor) {
            let box = convert(pdfView.convert(pageRect, from: page), from: pdfView).insetBy(dx: -1.5, dy: -1)
            color.setFill()
            #if os(macOS)
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            #else
            UIBezierPath(roundedRect: box, cornerRadius: 2).fill()
            #endif
        }
        matches.forEach { fill($0, MatchHighlighter.matchColor) }
        current.forEach { fill($0, MatchHighlighter.currentColor) }
    }
}
