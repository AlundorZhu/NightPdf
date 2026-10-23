//
//  PDFKitView.swift
//  NightPdf
//

import PDFKit
import SwiftUI

struct PDFKitView {
    let model: ReaderModel
    let layout: PageLayout
    let invertsPages: Bool
    #if os(iOS)
    let hidesBars: Bool
    /// See `NightPDFView.bottomObscuredHeight`.
    let bottomObscuredHeight: CGFloat
    #endif

    func makeView(context: Context) -> NightPDFView {
        let view = NightPDFView()
        #if os(macOS)
        view.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black : .underPageBackgroundColor
        }
        view.pageBreakMargins = NSEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        #else
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .secondarySystemBackground
        }
        view.pageBreakMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)
        #endif
        view.pageOverlayViewProvider = view.overlays

        model.attach(view)
        model.apply(invertsPages: invertsPages)
        model.apply(layout: layout)
        view.document = model.document
        view.autoScales = true

        view.willJump = { [weak model] destination in model?.willJump(to: destination) }
        #if os(iOS)
        view.touchChanged = { [weak model] isDown in model?.knocks.touchChanged(isDown: isDown) }
        #endif
        view.sceneActivityChanged = { [weak model] isActive in model?.sceneActivityChanged(isActive) }
        context.coordinator.observe(view)
        return view
    }

    func updateView(_ view: NightPDFView, context: Context) {
        model.apply(layout: layout)
        model.apply(invertsPages: invertsPages)
        #if os(iOS)
        view.bottomObscuredHeight = bottomObscuredHeight
        // DocumentGroup's navigation controller ignores SwiftUI's toolbar visibility.
        if let navigation = view.navigationController, navigation.isNavigationBarHidden != hidesBars {
            navigation.setNavigationBarHidden(hidesBars, animated: true)
        }
        #endif
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    final class Coordinator: NSObject {
        let model: ReaderModel

        init(model: ReaderModel) {
            self.model = model
        }

        func observe(_ view: NightPDFView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageChanged), name: .PDFViewPageChanged, object: view)

            // On the Mac, clicks select text; there are no bars to hide.
            #if os(iOS)
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
            #endif
        }

        @objc private func pageChanged() {
            model.pageDidChange()
        }
    }
}

#if os(macOS)
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> NightPDFView {
        makeView(context: context)
    }

    func updateNSView(_ view: NightPDFView, context: Context) {
        updateView(view, context: context)
    }
}
#else
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> NightPDFView {
        makeView(context: context)
    }

    func updateUIView(_ view: NightPDFView, context: Context) {
        updateView(view, context: context)
    }
}

extension PDFKitView.Coordinator: UIGestureRecognizerDelegate {
    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        // While searching, a tap just puts the keyboard away so the page can be read.
        if model.search?.isActive == true {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            return
        }
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
#endif
