//
//  NightPDFView.swift
//  NightPdf
//

import PDFKit
import UIKit.UIGestureRecognizerSubclass

/// PDFView that reports destination jumps (link taps, outline, go to page)
/// before they happen, so the reader can offer a way back.
final class NightPDFView: PDFView {
    var willJump: ((PDFDestination) -> Void)?
    /// Called when a finger goes down anywhere in the window (true) and when
    /// the last one lifts (false).
    var touchChanged: ((Bool) -> Void)?
    let highlighter = MatchHighlighter()
    private let touchObserver = TouchObserver()

    /// Space left between the navigation bar and a jump target.
    private static let jumpMargin: CGFloat = 12
    /// How much of the visible height one step scrolls, leaving a few lines
    /// of overlap to read on from.
    private static let stepFraction: CGFloat = 0.8

    override func go(to destination: PDFDestination) {
        willJump?(destination)
        super.go(to: destination)
        revealBelowTopBar(destination)
    }

    /// PDFView scrolls a destination to the very top of its frame, which sits
    /// under the navigation bar. Nudge it down so the target shows below the bar.
    private func revealBelowTopBar(_ destination: PDFDestination) {
        guard let page = destination.page, let scrollView,
              displayMode == .singlePageContinuous || displayMode == .twoUpContinuous,
              destination.point.y != kPDFDestinationUnspecifiedValue
        else { return }
        layoutIfNeeded()
        let target = convert(CGPoint(x: 0, y: destination.point.y), from: page)
        let insets = scrollView.adjustedContentInset
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height + insets.bottom, -insets.top)
        var offset = scrollView.contentOffset
        offset.y = min(max(offset.y + target.y - (topInset + Self.jumpMargin), -insets.top), maxY)
        scrollView.setContentOffset(offset, animated: false)
    }

    /// Scrolls a search match into the upper part of the screen, clear of the
    /// search bar and keyboard. Leaves it alone if it's already there.
    func reveal(_ selection: PDFSelection) {
        guard let page = selection.pages.first else { return }
        guard let scrollView, displayMode == .singlePageContinuous || displayMode == .twoUpContinuous else {
            go(to: page)   // paged layouts show one page (or spread) at a time
            return
        }
        layoutIfNeeded()
        let match = convert(selection.bounds(for: page), from: page)
        let top = topInset + Self.jumpMargin
        let clear = top...(bounds.height * 0.45)   // the keyboard and bar cover the rest
        let fitsHorizontally = match.minX >= bounds.minX && match.maxX <= bounds.maxX
        if clear.contains(match.minY) && clear.contains(match.maxY) && fitsHorizontally { return }

        let insets = scrollView.adjustedContentInset
        var offset = scrollView.contentOffset
        offset.y += match.midY - (top + (clear.upperBound - top) * 0.4)
        offset.y = min(max(offset.y, -insets.top),
                       max(scrollView.contentSize.height - scrollView.bounds.height + insets.bottom, -insets.top))
        if !fitsHorizontally {
            offset.x += match.midX - bounds.midX
            offset.x = min(max(offset.x, -insets.left),
                           max(scrollView.contentSize.width - scrollView.bounds.width + insets.right, -insets.left))
        }
        scrollView.setContentOffset(offset, animated: true)
    }

    /// Moves about a screenful forward or back: scrolls the continuous layouts,
    /// turns the page in the paged one.
    func step(forward: Bool) {
        guard let scrollView, displayMode == .singlePageContinuous || displayMode == .twoUpContinuous else {
            DebugLog.scroll("""
                step \(forward ? "forward" : "back") by page: mode \(displayMode.rawValue), \
                scroll view \(scrollView != nil), can go \(forward ? canGoToNextPage : canGoToPreviousPage)
                """)
            if forward { goToNextPage(nil) } else { goToPreviousPage(nil) }
            return
        }
        let insets = scrollView.adjustedContentInset
        let visible = scrollView.bounds.height - insets.top - insets.bottom
        var offset = scrollView.contentOffset
        offset.y += (forward ? 1 : -1) * visible * Self.stepFraction
        offset.y = min(max(offset.y, -insets.top),
                       max(scrollView.contentSize.height - scrollView.bounds.height + insets.bottom, -insets.top))
        DebugLog.scroll("""
            step \(forward ? "forward" : "back"): offset \(Int(scrollView.contentOffset.y)) → \(Int(offset.y)) \
            of \(Int(scrollView.contentSize.height)), visible \(Int(visible)), \
            \(offset.y == scrollView.contentOffset.y ? "already at the end" : "scrolling")
            """)
        scrollView.setContentOffset(offset, animated: true)
    }

    // Touches anywhere in the window, including the SwiftUI bars and sheets.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        window?.removeGestureRecognizer(touchObserver)
        touchObserver.touchChanged = { [weak self] isDown in self?.touchChanged?(isDown) }
        newWindow?.addGestureRecognizer(touchObserver)
    }

    /// The point at the top-left of the area not covered by the navigation bar.
    /// (`currentDestination` doesn't track the visible top reliably.)
    var visibleDestination: PDFDestination? {
        let point = CGPoint(x: bounds.minX + 1, y: topInset + Self.jumpMargin)
        guard let page = page(for: point, nearest: true) else { return nil }
        return PDFDestination(page: page, at: convert(point, to: page))
    }

    private var topInset: CGFloat {
        scrollView?.adjustedContentInset.top ?? safeAreaInsets.top
    }

    var navigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let next = responder?.next {
            if let controller = next as? UIViewController, let navigation = controller.navigationController {
                return navigation
            }
            responder = next
        }
        return nil
    }

    private var scrollView: UIScrollView? {
        func find(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView { return scrollView }
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        return find(in: self)
    }

    /// Re-renders page tiles, e.g. after the page colors change.
    func redrawPages() {
        func invalidate(_ view: UIView) {
            view.setNeedsDisplay()
            view.layer.setNeedsDisplay()
            view.subviews.forEach(invalidate)
        }
        invalidate(self)
        layoutDocumentView()
    }
}

/// Reports touches without taking part in gesture handling.
private final class TouchObserver: UIGestureRecognizer {
    var touchChanged: ((Bool) -> Void)?

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ other: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by other: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        touchChanged?(true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finishIfLifted(event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finishIfLifted(event)
    }

    private func finishIfLifted(_ event: UIEvent) {
        let lifted = event.allTouches?.allSatisfy { $0.phase == .ended || $0.phase == .cancelled } ?? true
        guard lifted else { return }
        touchChanged?(false)
        state = .failed   // resets to .possible for the next touch
    }
}
