//
//  FileWatcher.swift
//  NightPdf
//

import Foundation

/// Reports when a file is rewritten by another app or tool, e.g. a LaTeX
/// build. (DocumentGroup only passes on changes it's told about.)
///
/// Watches the file itself for writes, and its directory for the file being
/// replaced, since most tools save by writing a new file and renaming it over
/// the old one. Changes are reported once the file has been quiet for a
/// moment, so a build in progress doesn't open a half-written file.
enum FileWatcher {
    static let settleDelay: Duration = .milliseconds(300)

    /// Reports a change each time the file's modification date or size differs
    /// from the last report. Ends when the task reading it is cancelled.
    static func changes(at url: URL) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let watcher = Watcher(url: url) { continuation.yield() }
            continuation.onTermination = { _ in watcher.stop() }
            watcher.start()
        }
    }

    private static func stamp(of url: URL) -> (Date, Int)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
              let date = attributes[.modificationDate] as? Date, let size = attributes[.size] as? Int
        else { return nil }
        return (date, size)
    }

    /// Unchecked Sendable: used from the watch queue only, apart from `stop`,
    /// which just cancels the sources.
    private final class Watcher: @unchecked Sendable {
        private let url: URL
        private let changed: @Sendable () -> Void
        private let queue = DispatchQueue(label: "NightPdf.FileWatcher")
        private var fileSource: DispatchSourceFileSystemObject?
        private var directorySource: DispatchSourceFileSystemObject?
        private var settle: DispatchWorkItem?
        private var lastStamp: (Date, Int)?

        init(url: URL, changed: @escaping @Sendable () -> Void) {
            self.url = url
            self.changed = changed
        }

        func start() {
            queue.async {
                self.lastStamp = stamp(of: self.url)
                self.directorySource = self.makeSource(for: self.url.deletingLastPathComponent(), events: .write)
                self.watchFile()
            }
        }

        func stop() {
            queue.async {
                self.settle?.cancel()
                self.fileSource?.cancel()
                self.directorySource?.cancel()
                self.fileSource = nil
                self.directorySource = nil
            }
        }

        /// A new file source each time the file is replaced: the old one
        /// follows the old inode.
        private func watchFile() {
            fileSource?.cancel()
            fileSource = makeSource(for: url, events: [.write, .extend, .attrib, .delete, .rename, .revoke])
        }

        private func makeSource(for url: URL, events: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
            let descriptor = open(url.path(percentEncoded: false), O_EVTONLY)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: queue)
            source.setEventHandler { [weak self] in self?.noteEvent(source.data) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }

        private func noteEvent(_ events: DispatchSource.FileSystemEvent) {
            settle?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.checkForChange() }
            settle = work
            queue.asyncAfter(deadline: .now() + .milliseconds(Int(settleDelay / .milliseconds(1))), execute: work)
        }

        private func checkForChange() {
            // Reopen in case the file was replaced; harmless if it wasn't.
            watchFile()
            guard let stamp = stamp(of: url) else { return }   // gone for the moment; wait for it to come back
            if let lastStamp, lastStamp == stamp { return }
            lastStamp = stamp
            changed()
        }
    }
}
