//
//  PageOverlays.swift
//  NightPdf
//

import PDFKit
import QuartzCore

/// Makes the view laid over each page: in dark mode the inverted page itself,
/// and above it the search highlights.
///
/// Drawing the night page in the overlay, rather than in the page, keeps
/// PDFKit's white page backing out of sight: it shows wherever PDFKit's
/// tiles aren't drawn yet, which is every page scrolling into view and the
/// whole page while a zoom re-renders. The overlay is opaque and dark from the
/// moment it exists. (PDFKit's own highlights render into the page, where
/// the inversion turns them into barely visible tinted text.)
final class PageOverlayProvider: NSObject, PDFPageOverlayViewProvider {
    /// Translucent so the matched word stays readable on light and dark pages.
    static let matchColor = PlatformColor.systemYellow.withAlphaComponent(0.3)
    static let currentColor = PlatformColor.systemOrange.withAlphaComponent(0.55)

    /// Whether the overlays draw the inverted page.
    var invertsPages = false {
        didSet {
            guard invertsPages != oldValue else { return }
            previews.removeAllObjects()
            overlays.values.forEach { $0.invertsPages = invertsPages }
        }
    }

    /// Line rects in page space, by page index.
    private var matches: [Int: [CGRect]] = [:]
    private var current: (pageIndex: Int, rects: [CGRect])?
    private var overlays: [Int: PageOverlayView] = [:]
    /// Whole-page renders shown under the tiles until they're drawn, by page
    /// index. Costs are pixel counts.
    fileprivate let previews: NSCache<NSNumber, CGImage> = {
        let cache = NSCache<NSNumber, CGImage>()
        cache.totalCostLimit = 16_000_000   // about 64 MB
        return cache
    }()

    /// Adds matches as the search finds them; only pages that changed redraw.
    func add(_ newMatches: [(pageIndex: Int, rects: [CGRect])]) {
        var changed: Set<Int> = []
        for (pageIndex, rects) in newMatches {
            matches[pageIndex, default: []].append(contentsOf: rects)
            changed.insert(pageIndex)
        }
        changed.forEach { overlays[$0]?.redrawHighlights() }
    }

    func removeAll() {
        matches = [:]
        current = nil
        overlays.values.forEach { $0.redrawHighlights() }
    }

    func setCurrent(_ rects: [CGRect], onPage pageIndex: Int) {
        let old = current?.pageIndex
        current = (pageIndex, rects)
        for page in Set([old, pageIndex].compactMap { $0 }) {
            overlays[page]?.redrawHighlights()
        }
    }

    fileprivate func highlights(forPage pageIndex: Int) -> (matches: [CGRect], current: [CGRect]) {
        (matches[pageIndex] ?? [], current?.pageIndex == pageIndex ? current?.rects ?? [] : [])
    }

    // MARK: - PDFPageOverlayViewProvider

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> PlatformView? {
        guard let pageIndex = view.document?.index(for: page) else { return nil }
        let overlay = PageOverlayView(provider: self, pdfView: view, page: page, pageIndex: pageIndex)
        overlay.invertsPages = invertsPages
        overlays[pageIndex] = overlay
        return overlay
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: PlatformView, for page: PDFPage) {
        // A layout change can make the page's new overlay before ending the old one.
        guard let pageIndex = pdfView.document?.index(for: page), overlays[pageIndex] === overlayView else { return }
        overlays[pageIndex] = nil
    }
}

/// The view over one page. In dark mode it's opaque: a dark background, a
/// quick whole-page render over that, and sharp tiles of the page over
/// both as they're drawn. The highlights are a layer of their own on top.
private final class PageOverlayView: PlatformView {
    private weak var provider: PageOverlayProvider?
    private weak var pdfView: PDFView?
    private weak var page: PDFPage?
    private let pageIndex: Int
    private let preview = CALayer()
    private let tiles = NightTileLayer()
    private let highlights = HighlightLayer()
    private var tileDrawer: NightTileDrawer?
    private var previewTask: Task<Void, Never>?

    /// Up to this many pixels across, the preview is a fair stand-in for the tiles.
    private static let previewWidth: CGFloat = 1024

    var invertsPages = false {
        didSet {
            guard invertsPages != oldValue else { return }
            applyMode()
        }
    }

    init(provider: PageOverlayProvider, pdfView: PDFView, page: PDFPage, pageIndex: Int) {
        self.provider = provider
        self.pdfView = pdfView
        self.page = page
        self.pageIndex = pageIndex
        super.init(frame: .zero)
        #if os(macOS)
        wantsLayer = true
        #else
        backgroundColor = .clear
        isUserInteractionEnabled = false
        #endif
        preview.contentsGravity = .resize
        preview.isHidden = true
        tiles.isHidden = true
        highlights.delegate = highlightDrawer
        highlights.needsDisplayOnBoundsChange = true   // stay sharp when zooming
        highlightDrawer.view = self
        if let night = page as? NightPage {
            let drawer = NightTileDrawer(page: night, box: pdfView.displayBox)
            tileDrawer = drawer
            tiles.delegate = drawer
        }
        for layer in [preview, tiles, highlights] {
            layer.contentsScale = Self.screenScale
            hostLayer.addSublayer(layer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        previewTask?.cancel()
    }

    private let highlightDrawer = HighlightDrawer()

    private var hostLayer: CALayer {
        #if os(macOS)
        layer!
        #else
        layer
        #endif
    }

    private static var screenScale: CGFloat {
        #if os(macOS)
        NSScreen.main?.backingScaleFactor ?? 2
        #else
        UIScreen.main.scale
        #endif
    }

    func redrawHighlights() {
        highlights.setNeedsDisplay()
    }

    private func applyMode() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer.backgroundColor = invertsPages ? NightPage.nightBackground : nil
        preview.isHidden = !invertsPages
        tiles.isHidden = !invertsPages
        if invertsPages {
            tiles.setNeedsDisplay()
            loadPreview()
        } else {
            previewTask?.cancel()
            preview.contents = nil
        }
        CATransaction.commit()
    }

    /// A whole-page render for under the tiles, from the cache or made in the
    /// background.
    private func loadPreview() {
        if let image = provider?.previews.object(forKey: pageIndex as NSNumber) {
            preview.contents = image
            return
        }
        guard previewTask == nil, let page = page as? NightPage else { return }
        let size = CGSize(width: Self.previewWidth, height: Self.previewWidth * 2)
        previewTask = Task { [weak self] in
            let image = await Self.render(page, fitting: size)
            guard !Task.isCancelled, let self else { return }
            previewTask = nil
            guard let image else { return }
            provider?.previews.setObject(image, forKey: pageIndex as NSNumber, cost: image.width * image.height)
            if invertsPages { preview.contents = image }
        }
    }

    @concurrent
    private nonisolated static func render(_ page: NightPage, fitting size: CGSize) async -> CGImage? {
        #if os(macOS)
        page.thumbnail(fitting: size, scale: 1)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        page.thumbnail(fitting: size, scale: 1)?.cgImage
        #endif
    }

    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [preview, tiles, highlights] {
            layer.frame = bounds
        }
        CATransaction.commit()
    }

    #if os(macOS)
    override var isOpaque: Bool { false }

    /// Clicks go through to the page.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    /// Moving to a display with another scale.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? Self.screenScale
        for layer in [preview, tiles, highlights] { layer.contentsScale = scale }
    }
    #else
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutLayers()
    }
    #endif

    // MARK: - Highlights

    /// Draws the highlights into their layer. (A delegate object rather than
    /// the view: a view that is its own layer's delegate is fine, but not of
    /// a sublayer's.)
    private final class HighlightDrawer: NSObject, CALayerDelegate {
        weak var view: PageOverlayView?

        func draw(_ layer: CALayer, in context: CGContext) {
            view?.drawHighlights(in: context)
        }
    }

    private func drawHighlights(in context: CGContext) {
        guard let provider, let pdfView, let page else { return }
        let (matches, current) = provider.highlights(forPage: pageIndex)
        guard !matches.isEmpty || !current.isEmpty else { return }
        // Through the PDF view, which knows the page's rotation, crop and zoom.
        func fill(_ pageRect: CGRect, _ color: PlatformColor) {
            let box = convert(pdfView.convert(pageRect, from: page), from: pdfView).insetBy(dx: -1.5, dy: -1)
            context.setFillColor(color.cgColor)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 2, cornerHeight: 2, transform: nil))
            context.fillPath()
        }
        // The view's coordinates match its layers' on both platforms: the Mac
        // view isn't flipped, and on iOS both have y down.
        matches.forEach { fill($0, PageOverlayProvider.matchColor) }
        current.forEach { fill($0, PageOverlayProvider.currentColor) }
    }
}

/// Tiles of the inverted page, drawn on Core Animation's threads.
private final class NightTileLayer: CATiledLayer {
    override init() {
        super.init()
        tileSize = CGSize(width: 512, height: 512)
        // PDFView zooms by scaling the page's layer rather than resizing it,
        // so the tiles are drawn finer as the zoom goes up: 5 levels in,
        // 32 times the page's natural size, and 2 out.
        levelsOfDetail = 8
        levelsOfDetailBias = 5
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Tiles appear as soon as they're drawn, as PDFKit's do.
    override class func fadeDuration() -> CFTimeInterval { 0 }
}

/// Draws a tile of the page at the layer's size. Unchecked Sendable: called
/// on Core Animation's drawing threads, and holds only the page, which
/// PDFKit draws from its own threads too.
final class NightTileDrawer: NSObject, CALayerDelegate, @unchecked Sendable {
    private let page: NightPage
    private let box: PDFDisplayBox

    init(page: NightPage, box: PDFDisplayBox) {
        self.page = page
        self.box = box
    }

    /// The inversion blends colors, which the tile's own context doesn't do
    /// (it leaves the page as printed on a gray fill), so the tile is drawn
    /// in a bitmap and copied in.
    nonisolated func draw(_ layer: CALayer, in context: CGContext) {
        let bounds = layer.bounds
        let pageSize = page.displaySize(for: box)
        let tile = context.boundingBoxOfClipPath.intersection(bounds)
        guard tile.width > 0, tile.height > 0, pageSize.width > 0, pageSize.height > 0 else { return }
        // Pixels per point of this tile: the screen's scale times the zoom,
        // as the level of detail puts it in the context's transform.
        let ctm = context.ctm
        let scale = (ctm.a * ctm.a + ctm.c * ctm.c).squareRoot()
        guard scale > 0 else { return }
        let width = Int((tile.width * scale).rounded(.up)), height = Int((tile.height * scale).rounded(.up))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        // The bitmap covers the tile; its y axis points up, as the page's does.
        bitmap.scaleBy(x: scale, y: scale)
        #if os(iOS)
        // The layer's y points down: the tile's top is at bounds.height - maxY from the page's bottom.
        bitmap.translateBy(x: -tile.minX, y: -(bounds.height - tile.maxY))
        #else
        bitmap.translateBy(x: -tile.minX, y: -tile.minY)
        #endif
        bitmap.scaleBy(x: bounds.width / pageSize.width, y: bounds.height / pageSize.height)
        bitmap.interpolationQuality = .high
        page.drawForDisplay(with: box, to: bitmap)
        guard let image = bitmap.makeImage() else { return }
        context.saveGState()
        #if os(iOS)
        // UIKit hands over a flipped context; images draw with y up.
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: tile.minX, y: bounds.height - tile.maxY, width: tile.width, height: tile.height))
        #else
        context.draw(image, in: tile)
        #endif
        context.restoreGState()
    }
}

private final class HighlightLayer: CALayer {}
