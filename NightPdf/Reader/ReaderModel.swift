//
//  ReaderModel.swift
//  NightPdf
//

import os
import PDFKit
import SwiftUI

/// A place in the document the reader jumped away from.
struct ReturnPoint {
    let destination: PDFDestination
    let pageIndex: Int
}

struct OutlineNode: Identifiable {
    let id: Int
    let title: String
    let destination: PDFDestination?
    let children: [OutlineNode]?
}

@Observable
final class ReaderModel {
    let document: NightDocument?
    let fileURL: URL?
    private let data: Data

    @ObservationIgnored weak var pdfView: NightPDFView?
    @ObservationIgnored private var suppressHistory = false
    @ObservationIgnored private var appliedLayout: PageLayout?

    private(set) var pageCount = 0
    private(set) var currentPageIndex = 0
    private(set) var returnStack: [ReturnPoint] = []
    private(set) var outline: [OutlineNode] = []
    private(set) var invertsPages = false
    var isChromeHidden = false
    private(set) var isSearching = false

    init(data: Data, fileURL: URL?) {
        self.data = data
        self.fileURL = fileURL
        // Password-protected files aren't supported; they show as unopenable.
        let document = Signposts.signposter.withIntervalSignpost("Load Document") {
            NightDocument(data: data)
        }.flatMap { $0.isLocked ? nil : $0 }
        self.document = document
        guard let document else { return }
        pageCount = document.pageCount
        outline = Signposts.signposter.withIntervalSignpost("Build Outline") {
            Self.outlineNodes(of: document.outlineRoot)
        }
        currentPageIndex = min(defaults.integer(forKey: key("lastPage")), max(pageCount - 1, 0))
    }

    func attach(_ view: NightPDFView) {
        pdfView = view
        let start = currentPageIndex
        guard start > 0 else { return }
        // Wait for the first layout pass, otherwise PDFView ignores the jump.
        DispatchQueue.main.async { [weak self] in
            guard let self, let page = self.document?.page(at: start) else { return }
            self.withoutHistory { view.go(to: page) }
        }
    }

    // MARK: - Display settings

    func apply(layout: PageLayout) {
        guard let view = pdfView, layout != appliedLayout else { return }
        let isFirstLayout = appliedLayout == nil
        appliedLayout = layout
        let page = view.currentPage

        switch layout {
        case .continuous:
            view.usePageViewController(false)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.displaysAsBook = false
        case .paged:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.displaysAsBook = false
            view.usePageViewController(true)
        case .twoUp:
            view.usePageViewController(false)
            view.displayMode = .twoUpContinuous
            view.displayDirection = .vertical
            view.displaysAsBook = true
        }
        view.autoScales = true

        if !isFirstLayout, let page {
            withoutHistory { view.go(to: page) }
        }
    }

    func apply(invertsPages inverts: Bool) {
        guard let document, inverts != invertsPages else { return }
        document.invertsPages = inverts
        invertsPages = inverts
        guard let view = pdfView else { return }
        view.pageShadowsEnabled = !inverts
        view.redrawPages()
    }

    // MARK: - Navigation

    func pageDidChange() {
        guard let view = pdfView, let page = view.currentPage, let document else { return }
        currentPageIndex = document.index(for: page)
        defaults.set(currentPageIndex, forKey: key("lastPage"))
    }

    /// Called by the PDF view before every destination jump, including link taps.
    func willJump(to destination: PDFDestination) {
        guard !suppressHistory,
              let view = pdfView, let document,
              let from = view.visibleDestination,
              let fromPage = from.page, let toPage = destination.page,
              fromPage != toPage
        else { return }

        returnStack.append(ReturnPoint(destination: from, pageIndex: document.index(for: fromPage)))
        if returnStack.count > 50 { returnStack.removeFirst() }
        isChromeHidden = false
    }

    func go(toPage index: Int) {
        guard let page = document?.page(at: index) else { return }
        let bounds = page.bounds(for: .cropBox)
        go(to: PDFDestination(page: page, at: CGPoint(x: bounds.minX, y: bounds.maxY)))
    }

    func go(to destination: PDFDestination) {
        pdfView?.go(to: destination)
    }

    func returnToPrevious() {
        guard let point = returnStack.popLast() else { return }
        withoutHistory { pdfView?.go(to: point.destination) }
    }

    func clearReturnStack() {
        returnStack.removeAll()
    }

    private func withoutHistory(_ action: () -> Void) {
        suppressHistory = true
        action()
        suppressHistory = false
    }

    // MARK: - Search, printing

    func showFind() {
        guard let interaction = pdfView?.findInteraction else { return }
        isChromeHidden = false
        isSearching = true
        interaction.presentFindNavigator(showingReplace: false)

        // PDFView owns the find delegate, so watch for the navigator closing.
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self, weak interaction] timer in
            MainActor.assumeIsolated {
                guard let self else { return timer.invalidate() }
                if interaction?.isFindNavigatorVisible != true {
                    timer.invalidate()
                    withAnimation { self.isSearching = false }
                }
            }
        }
    }

    func printDocument() {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
    }

    // MARK: - Helpers

    func thumbnail(forPage index: Int, fitting size: CGSize) async -> UIImage? {
        guard let page = document?.page(at: index) as? NightPage else { return nil }
        return await Self.renderThumbnail(of: page, fitting: size)
    }

    /// Off the main thread, so scrolling the page grid doesn't stall on rendering.
    @concurrent
    private nonisolated static func renderThumbnail(of page: NightPage, fitting size: CGSize) async -> UIImage? {
        guard !Task.isCancelled else { return nil }   // scrolled away before its turn
        return page.thumbnail(fitting: size)
    }

    func pageIndex(of node: OutlineNode) -> Int? {
        guard let document, let page = node.destination?.page else { return nil }
        return document.index(for: page)
    }

    private var defaults: UserDefaults { .standard }

    private func key(_ name: String) -> String {
        "\(name):\(fileURL?.path(percentEncoded: false) ?? "untitled")"
    }

    /// Resolving a destination's page is slow (~0.1 ms each), so that waits
    /// until a row asks for it in `pageIndex(of:)`.
    private static func outlineNodes(of item: PDFOutline?) -> [OutlineNode] {
        var nextID = 0
        func build(_ item: PDFOutline) -> [OutlineNode] {
            (0..<item.numberOfChildren).compactMap { item.child(at: $0) }.map { child in
                nextID += 1
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                let children = build(child)
                return OutlineNode(
                    id: nextID,
                    title: child.label ?? "Untitled",
                    destination: destination,
                    children: children.isEmpty ? nil : children
                )
            }
        }
        return item.map(build) ?? []
    }
}
