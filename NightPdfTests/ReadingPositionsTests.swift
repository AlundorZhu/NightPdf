//
//  ReadingPositionsTests.swift
//  NightPdfTests
//

import Foundation
import Testing
@testable import NightPdf

/// Runs against a throwaway defaults suite, so the app's own positions are untouched.
@Suite(.serialized)
final class ReadingPositionsTests {
    private let suiteName = "ReadingPositionsTests"
    private let saved = ReadingPositions.defaults

    init() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        ReadingPositions.defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        ReadingPositions.defaults = saved
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func savesAndReads() throws {
        ReadingPositions.save(.init(pageIndex: 4, point: CGPoint(x: 12, y: 340)), for: "/a.pdf")
        ReadingPositions.save(.init(pageIndex: 7, point: nil), for: "/b.pdf")

        let a = try #require(ReadingPositions.position(for: "/a.pdf"))
        #expect(a.pageIndex == 4)
        #expect(a.point == CGPoint(x: 12, y: 340))
        let b = try #require(ReadingPositions.position(for: "/b.pdf"))
        #expect(b.pageIndex == 7)
        #expect(b.point == nil)
        #expect(ReadingPositions.position(for: "/never-opened.pdf") == nil)
    }

    @Test func dropsLeastRecentlyRead() {
        ReadingPositions.save(.init(pageIndex: 1, point: nil), for: "/oldest.pdf")
        Thread.sleep(forTimeInterval: 0.01)   // so it's strictly the oldest
        for index in 1...ReadingPositions.limit {
            ReadingPositions.save(.init(pageIndex: index, point: nil), for: "/\(index).pdf")
        }

        let stored = ReadingPositions.defaults.dictionary(forKey: "readingPositions")
        #expect(stored?.count == ReadingPositions.limit)
        #expect(ReadingPositions.position(for: "/oldest.pdf") == nil)
        #expect(ReadingPositions.position(for: "/1.pdf")?.pageIndex == 1)
        #expect(ReadingPositions.position(for: "/\(ReadingPositions.limit).pdf")?.pageIndex == ReadingPositions.limit)
    }

    @Test func migratesLegacyKey() throws {
        let defaults = ReadingPositions.defaults
        defaults.set(5, forKey: "lastPage:/old.pdf")

        let position = try #require(ReadingPositions.position(for: "/old.pdf"))
        #expect(position.pageIndex == 5)
        #expect(position.point == nil)
        #expect(defaults.object(forKey: "lastPage:/old.pdf") == nil, "the old key is removed")
        #expect(ReadingPositions.position(for: "/old.pdf")?.pageIndex == 5, "and the position kept under the new one")
    }
}
