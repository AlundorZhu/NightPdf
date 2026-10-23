//
//  Signposts.swift
//  NightPdf
//

import os

/// Intervals for Instruments and the performance tests (NightPdfUITests/PerformanceTests).
///
/// - "Open Document": from reading the file until the first page is drawn.
///   Within it, "Load Document" (parsing) and "Build Outline".
/// - "Resolve Outline Pages": finding each outline entry's page, in the background.
/// - "Show Contents": from tapping Contents until the sheet appears.
/// - "Render Thumbnail": one page in the Pages grid.
/// - "Search": from submitting a search until PDFKit has searched every page.
///
/// `begin`/`end` are for intervals that start and finish in different places;
/// the rest use `signposter.withIntervalSignpost` directly.
nonisolated enum Signposts {
    static let signposter = OSSignposter(subsystem: "ucdavis.NightPdf", category: "Performance")

    private static let open = OSAllocatedUnfairLock<[String: OSSignpostIntervalState]>(initialState: [:])

    static func begin(_ name: StaticString) {
        let state = signposter.beginInterval(name)
        open.withLock { $0[name.description] = state }
    }

    /// Ends the interval if one is running; later calls do nothing.
    static func end(_ name: StaticString) {
        guard let state = open.withLock({ $0.removeValue(forKey: name.description) }) else { return }
        signposter.endInterval(name, state)
    }
}
