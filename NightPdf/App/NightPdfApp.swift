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
        // Set by the UI tests, which also run against Release builds.
        if CommandLine.arguments.contains("-resetState"), let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
    }

    var body: some Scene {
        DocumentGroup(viewing: PDFFile.self) { file in
            ReaderView(data: file.document.data, fileURL: file.fileURL)
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            ReaderCommands()
            #if os(macOS)
            SidebarCommands()   // View > Show Sidebar, ⌃⌘S
            #endif
        }
    }
}
