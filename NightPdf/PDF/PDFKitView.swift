//
//  PDFKitView.swift
//  NightPdf
//

import PDFKit
import SwiftUI

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
        view.pageOverlayViewProvider = view.highlighter
        view.pageBreakMargins = UIEdgeInsets(top: 6, left: 0, bottom: 6, right: 0)

        model.attach(view)
        model.apply(invertsPages: invertsPages)
        model.apply(layout: layout)
        view.document = model.document
        view.autoScales = true

        view.willJump = { [weak model] destination in model?.willJump(to: destination) }
        view.touchChanged = { [weak model] isDown in model?.knocks.touchChanged(isDown: isDown) }
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
}
