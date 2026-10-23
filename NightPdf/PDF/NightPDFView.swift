//
//  NightPDFView.swift
//  NightPdf
//

import PDFKit

/// PDFView that reports destination jumps (link taps, outline, go to page)
/// before they happen, so the reader can offer a way back.
///
/// The parts that differ by platform (scrolling, insets, window activity)
/// are in NightPDFView+iOS.swift and NightPDFView+macOS.swift.
final class NightPDFView: PDFView {
    var willJump: ((PDFDestination) -> Void)?
    /// Called when the window's scene becomes active (true) or stops being
    /// active, e.g. in the background or app switcher. On the Mac, when the
    /// app becomes or stops being active, and as the window closes or the
    /// app quits. (SwiftUI's `scenePhase` doesn't reach DocumentGroup's
    /// document view.)
    var sceneActivityChanged: ((Bool) -> Void)?
    /// Set up by the platform files as the view moves to a window.
    var sceneObservers: [NSObjectProtocol] = []
    let overlays = PageOverlayProvider()

    #if os(iOS)
    /// Height of the floating bars over the bottom of the view, beyond the safe
    /// area. The scrolling layouts leave room for it, so the end of the
    /// document can scroll clear of the bars. (The Mac has no bars over the
    /// pages, so PDFKit's own insets are left alone there.)
    var bottomObscuredHeight: CGFloat = 0 {
        didSet {
            guard bottomObscuredHeight != oldValue else { return }
            bottomObscuredHeightChanged()
        }
    }
    /// Called when a finger goes down anywhere in the window (true) and when
    /// the last one lifts (false).
    var touchChanged: ((Bool) -> Void)?
    let touchObserver = TouchObserver()
    weak var cachedScrollView: UIScrollView?
    #else
    weak var cachedScrollView: NSScrollView?
    #endif

    /// Space left between the top of the visible area and a jump target.
    static let jumpMargin: CGFloat = 12

    var isScrollingLayout: Bool {
        displayMode == .singlePageContinuous || displayMode == .twoUpContinuous
    }

    override func go(to destination: PDFDestination) {
        willJump?(destination)
        super.go(to: destination)
        alignBelowTop(destination)
    }

    override var displayMode: PDFDisplayMode {
        didSet { cachedScrollView = nil }
    }

    override var document: PDFDocument? {
        didSet { cachedScrollView = nil }
    }

    /// Re-renders page tiles, e.g. after the page colors change.
    func redrawPages() {
        func invalidate(_ view: PlatformView) {
            #if os(macOS)
            view.needsDisplay = true
            view.layer?.setNeedsDisplay()
            #else
            view.setNeedsDisplay()
            view.layer.setNeedsDisplay()
            #endif
            view.subviews.forEach(invalidate)
        }
        invalidate(self)
        layoutDocumentView()
    }
}
