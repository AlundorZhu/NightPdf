//
//  PDFKitView.swift
//  NightPdf
//

import PDFKit
import SwiftUI

/// PDFView that reports destination jumps (link taps, outline, go to page)
/// before they happen, so the reader can offer a way back.
final class NightPDFView: PDFView {
    var willJump: ((PDFDestination) -> Void)?

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

struct PDFKitView: UIViewRepresentable {
    let model: ReaderModel
    let layout: PageLayout
    let invertsPages: Bool
    let hidesBars: Bool

    func makeUIView(context: Context) -> NightPDFView {
        let view = NightPDFView()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .secondarySystemBackground
        }
        view.isFindInteractionEnabled = true
        view.pageBreakMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        model.attach(view)
        model.apply(invertsPages: invertsPages)
        model.apply(layout: layout)
        view.document = model.document
        view.autoScales = true

        view.willJump = { [weak model] destination in model?.willJump(to: destination) }
        context.coordinator.observe(view)
        return view
    }

    func updateUIView(_ view: NightPDFView, context: Context) {
        model.apply(layout: layout)
        model.apply(invertsPages: invertsPages)
        // DocumentGroup's navigation controller ignores SwiftUI's toolbar visibility.
        if let navigation = view.navigationController, navigation.isNavigationBarHidden != hidesBars {
            navigation.setNavigationBarHidden(hidesBars, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let model: ReaderModel

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: NightPDFView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)

            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }

        @objc private func pageChanged() {
            model.pageDidChange()
        }

        @objc private func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? PDFView, !isLink(at: gesture.location(in: view), in: view) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                model.isChromeHidden.toggle()
            }
        }

        private func isLink(at location: CGPoint, in view: PDFView) -> Bool {
            guard let page = view.page(for: location, nearest: false),
                  let annotation = page.annotation(at: view.convert(location, to: page))
            else { return false }
            return annotation.type == "Link" || annotation.url != nil || annotation.destination != nil || annotation.action != nil
        }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            // A tap that dismisses a text selection shouldn't also toggle the bars.
            guard let view = gesture.view as? PDFView else { return true }
            return view.currentSelection?.string?.isEmpty ?? true
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool {
            // Wait for double-tap-to-zoom to fail before toggling the bars.
            (other as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }
    }
}
