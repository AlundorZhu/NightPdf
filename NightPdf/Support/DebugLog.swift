//
//  DebugLog.swift
//  NightPdf
//

import Foundation
import os

/// Logging for debugging on a device, in Debug builds only. Messages show in
/// Xcode's console, or in Console.app filtered to subsystem `ucdavis.NightPdf`.
///
/// In Release the functions are empty, and because messages are autoclosures
/// they're never built, so neither the logging nor its text ends up in the app.
nonisolated enum DebugLog {
    #if DEBUG
    private static let knockLogger = Logger(subsystem: "ucdavis.NightPdf", category: "Knock")
    private static let scrollLogger = Logger(subsystem: "ucdavis.NightPdf", category: "Scroll")

    static func knock(_ message: @autoclosure () -> String) {
        let text = message()
        knockLogger.notice("\(text, privacy: .public)")
    }

    static func scroll(_ message: @autoclosure () -> String) {
        let text = message()
        scrollLogger.notice("\(text, privacy: .public)")
    }
    #else
    @inline(__always) static func knock(_ message: @autoclosure () -> String) {}
    @inline(__always) static func scroll(_ message: @autoclosure () -> String) {}
    #endif

    static func g(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(3)))) g"
    }

    static func ms(_ seconds: Double) -> String {
        seconds > 10 ? "—" : "\(Int((seconds * 1000).rounded())) ms"
    }
}
