//
//  NightPdfApp.swift
//  NightPdf
//
//  Created by ZIQIANG ZHU on 10/11/26.
//

import SwiftUI

@main
struct NightPdfApp: App {
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("-resetState"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        #endif
    }

    var body: some Scene {
        DocumentGroup(viewing: PDFFile.self) { file in
            ReaderView(data: file.document.data, fileURL: file.fileURL)
        }
    }
}
