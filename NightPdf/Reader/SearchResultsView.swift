//
//  SearchResultsView.swift
//  NightPdf
//

import SwiftUI

/// Every match for the current search, grouped by page.
struct SearchResultsView: View {
    let search: DocumentSearch

    @Environment(\.dismiss) private var dismiss

    private var pages: [(pageIndex: Int, results: [SearchResult])] {
        var pages: [(pageIndex: Int, results: [SearchResult])] = []
        for result in search.results {   // already in page order
            if pages.last?.pageIndex == result.pageIndex {
                pages[pages.count - 1].results.append(result)
            } else {
                pages.append((result.pageIndex, [result]))
            }
        }
        return pages
    }

    var body: some View {
        VStack(spacing: 0) {
            // A NavigationStack here would inherit DocumentGroup's back button.
            HStack {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button("Done", systemImage: "xmark", role: .close) { dismiss() }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .labelStyle(.iconOnly)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                List {
                    ForEach(pages, id: \.pageIndex) { page in
                        Section("Page \(page.pageIndex + 1)") {
                            ForEach(page.results) { result in
                                Button {
                                    search.select(result.id)
                                    dismiss()
                                } label: {
                                    Text(search.snippet(for: result))
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                }
                                .listRowBackground(result.id == search.currentIndex ? Color.accentColor.opacity(0.15) : nil)
                                .id(result.id)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .onAppear {
                    if let current = search.currentIndex {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
    }

    private var title: String {
        let count = search.results.count
        let matches = count == 1 ? "1 match" : "\(count) matches"
        return search.isFinding ? "\(matches) so far" : matches
    }
}
