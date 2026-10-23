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

nonisolated struct OutlineNode: Identifiable {
    let id: Int
    let title: String
    let destination: PDFDestination?
    let children: [OutlineNode]?
}

@Observable
final class ReaderModel {
    let document: NightDocument?
    let search: DocumentSearch?
    let fileURL: URL?
    #if os(iOS)
    let knocks = KnockDetector.shared
    #endif
    private let data: Data

    @ObservationIgnored weak var pdfView: NightPDFView?
    @ObservationIgnored private var suppressHistory = false
    @ObservationIgnored private var appliedLayout: PageLayout?
    /// Where on the restored page to scroll to when the PDF view attaches.
    @ObservationIgnored private var restorePoint: CGPoint?
    /// Until the restore jump runs, the view shows the first page, which mustn't
    /// be saved over the position being restored.
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var positionSave: Task<Void, Never>?
    /// Rendered page thumbnails, by page and size. Costs are pixel counts.
    @ObservationIgnored private let thumbnails: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = 12_000_000   // about 48 MB
        return cache
    }()

    private(set) var pageCount = 0
    private(set) var currentPageIndex = 0
    private(set) var returnStack: [ReturnPoint] = []
    private(set) var outline: [OutlineNode] = []
    /// Each outline entry's page, by entry id; nil until resolved in the background.
    private(set) var outlinePageIndices: [OutlineNode.ID: Int]?
    private(set) var invertsPages = false
    #if os(iOS)
    /// Hidden by tapping the page. The Mac's toolbar and sidebar don't hide.
    var isChromeHidden = false
    /// Whether the reader's window is in the foreground and active. Decides
    /// whether to listen for knocks.
    private(set) var isSceneActive = true
    #endif
    #if os(macOS)
    /// The print sheet in progress, kept until it's done with the document copy.
    @ObservationIgnored private var printJob: PrintJob?
    #endif

    init(data: Data, fileURL: URL?) {
        self.data = data
        self.fileURL = fileURL
        // Password-protected and empty files aren't supported; they show as unopenable.
        let document = Signposts.signposter.withIntervalSignpost("Load Document") {
            NightDocument(data: data)
        }.flatMap { $0.isLocked || $0.pageCount == 0 ? nil : $0 }
        self.document = document
        search = document.map { DocumentSearch(document: $0, data: data) }
        guard let document else { return }
        search?.reveal = { [weak self] selection in
            self?.withoutHistory { self?.pdfView?.reveal(selection) }
        }
        pageCount = document.pageCount
        outline = Signposts.signposter.withIntervalSignpost("Build Outline") {
            Self.outlineNodes(of: document.outlineRoot)
        }
        if !outline.isEmpty {
            Task { [weak self, data] in
                let indices = await Self.outlinePageIndices(data: data)
                self?.outlinePageIndices = indices
            }
        }
        if let position = ReadingPositions.position(for: positionKey) {
            currentPageIndex = min(max(position.pageIndex, 0), pageCount - 1)
            restorePoint = position.pageIndex == currentPageIndex ? position.point : nil
        }
    }

    func attach(_ view: NightPDFView) {
        pdfView = view
        search?.pdfView = view
        // A new view starts from PDFKit's defaults, whatever was applied to an earlier one.
        appliedLayout = nil
        view.pageShadowsEnabled = !invertsPages
        let start = currentPageIndex
        let point = restorePoint
        restorePoint = nil
        guard start > 0 || point != nil else { return }
        isRestoring = true
        // Wait for the first layout pass, otherwise PDFView ignores the jump.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isRestoring = false
            guard let page = document?.page(at: start) else { return }
            let top = page.bounds(for: .cropBox)
            // Through `go(to:)`, which keeps the spot clear of the navigation bar.
            let destination = PDFDestination(page: page, at: point ?? CGPoint(x: top.minX, y: top.maxY))
            self.withoutHistory { view.go(to: destination) }
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
            #if os(iOS)
            view.usePageViewController(false)
            #endif
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.displaysAsBook = false
        case .paged:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.displaysAsBook = false
            #if os(iOS)
            view.usePageViewController(true)
            #endif
        case .twoUp:
            #if os(iOS)
            view.usePageViewController(false)
            #endif
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
        thumbnails.removeAllObjects()
        guard let view = pdfView else { return }
        view.pageShadowsEnabled = !inverts
        view.redrawPages()
    }

    // MARK: - Navigation

    func pageDidChange() {
        guard let view = pdfView, let page = view.currentPage, let document else { return }
        currentPageIndex = document.index(for: page)
        // Pages change many times a second in a fast scroll; save once it settles.
        positionSave?.cancel()
        positionSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            savePosition()
        }
    }

    func sceneActivityChanged(_ isActive: Bool) {
        #if os(iOS)
        isSceneActive = isActive
        #endif
        if !isActive { savePosition() }
    }

    /// Remembers the spot at the top of the screen, to reopen the file there.
    /// Also called when the window goes to the background or closes.
    func savePosition() {
        positionSave?.cancel()
        positionSave = nil
        guard let document, !isRestoring else { return }
        var position = ReadingPositions.Position(pageIndex: currentPageIndex, point: nil)
        if let destination = pdfView?.visibleDestination, let page = destination.page {
            position = .init(pageIndex: document.index(for: page), point: destination.point)
        }
        ReadingPositions.save(position, for: positionKey)
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
        #if os(iOS)
        isChromeHidden = false   // so the way back shows
        #endif
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

    #if os(iOS)
    /// Scrolls about a screenful, or turns the page. Not a jump, so it isn't
    /// added to the return history.
    func step(forward: Bool) {
        if pdfView == nil { DebugLog.scroll("step skipped: no PDF view") }
        withoutHistory { pdfView?.step(forward: forward) }
    }
    #endif

    private func withoutHistory(_ action: () -> Void) {
        suppressHistory = true
        action()
        suppressHistory = false
    }

    #if os(iOS)
    // MARK: - Knock to scroll

    /// Every window's reader listens while it's active; knocks go to the one
    /// in the key window.
    func listenForKnocks(_ listens: Bool) {
        DebugLog.knock("listen \(listens), enabled \(knocks.isEnabled)")
        if listens {
            knocks.addListener(self, isKey: { [weak self] in self?.pdfView?.window?.isKeyWindow == true }) {
                [weak self] knock in self?.step(forward: knock == .double)
            }
        } else {
            knocks.removeListener(self)
        }
    }
    #endif

    // MARK: - Printing

    func printDocument() {
        let jobName = fileURL?.deletingPathExtension().lastPathComponent ?? "Document"
        #if os(macOS)
        guard printJob == nil else { return }   // its sheet is already up
        // A fresh copy of the file, so dark mode's inverted pages don't print.
        guard let copy = PDFDocument(data: data),
              let operation = copy.printOperation(for: .shared, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return }
        operation.jobTitle = jobName
        if let window = pdfView?.window {
            // The sheet runs after this returns; the job keeps the copy alive until it's done.
            let job = PrintJob(document: copy) { [weak self] in self?.printJob = nil }
            printJob = job
            operation.runModal(for: window, delegate: job,
                               didRun: #selector(PrintJob.printOperationDidRun(_:success:contextInfo:)),
                               contextInfo: nil)
        } else {
            operation.run()
        }
        #else
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        controller.printInfo = info
        controller.printingItem = data
        controller.present(animated: true)
        #endif
    }

    // MARK: - Helpers

    /// Kept, so reopening the page grid or scrolling back doesn't render again.
    /// `scale` is the display's pixels per point.
    func thumbnail(forPage index: Int, fitting size: CGSize, scale: CGFloat) async -> PlatformImage? {
        let key = "\(index) \(Int(size.width))x\(Int(size.height))@\(scale)" as NSString
        if let image = thumbnails.object(forKey: key) { return image }
        guard let page = document?.page(at: index) as? NightPage else { return nil }
        let inverts = invertsPages
        guard let image = await Self.renderThumbnail(of: page, fitting: size, scale: scale) else { return nil }
        // Don't keep one drawn in the old colors.
        if inverts == invertsPages {
            thumbnails.setObject(image, forKey: key, cost: image.pixelCount)
        }
        return image
    }

    /// Off the main thread, so scrolling the page grid doesn't stall on rendering.
    @concurrent
    private nonisolated static func renderThumbnail(of page: NightPage, fitting size: CGSize,
                                                    scale: CGFloat) async -> PlatformImage? {
        guard !Task.isCancelled else { return nil }   // scrolled away before its turn
        return page.thumbnail(fitting: size, scale: scale)
    }

    func pageIndex(of node: OutlineNode) -> Int? {
        outlinePageIndices?[node.id]
    }

    /// The section the reader is in: the last entry, in reading order, that
    /// starts at or before the current page, with the entries above it.
    /// Empty until the outline's pages are resolved.
    func currentOutlinePath() -> [OutlineNode] {
        var path: [OutlineNode] = []
        var found: [OutlineNode] = []
        func visit(_ nodes: [OutlineNode]) -> Bool {
            for node in nodes {
                if let index = pageIndex(of: node) {
                    if index > currentPageIndex { return false }
                    found = path + [node]
                }
                path.append(node)
                defer { path.removeLast() }
                if !visit(node.children ?? []) { return false }
            }
            return true
        }
        _ = visit(outline)
        return found
    }

    private var positionKey: String {
        fileURL?.path(percentEncoded: false) ?? "untitled"
    }

    /// Resolving a destination's page is slow (~0.1 ms each, so seconds for a
    /// textbook's outline), so it's left to `outlinePageIndices(data:)`.
    /// `visit` sees each entry's id and destination as it's built.
    private nonisolated static func outlineNodes(
        of item: PDFOutline?, visit: (OutlineNode.ID, PDFDestination?) -> Void = { _, _ in }
    ) -> [OutlineNode] {
        var nextID = 0
        func build(_ item: PDFOutline) -> [OutlineNode] {
            (0..<item.numberOfChildren).compactMap { item.child(at: $0) }.map { child in
                nextID += 1
                let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination
                visit(nextID, destination)
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

    /// Every outline entry's page, resolved off the main thread on a private
    /// copy of the document (PDFKit documents aren't safe to share across
    /// threads). Built by the same walk as `outline`, so the ids match.
    @concurrent
    private nonisolated static func outlinePageIndices(data: Data) async -> [OutlineNode.ID: Int] {
        Signposts.signposter.withIntervalSignpost("Resolve Outline Pages") {
            guard let copy = PDFDocument(data: data) else { return [:] }
            var indices: [OutlineNode.ID: Int] = [:]
            _ = outlineNodes(of: copy.outlineRoot) { id, destination in
                if let page = destination?.page {
                    indices[id] = copy.index(for: page)
                }
            }
            return indices
        }
    }
}

#if os(macOS)
/// Holds the document a print sheet prints from, and hears when the sheet is done.
private final class PrintJob: NSObject {
    let document: PDFDocument
    private let finished: () -> Void

    init(document: PDFDocument, finished: @escaping () -> Void) {
        self.document = document
        self.finished = finished
    }

    @objc func printOperationDidRun(_ operation: NSPrintOperation, success: Bool,
                                    contextInfo: UnsafeMutableRawPointer?) {
        finished()
    }
}
#endif

/// Where each file was left, all under one key with the least recently read
/// dropped, so opening many files doesn't grow the defaults without end.
enum ReadingPositions {
    struct Position {
        let pageIndex: Int
        /// In page space; nil when only the page is known.
        let point: CGPoint?
    }

    private static let key = "readingPositions"
    static let limit = 200
    /// Replaced by the unit tests.
    static var defaults = UserDefaults.standard

    static func position(for path: String) -> Position? {
        if let entry = defaults.dictionary(forKey: key)?[path] as? [String: Double], let page = entry["page"] {
            let point = entry["x"].flatMap { x in entry["y"].map { CGPoint(x: x, y: $0) } }
            return Position(pageIndex: Int(page), point: point)
        }
        // Before, each file had a key of its own.
        let legacyKey = "lastPage:\(path)"
        guard defaults.object(forKey: legacyKey) != nil else { return nil }
        let position = Position(pageIndex: defaults.integer(forKey: legacyKey), point: nil)
        defaults.removeObject(forKey: legacyKey)
        save(position, for: path)
        return position
    }

    static func save(_ position: Position, for path: String) {
        var positions = defaults.dictionary(forKey: key) as? [String: [String: Double]] ?? [:]
        var entry = ["page": Double(position.pageIndex), "time": Date.now.timeIntervalSinceReferenceDate]
        if let point = position.point {
            entry["x"] = point.x
            entry["y"] = point.y
        }
        positions[path] = entry
        if positions.count > limit,
           let oldest = positions.min(by: { $0.value["time"] ?? 0 < $1.value["time"] ?? 0 })?.key {
            positions[oldest] = nil
        }
        defaults.set(positions, forKey: key)
    }
}
