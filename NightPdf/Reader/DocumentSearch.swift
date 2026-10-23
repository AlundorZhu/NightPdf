//
//  DocumentSearch.swift
//  NightPdf
//

import os
import PDFKit
import SwiftUI

struct SearchResult: Identifiable, Sendable {
    let id: Int
    let pageIndex: Int
    /// Character range in the page's text.
    let range: NSRange
    /// Match bounds in page space, one per line it spans.
    let lineRects: [CGRect]
    /// For the results list; made by the search, which has the page's text at hand.
    let snippet: SearchSnippet
}

/// A match with some text on either side, whitespace collapsed.
nonisolated struct SearchSnippet: Equatable, Sendable {
    let head: String
    let match: String
    let tail: String

    /// Cut around the match's own range, so the right occurrence is the bold one.
    init(range: NSRange, in text: NSString) {
        let before = 40, after = 60
        guard NSMaxRange(range) <= text.length else {
            head = ""; match = ""; tail = ""
            return
        }
        let start = max(range.location - before, 0)
        let end = min(NSMaxRange(range) + after, text.length)
        func part(_ location: Int, _ length: Int) -> String {
            text.substring(with: NSRange(location: location, length: length))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        var head = part(start, range.location - start)
        var tail = part(NSMaxRange(range), end - NSMaxRange(range))

        // Cutting by characters splits words; drop the partial ones, unless
        // the text was already cut short by the start or end of the page.
        if start == 0 {
            while head.hasPrefix(" ") { head.removeFirst() }
        } else if let space = head.firstIndex(of: " ") {
            head = "…" + head[head.index(after: space)...]
        } else {
            head = "…" + head
        }
        if end == text.length {
            while tail.hasSuffix(" ") { tail.removeLast() }
        } else if let space = tail.lastIndex(of: " ") {
            tail = tail[..<space] + "…"
        }
        self.head = head
        self.match = part(range.location, range.length)
        self.tail = tail
    }
}

/// Find in document. Pages are searched off the main thread, in parallel on
/// private copies of the document; results arrive in page order, in batches.
/// (PDFKit's `beginFindString` searches on the main thread, one page per run
/// loop pass, which stalls the UI.)
@Observable
final class DocumentSearch {
    var isActive = false
    var query = ""
    /// The query the results belong to; `query` may have been edited since.
    private(set) var searchedQuery = ""
    private(set) var results: [SearchResult] = []
    private(set) var currentIndex: Int?
    private(set) var isFinding = false
    /// The search stopped at `maxResults`; there are more matches.
    private(set) var isCapped = false

    /// A one-letter query can match hundreds of thousands of times, and each
    /// match holds a selection and draws a highlight.
    nonisolated static let maxResults = 5_000

    @ObservationIgnored weak var pdfView: NightPDFView?
    /// Scrolls to a match; set by the reader so jumps skip the back history.
    @ObservationIgnored var reveal: ((PDFSelection) -> Void)?
    @ObservationIgnored private let document: PDFDocument
    @ObservationIgnored private let data: Data
    /// Parsing the copies takes a while for a large file, so it runs off the
    /// main thread; a second search before it's done waits for the same task.
    @ObservationIgnored private var copies: Task<SearchCopies, Never>?
    @ObservationIgnored private var startPage = 0
    @ObservationIgnored private var findTask: Task<Void, Never>?
    /// Batches already buffered by a cancelled search can still arrive; this
    /// tells them apart from the current search's.
    @ObservationIgnored private var generation = 0
    /// Lets go of the copies when the system runs low on memory. The same on
    /// both platforms; the Mac has no memory warning notification.
    @ObservationIgnored nonisolated(unsafe) private var memoryPressure: DispatchSourceMemoryPressure?

    init(document: PDFDocument, data: Data) {
        self.document = document
        self.data = data
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.copies = nil }
        }
        source.resume()
        memoryPressure = source
    }

    deinit {
        memoryPressure?.cancel()
    }

    func begin() {
        isActive = true
    }

    func end() {
        clearResults()
        isActive = false
        query = ""
        copies = nil   // the next search parses them again, off the main thread
    }

    /// Return in the search field: a new query searches, the same one moves on.
    func submit() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if text == searchedQuery && !results.isEmpty {
            next()
        } else {
            find(text)
        }
    }

    /// While typing (the Mac's toolbar field): searches once the text is long
    /// enough to narrow things down, and leaves a query that hasn't changed
    /// alone, where `submit()` would move on.
    func searchAsTyped() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text != searchedQuery else { return }
        find(text)
    }

    func next() {
        guard !results.isEmpty else { return }
        if let currentIndex {
            select((currentIndex + 1) % results.count)
        } else {
            // Like the first match selected: from where the reader is.
            select(results.firstIndex { $0.pageIndex >= startPage } ?? 0)
        }
    }

    func previous() {
        guard !results.isEmpty else { return }
        select(((currentIndex ?? 0) - 1 + results.count) % results.count)
    }

    func select(_ index: Int) {
        currentIndex = index
        let result = results[index]
        pdfView?.overlays.setCurrent(result.lineRects, onPage: result.pageIndex)
        if let selection = selection(for: result) {
            reveal?(selection)
        }
    }

    /// The match with some text on either side, for the results list.
    func snippet(for result: SearchResult) -> AttributedString {
        var emphasized = AttributedString(result.snippet.match)
        emphasized.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(result.snippet.head) + emphasized + AttributedString(result.snippet.tail)
    }

    private func selection(for result: SearchResult) -> PDFSelection? {
        document.page(at: result.pageIndex)?.selection(for: result.range)
    }

    private func find(_ text: String) {
        clearResults()
        searchedQuery = text
        guard !text.isEmpty else { return }
        startPage = pdfView?.currentPage.map { document.index(for: $0) } ?? 0
        isFinding = true
        let generation = generation
        let interval = Signposts.signposter.beginInterval("Search")
        let copies = copies ?? Task.detached(priority: .userInitiated) { [data] in SearchCopies(data: data) }
        self.copies = copies
        findTask = Task {
            for await batch in Self.matches(of: text, in: await copies.value) {
                guard !Task.isCancelled, generation == self.generation else { break }
                add(batch.results)
                if batch.isCapped { isCapped = true }
            }
            guard !Task.isCancelled, generation == self.generation else {
                Signposts.signposter.endInterval("Search", interval, "cancelled")
                return
            }
            Signposts.signposter.endInterval("Search", interval, "\(self.results.count) matches")
            isFinding = false
            if currentIndex == nil && !results.isEmpty {
                select(0)
            }
            let found = results.isEmpty ? "No matches" : results.count == 1 ? "1 match" : "\(countText) matches"
            AccessibilityNotification.Announcement(found).post()
        }
    }

    /// The number of matches, with a "+" when the search stopped at the cap.
    var countText: String {
        "\(results.count.formatted())\(isCapped ? "+" : "")"
    }

    private func clearResults() {
        findTask?.cancel()
        findTask = nil
        generation += 1
        searchedQuery = ""
        results = []
        currentIndex = nil
        isFinding = false
        isCapped = false
        pdfView?.overlays.removeAll()
    }

    private func add(_ batch: [SearchResult]) {
        let first = results.count
        let numbered = batch.enumerated().map { offset, result in
            SearchResult(id: first + offset, pageIndex: result.pageIndex, range: result.range,
                         lineRects: result.lineRects, snippet: result.snippet)
        }
        results.append(contentsOf: numbered)
        pdfView?.overlays.add(numbered.map { ($0.pageIndex, $0.lineRects) })
        // Start from where the reader is, not from page 1.
        if currentIndex == nil, let here = numbered.first(where: { $0.pageIndex >= startPage }) {
            select(here.id)
        }
    }

    /// Searches the pages in parallel and yields matches in page order, about
    /// ten times a second, so the UI updates in steps rather than once per page.
    /// Stops once `limit` are in; the last batch says whether it did.
    nonisolated static func matches(
        of query: String, in copies: SearchCopies, limit: Int = maxResults
    ) -> AsyncStream<(results: [SearchResult], isCapped: Bool)> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let workers = copies.documents.count
                let pageCount = copies.documents.first?.pageCount ?? 0
                // Pages finish out of order; hold them until the ones before are in.
                let collected = OSAllocatedUnfairLock(initialState: (
                    next: 0, done: [Int: [SearchResult]](), batch: [SearchResult](), lastYield: ContinuousClock.now,
                    total: 0, isCapped: false))

                await withTaskGroup(of: Void.self) { group in
                    for worker in 0..<workers {
                        group.addTask {
                            let document = copies.documents[worker]
                            for pageIndex in stride(from: worker, to: pageCount, by: workers) {
                                if Task.isCancelled || collected.withLock({ $0.isCapped }) { return }
                                // One more than fits, to tell a full set from a cut-off one.
                                let found = matches(of: query, onPage: pageIndex, in: document, limit: limit + 1)
                                collected.withLock { state in
                                    state.done[pageIndex] = found
                                    while !state.isCapped, let ready = state.done.removeValue(forKey: state.next) {
                                        let room = limit - state.total
                                        state.batch += ready.prefix(room)
                                        state.total += min(ready.count, room)
                                        state.isCapped = ready.count > room
                                        state.next += 1
                                    }
                                    if !state.batch.isEmpty && ContinuousClock.now - state.lastYield > .milliseconds(100) {
                                        continuation.yield((state.batch, false))
                                        state.batch = []
                                        state.lastYield = .now
                                    }
                                }
                            }
                        }
                    }
                }
                let (rest, isCapped) = collected.withLock { ($0.batch, $0.isCapped) }
                if !rest.isEmpty || isCapped { continuation.yield((rest, isCapped)) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func matches(of query: String, onPage pageIndex: Int, in document: PDFDocument,
                                            limit: Int) -> [SearchResult] {
        guard let page = document.page(at: pageIndex), let text = page.string as NSString? else { return [] }
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var results: [SearchResult] = []
        var remaining = NSRange(location: 0, length: text.length)
        while results.count < limit {
            let found = text.range(of: query, options: options, range: remaining)
            if found.location == NSNotFound { break }
            let lines = page.selection(for: found)?.selectionsByLine() ?? []
            results.append(SearchResult(id: 0, pageIndex: pageIndex, range: found,
                                        lineRects: lines.map { $0.bounds(for: page) },
                                        snippet: SearchSnippet(range: found, in: text)))
            remaining = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        return results
    }
}

/// Private copies of the document for searching off the main thread, one per
/// worker: PDFKit documents aren't safe to share across threads. They're kept
/// while search is open, so later searches reuse the page text PDFKit extracted
/// for the first one, and let go when it closes or memory runs low.
nonisolated final class SearchCopies: @unchecked Sendable {
    let documents: [PDFDocument]

    init(data: Data) {
        // Leave cores free so page drawing doesn't wait on a search.
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        documents = (0..<workers).compactMap { _ in PDFDocument(data: data) }
    }
}
