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
    static let matchColor = UIColor.systemYellow.withAlphaComponent(0.3)
    static let currentColor = UIColor.systemOrange.withAlphaComponent(0.55)

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
        changed.forEach { overlays[$0]?.setNeedsDisplay() }
    }

    func removeAll() {
        matches = [:]
        current = nil
        overlays.values.forEach { $0.setNeedsDisplay() }
    }

    func setCurrent(_ rects: [CGRect], onPage pageIndex: Int) {
        let old = current?.pageIndex
        current = (pageIndex, rects)
        for page in Set([old, pageIndex].compactMap { $0 }) {
            overlays[page]?.setNeedsDisplay()
        }
    }

    fileprivate func highlights(forPage pageIndex: Int) -> (matches: [CGRect], current: [CGRect]) {
        (matches[pageIndex] ?? [], current?.pageIndex == pageIndex ? current?.rects ?? [] : [])
    }

    // MARK: - PDFPageOverlayViewProvider

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let pageIndex = view.document?.index(for: page) else { return nil }
        let overlay = MatchOverlayView(highlighter: self, pdfView: view, page: page, pageIndex: pageIndex)
        overlays[pageIndex] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        guard let pageIndex = pdfView.document?.index(for: page) else { return }
        overlays[pageIndex] = nil
    }
}

private final class MatchOverlayView: UIView {
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
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw   // stay sharp when zooming
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draw(_ rect: CGRect) {
        guard let highlighter, let pdfView, let page else { return }
        let (matches, current) = highlighter.highlights(forPage: pageIndex)
        // Through the PDF view, which knows the page's rotation, crop and zoom.
        func fill(_ pageRect: CGRect, _ color: UIColor) {
            let box = convert(pdfView.convert(pageRect, from: page), from: pdfView).insetBy(dx: -1.5, dy: -1)
            color.setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 2).fill()
        }
        matches.forEach { fill($0, MatchHighlighter.matchColor) }
        current.forEach { fill($0, MatchHighlighter.currentColor) }
    }
}
