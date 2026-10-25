//
//  NightPDFView+iOS.swift
//  NightPdf
//

#if os(iOS)
import PDFKit
import UIKit.UIGestureRecognizerSubclass

extension NightPDFView {
    /// How much of the visible height one step scrolls, leaving a few lines
    /// of overlap to read on from.
    private static let stepFraction: CGFloat = 0.8

    /// PDFView scrolls a destination to the very top of its frame, which sits
    /// under the navigation bar. Nudge it down so the target shows below the bar.
    /// An entry with no spot of its own goes to the top of its page.
    func alignBelowTop(_ destination: PDFDestination) {
        guard let page = destination.page, let scrollView, isScrollingLayout else { return }
        layoutIfNeeded()
        let y = destination.point.y == kPDFDestinationUnspecifiedValue ? page.bounds(for: displayBox).maxY : destination.point.y
        let target = convert(CGPoint(x: 0, y: y), from: page)
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
        guard let scrollView, isScrollingLayout else {
            go(to: page)   // paged layouts show one page (or spread) at a time
            return
        }
        layoutIfNeeded()
        let match = convert(selection.bounds(for: page), from: page)
        // A match PDFKit can't place comes back as a null rect, which converts to NaN.
        guard match.isFinite else {
            go(to: page)
            return
        }
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
        guard let scrollView, isScrollingLayout else {
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

    // MARK: - Bottom inset

    func bottomObscuredHeightChanged() {
        guard let scrollView else { return }
        applyBottomInset()
        // Past the end once the room is gone: settle back rather than jump on the next touch.
        let insets = scrollView.adjustedContentInset
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height + insets.bottom, -insets.top)
        if scrollView.contentOffset.y > maxY {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: maxY), animated: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyBottomInset()   // the scroll view may be new, or PDFKit may have reset it
    }

    private func applyBottomInset() {
        guard let scrollView else { return }
        let inset = isScrollingLayout ? bottomObscuredHeight : 0
        guard scrollView.contentInset.bottom != inset else { return }
        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }

    // MARK: - Window

    // Touches anywhere in the window, including the SwiftUI bars and sheets.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        window?.removeGestureRecognizer(touchObserver)
        touchObserver.touchChanged = { [weak self] isDown in self?.touchChanged?(isDown) }
        newWindow?.addGestureRecognizer(touchObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sceneObservers.forEach(NotificationCenter.default.removeObserver)
        sceneObservers = []
        guard let scene = window?.windowScene else { return }
        sceneActivityChanged?(scene.activationState == .foregroundActive)
        for (name, isActive) in [(UIScene.didActivateNotification, true), (UIScene.willDeactivateNotification, false)] {
            sceneObservers.append(NotificationCenter.default.addObserver(forName: name, object: scene, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.sceneActivityChanged?(isActive) }
            })
        }
    }

    // MARK: - Geometry

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

    /// PDFKit's scroll view, looked up again when the layout changes, since
    /// switching to and from the page view controller swaps the views.
    private var scrollView: UIScrollView? {
        if let cachedScrollView, cachedScrollView.isDescendant(of: self) { return cachedScrollView }
        func find(in view: UIView) -> UIScrollView? {
            for subview in view.subviews {
                if let scrollView = subview as? UIScrollView { return scrollView }
                if let found = find(in: subview) { return found }
            }
            return nil
        }
        cachedScrollView = find(in: self)
        return cachedScrollView
    }

    override func usePageViewController(_ enable: Bool, withViewOptions viewOptions: [AnyHashable: Any]? = nil) {
        super.usePageViewController(enable, withViewOptions: viewOptions)
        cachedScrollView = nil
    }
}

/// Reports touches without taking part in gesture handling.
final class TouchObserver: UIGestureRecognizer {
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
#endif
