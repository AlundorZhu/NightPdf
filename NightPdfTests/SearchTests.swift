//
//  SearchTests.swift
//  NightPdfTests
//

import Foundation
import Testing
@testable import NightPdf

struct SearchSnippetTests {
    private func snippet(_ text: String, _ match: String, occurrence: Int = 0) -> SearchSnippet {
        let string = text as NSString
        var range = string.range(of: match)
        for _ in 0..<occurrence {
            let from = NSMaxRange(range)
            range = string.range(of: match, range: NSRange(location: from, length: string.length - from))
        }
        return SearchSnippet(range: range, in: string)
    }

    @Test func shortTextIsWhole() {
        let parts = snippet("Hello brave world  ", "brave")
        #expect(parts.head == "Hello ")
        #expect(parts.match == "brave")
        #expect(parts.tail == " world", "trailing space at the end of the page is dropped")
    }

    @Test func cutsAtWordsInLongText() {
        let text = (0..<60).map { "word\($0)" }.joined(separator: " ")
        let parts = snippet(text, "word30")
        #expect(parts.match == "word30")
        #expect(parts.head.hasPrefix("…word"), "the partial word at the start is dropped")
        #expect(parts.head.hasSuffix(" "))
        #expect(text.contains(parts.head.dropFirst()))
        #expect(parts.tail.hasPrefix(" word31"))
        #expect(parts.tail.hasSuffix(" …") == false && parts.tail.hasSuffix("…"))
        #expect(text.contains(parts.tail.dropLast()), "the partial word at the end is dropped")
    }

    @Test func collapsesWhitespace() {
        let parts = snippet("one\n\n  two\tthree", "two")
        #expect(parts.head == "one ")
        #expect(parts.tail == " three")
    }

    @Test func boldsTheMatchedOccurrence() {
        let parts = snippet("cat dog cat", "cat", occurrence: 1)
        #expect(parts.head == "cat dog ")
        #expect(parts.match == "cat")
        #expect(parts.tail == "")
    }

    @Test func rangePastTheTextIsEmpty() {
        let parts = SearchSnippet(range: NSRange(location: 5, length: 10), in: "short")
        #expect(parts == SearchSnippet(range: NSRange(location: 0, length: 0), in: ""))
        #expect(parts.match.isEmpty)
    }
}

struct SearchCapTests {
    private static let sample = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "TestAssets/sample.pdf")

    private func search(_ query: String, limit: Int) async throws -> (results: [SearchResult], isCapped: Bool) {
        let copies = SearchCopies(data: try Data(contentsOf: Self.sample))
        var results: [SearchResult] = []
        var isCapped = false
        for await batch in DocumentSearch.matches(of: query, in: copies, limit: limit) {
            results += batch.results
            isCapped = isCapped || batch.isCapped
        }
        return (results, isCapped)
    }

    @Test func stopsAtTheLimitInPageOrder() async throws {
        let all = try await search("e", limit: DocumentSearch.maxResults)
        #expect(!all.isCapped)
        try #require(all.results.count > 100, "the sample has plenty of e's")
        #expect(Set(all.results.map(\.pageIndex)).count > 1)

        let capped = try await search("e", limit: 100)
        #expect(capped.isCapped)
        #expect(capped.results.count == 100)
        let key = { (result: SearchResult) in [result.pageIndex, result.range.location] }
        #expect(capped.results.map(key) == all.results.prefix(100).map(key), "the first matches, in page order")
        #expect(all.results.map(key) == all.results.map(key).sorted { $0.lexicographicallyPrecedes($1) })
    }

    @Test func exactlyTheLimitIsNotCapped() async throws {
        let all = try await search("e", limit: DocumentSearch.maxResults)
        let exact = try await search("e", limit: all.results.count)
        #expect(exact.results.count == all.results.count)
        #expect(!exact.isCapped)
    }

    @Test func snippetsComeWithResults() async throws {
        let found = try await search("conclusion", limit: 10)
        let first = try #require(found.results.first)
        #expect(first.snippet.match.lowercased() == "conclusion")
    }
}
