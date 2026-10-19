//
//  ReaderSettings.swift
//  NightPdf
//

import Foundation

enum PageAppearance: String, CaseIterable, Identifiable {
    case automatic, light, dark

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "Match System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum PageLayout: String, CaseIterable, Identifiable {
    case continuous, paged, twoUp

    var id: Self { self }

    var title: String {
        switch self {
        case .continuous: "Vertical Scrolling"
        case .paged: "Page by Page"
        case .twoUp: "Two Pages"
        }
    }

    var systemImage: String {
        switch self {
        case .continuous: "arrow.up.and.down.text.horizontal"
        case .paged: "book.pages"
        case .twoUp: "book"
        }
    }
}
