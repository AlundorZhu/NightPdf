//
//  PDFFile.swift
//  NightPdf
//

import SwiftUI
import UniformTypeIdentifiers

/// Read-only document wrapper used by the document browser.
nonisolated struct PDFFile: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    let data: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
