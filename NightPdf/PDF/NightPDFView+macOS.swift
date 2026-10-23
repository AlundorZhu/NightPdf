//
//  NightPDFView+macOS.swift
//  NightPdf
//

#if os(macOS)
import AppKit
import PDFKit

extension NightPDFView {
    /// Room left around a search match scrolled into view.
    private static let revealMargin: CGFloat = 8

    /// PDFView scrolls a destination to the very top edge. Line it up with the
    /// reading line instead, `jumpMargin` below the top, which is also where
    /// `visibleDestination` reads the position: what's saved comes back to the
    /// same spot.
    ///
    /// Jumps can come in the middle of a layout pass (a layout change from
    /// SwiftUI goes back to the page), where forcing layout isn't allowed; then
    /// the alignment waits for the pass to finish.
    func alignBelowTop(_ destination: PDFDestination, isDeferred: Bool = false) {
        guard let page = destination.page, let scrollView, let documentView, isScrollingLayout,
              destination.point.y != kPDFDestinationUnspecifiedValue
        else { return }
        if !isDeferred && (needsLayout || documentView.needsLayout) {
            DispatchQueue.main.async { [weak self] in self?.alignBelowTop(destination, isDeferred: true) }
            return
        }
        let clipView = scrollView.contentView
        let target = convert(CGPoint(x: 0, y: destination.point.y), from: page)
        let line = readingLine(in: scrollView)
        // Both in the clip view's coordinates, so the move is right whichever way y points.
        let delta = clipView.convert(target, from: self).y - clipView.convert(line, from: documentView).y
        var visible = clipView.bounds
        visible.origin.y += delta
        clipView.scroll(to: clipView.constrainBoundsRect(visible).origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Scrolls a search match into view. Leaves it alone if it's already there.
    func reveal(_ selection: PDFSelection) {
        guard let page = selection.pages.first else { return }
        guard let documentView, isScrollingLayout else {
            go(to: page)   // paged layouts show one page (or spread) at a time
            return
        }
        let match = documentView.convert(convert(selection.bounds(for: page), from: page), from: self)
        documentView.scrollToVisible(match.insetBy(dx: -Self.revealMargin, dy: -Self.revealMargin))
    }

    // MARK: - Window

    /// Sheets and other windows take key status, so it's the app's activity
    /// that counts, not the window's; otherwise opening the contents would
    /// save the position as if the reader had left.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
        sceneObservers = []
        guard let window else { return }
        sceneActivityChanged?(NSApp.isActive)
        let changes: [(Notification.Name, AnyObject?, Bool)] = [
            (NSApplication.didBecomeActiveNotification, nil, true),
            (NSApplication.willResignActiveNotification, nil, false),
            (NSApplication.willTerminateNotification, nil, false),
            (NSWindow.willCloseNotification, window, false),
        ]
        for (name, object, isActive) in changes {
            sceneObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.sceneActivityChanged?(isActive) }
            })
        }
    }

    // MARK: - Geometry

    /// The point at the top-left of the visible area, `jumpMargin` down, where
    /// `go(to:)` puts a destination. (`currentDestination` doesn't track the
    /// visible top reliably.)
    var visibleDestination: PDFDestination? {
        let point: CGPoint
        if let scrollView, let documentView {
            point = convert(readingLine(in: scrollView), from: documentView)
        } else {
            point = CGPoint(x: bounds.minX + 1, y: isFlipped ? bounds.minY + 1 : bounds.maxY - 1)
        }
        guard let page = page(for: point, nearest: true) else { return nil }
        return PDFDestination(page: page, at: convert(point, to: page))
    }

    /// `jumpMargin` below the top of what the scroll view shows, past any top
    /// inset, in the document view's coordinates. Worked out in the clip view,
    /// whose bounds are the visible part of the document and which is flipped
    /// whenever the document view is.
    private func readingLine(in scrollView: NSScrollView) -> CGPoint {
        let clipView = scrollView.contentView
        let visible = clipView.bounds
        let down = scrollView.contentInsets.top + Self.jumpMargin
        let line = CGPoint(x: visible.minX + 1, y: clipView.isFlipped ? visible.minY + down : visible.maxY - down)
        return documentView?.convert(line, from: clipView) ?? line
    }

    /// PDFKit's scroll view, looked up again when the layout changes.
    private var scrollView: NSScrollView? {
        if let cachedScrollView, cachedScrollView.isDescendant(of: self) { return cachedScrollView }
        func find(in view: NSView) -> NSScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? NSScrollView { return scrollView }
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        cachedScrollView = find(in: self)
        return cachedScrollView
    }
}
#endif
