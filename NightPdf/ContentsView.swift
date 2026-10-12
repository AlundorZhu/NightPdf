//
//  ContentsView.swift
//  NightPdf
//

import SwiftUI

struct ContentsView: View {
    let model: ReaderModel

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab?

    enum Tab: String, CaseIterable, Identifiable {
        case outline = "Contents"
        case pages = "Pages"
        case bookmarks = "Bookmarks"

        var id: Self { self }
    }

    private var selectedTab: Binding<Tab> {
        Binding(
            get: { tab ?? (model.outline.isEmpty ? .pages : .outline) },
            set: { tab = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // A NavigationStack here would inherit DocumentGroup's back button.
            HStack {
                Picker("View", selection: selectedTab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
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

            switch selectedTab.wrappedValue {
            case .outline: outline
            case .pages: PagesGrid(model: model, select: select)
            case .bookmarks: bookmarks
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var outline: some View {
        if model.outline.isEmpty {
            ContentUnavailableView(
                "No Contents",
                systemImage: "list.bullet",
                description: Text("This document doesn’t have a table of contents.")
            )
        } else {
            List(model.outline, children: \.children) { node in
                Button {
                    if let destination = node.destination {
                        model.go(to: destination)
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text(node.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if let page = node.pageIndex {
                            Text("\(page + 1)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(node.destination == nil)
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private var bookmarks: some View {
        if model.bookmarks.isEmpty {
            ContentUnavailableView(
                "No Bookmarks",
                systemImage: "bookmark",
                description: Text("Tap \(Image(systemName: "bookmark")) while reading to bookmark a page.")
            )
        } else {
            List {
                ForEach(model.bookmarks.sorted(), id: \.self) { index in
                    Button {
                        select(index)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Page \(index + 1)")
                                .foregroundStyle(.primary)
                            if let snippet = model.snippet(forPage: index) {
                                Text(snippet)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let sorted = model.bookmarks.sorted()
                    offsets.forEach { model.removeBookmark(sorted[$0]) }
                }
            }
            .listStyle(.plain)
        }
    }

    private func select(_ index: Int) {
        model.go(toPage: index)
        dismiss()
    }
}

private struct PagesGrid: View {
    let model: ReaderModel
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16)], spacing: 20) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        Button {
                            select(index)
                        } label: {
                            PageThumbnail(model: model, index: index, isCurrent: index == model.currentPageIndex)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding()
            }
            .onAppear {
                proxy.scrollTo(model.currentPageIndex, anchor: .center)
            }
        }
    }
}

private struct PageThumbnail: View {
    let model: ReaderModel
    let index: Int
    let isCurrent: Bool

    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Rectangle()
                        .fill(.fill.tertiary)
                        .aspectRatio(8.5 / 11, contentMode: .fit)
                }
            }
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.accentColor : Color.secondary.opacity(0.3),
                                  lineWidth: isCurrent ? 2.5 : 0.5)
            }

            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        }
        .task(id: model.invertsPages) {
            image = model.thumbnail(forPage: index, fitting: CGSize(width: 130, height: 170))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
