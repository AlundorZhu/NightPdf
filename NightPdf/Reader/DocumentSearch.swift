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

    @ObservationIgnored weak var pdfView: NightPDFView?
    /// Scrolls to a match; set by the reader so jumps skip the back history.
    @ObservationIgnored var reveal: ((PDFSelection) -> Void)?
    @ObservationIgnored private let document: PDFDocument
    @ObservationIgnored private let data: Data
    @ObservationIgnored private var copies: SearchCopies?
    @ObservationIgnored private var startPage = 0
    @ObservationIgnored private var findTask: Task<Void, Never>?

    init(document: PDFDocument, data: Data) {
        self.document = document
        self.data = data
    }

    func begin() {
        isActive = true
    }

    func end() {
        clearResults()
        isActive = false
        query = ""
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

    func next() {
        guard !results.isEmpty else { return }
        select((currentIndex.map { $0 + 1 } ?? 0) % results.count)
    }

    func previous() {
        guard !results.isEmpty else { return }
        select(((currentIndex ?? 0) - 1 + results.count) % results.count)
    }

    func select(_ index: Int) {
        currentIndex = index
        let result = results[index]
        pdfView?.highlighter.setCurrent(result.lineRects, onPage: result.pageIndex)
        if let selection = selection(for: result) {
            reveal?(selection)
        }
    }

    /// The match with some text on either side, for the results list.
    func snippet(for result: SearchResult) -> AttributedString {
        let before = 40, after = 60
        guard let context = selection(for: result) else { return AttributedString() }
        context.extend(atStart: before)
        context.extend(atEnd: after)
        var text = (context.string ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        // Extending by characters cuts words in half; drop the partial ones,
        // unless the text was already cut short by the start or end of the page.
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if let match = text.range(of: searchedQuery, options: options),
           text.distance(from: match.upperBound, to: text.endIndex) >= after - 5,
           let space = text[match.upperBound...].lastIndex(of: " ") {
            text = text[..<space] + "…"
        }
        if let match = text.range(of: searchedQuery, options: options),
           text.distance(from: text.startIndex, to: match.lowerBound) >= before - 5,
           let space = text[..<match.lowerBound].firstIndex(of: " ") {
            text = "…" + text[text.index(after: space)...]
        }

        var snippet = AttributedString(text)
        if let range = snippet.range(of: searchedQuery, options: options) {
            snippet[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return snippet
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
        let interval = Signposts.signposter.beginInterval("Search")
        let copies = copies ?? SearchCopies(data: data)
        self.copies = copies
        findTask = Task {
            for await batch in Self.matches(of: text, in: copies) {
                add(batch)
            }
            guard !Task.isCancelled else {
                Signposts.signposter.endInterval("Search", interval, "cancelled")
                return
            }
            Signposts.signposter.endInterval("Search", interval, "\(self.results.count) matches")
            isFinding = false
            if currentIndex == nil && !results.isEmpty {
                select(0)
            }
        }
    }

    private func clearResults() {
        findTask?.cancel()
        findTask = nil
        searchedQuery = ""
        results = []
        currentIndex = nil
        isFinding = false
        pdfView?.highlighter.removeAll()
    }

    private func add(_ batch: [SearchResult]) {
        let first = results.count
        let numbered = batch.enumerated().map { offset, result in
            SearchResult(id: first + offset, pageIndex: result.pageIndex, range: result.range, lineRects: result.lineRects)
        }
        results.append(contentsOf: numbered)
        pdfView?.highlighter.add(numbered.map { ($0.pageIndex, $0.lineRects) })
        // Start from where the reader is, not from page 1.
        if currentIndex == nil, let here = numbered.first(where: { $0.pageIndex >= startPage }) {
            select(here.id)
        }
    }

    /// Searches the pages in parallel and yields matches in page order, about
    /// ten times a second, so the UI updates in steps rather than once per page.
    private nonisolated static func matches(of query: String, in copies: SearchCopies) -> AsyncStream<[SearchResult]> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let workers = copies.documents.count
                let pageCount = copies.documents.first?.pageCount ?? 0
                // Pages finish out of order; hold them until the ones before are in.
                let collected = OSAllocatedUnfairLock(initialState: (
                    next: 0, done: [Int: [SearchResult]](), batch: [SearchResult](), lastYield: ContinuousClock.now))

                await withTaskGroup(of: Void.self) { group in
                    for worker in 0..<workers {
                        group.addTask {
                            let document = copies.documents[worker]
                            for pageIndex in stride(from: worker, to: pageCount, by: workers) {
                                if Task.isCancelled { return }
                                let found = matches(of: query, onPage: pageIndex, in: document)
                                collected.withLock { state in
                                    state.done[pageIndex] = found
                                    while let ready = state.done.removeValue(forKey: state.next) {
                                        state.batch += ready
                                        state.next += 1
                                    }
                                    if !state.batch.isEmpty && ContinuousClock.now - state.lastYield > .milliseconds(100) {
                                        continuation.yield(state.batch)
                                        state.batch = []
                                        state.lastYield = .now
                                    }
                                }
                            }
                        }
                    }
                }
                let rest = collected.withLock { $0.batch }
                if !rest.isEmpty { continuation.yield(rest) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private nonisolated static func matches(of query: String, onPage pageIndex: Int, in document: PDFDocument) -> [SearchResult] {
        guard let page = document.page(at: pageIndex), let text = page.string as NSString? else { return [] }
        let options: NSString.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var results: [SearchResult] = []
        var remaining = NSRange(location: 0, length: text.length)
        while true {
            let found = text.range(of: query, options: options, range: remaining)
            if found.location == NSNotFound { break }
            let lines = page.selection(for: found)?.selectionsByLine() ?? []
            results.append(SearchResult(id: 0, pageIndex: pageIndex, range: found,
                                        lineRects: lines.map { $0.bounds(for: page) }))
            remaining = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
        }
        return results
    }
}

/// Private copies of the document for searching off the main thread, one per
/// worker: PDFKit documents aren't safe to share across threads. They're kept,
/// so later searches reuse the page text PDFKit extracted for the first one.
private nonisolated final class SearchCopies: @unchecked Sendable {
    let documents: [PDFDocument]

    init(data: Data) {
        // Leave cores free so page drawing doesn't wait on a search.
        let workers = max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        documents = (0..<workers).compactMap { _ in PDFDocument(data: data) }
    }
}
