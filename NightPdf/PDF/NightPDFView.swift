//
//  NightPDFView.swift
//  NightPdf
//

import PDFKit

/// PDFView that reports destination jumps (link taps, outline, go to page)
/// before they happen, so the reader can offer a way back.
final class NightPDFView: PDFView {
    var willJump: ((PDFDestination) -> Void)?
    let highlighter = MatchHighlighter()

    /// Space left between the navigation bar and a jump target.
    private static let jumpMargin: CGFloat = 12

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
