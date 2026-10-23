//
//  ContentsView.swift
//  NightPdf
//

import PDFKit
import SwiftUI

/// The outline or the page grid: a sheet on iPhone and iPad, the sidebar on the Mac.
enum ContentsTab: String, CaseIterable, Identifiable {
    case outline = "Contents"
    case pages = "Pages"

    var id: Self { self }

    /// The outline when there is one.
    static func initial(for model: ReaderModel) -> Self {
        model.outline.isEmpty ? .pages : .outline
    }
}

#if os(iOS)
struct ContentsView: View {
    let model: ReaderModel

    @Environment(\.dismiss) private var dismiss
    @State private var tab: ContentsTab?

    private var selectedTab: Binding<ContentsTab> {
        Binding(
            get: { tab ?? .initial(for: model) },
            set: { tab = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // A NavigationStack here would inherit DocumentGroup's back button.
            HStack {
                Picker("View", selection: selectedTab) {
                    ForEach(ContentsTab.allCases) { Text($0.rawValue).tag($0) }
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
            case .outline:
                OutlineList(model: model) { destination in
                    model.go(to: destination)
                    dismiss()
                }
            case .pages:
                PagesGrid(model: model) { index in
                    model.go(toPage: index)
                    dismiss()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .onAppear { Signposts.end("Show Contents") }
    }
}
#endif

/// The document's outline, with the section the reader is in highlighted.
struct OutlineList: View {
    let model: ReaderModel
    let select: (PDFDestination) -> Void

    /// IDs of the current section and the entries above it.
    @State private var currentPath: [Int] = []
    @State private var hasScrolled = false
    #if os(macOS)
    /// The entry last chosen. It stays selected while the reader is on its
    /// page, even if another entry starts on the same page.
    @State private var chosen: OutlineNode.ID?
    #endif

    private struct UpdateID: Equatable {
        let isResolved: Bool
        let pageIndex: Int
    }

    var body: some View {
        if model.outline.isEmpty {
            ContentUnavailableView(
                "No Contents",
                systemImage: "list.bullet",
                description: Text("This document doesn’t have a table of contents.")
            )
        } else {
            ScrollViewReader { proxy in
                Group {
                    #if os(macOS)
                    List(model.outline, children: \.children, selection: selection) { node in
                        row(for: node, isSelected: node.id == selection.wrappedValue)
                            .selectionDisabled(node.destination == nil)
                            .id(node.id)
                    }
                    .listStyle(.sidebar)
                    #else
                    List(model.outline, children: \.children) { node in
                        let isCurrent = node.id == currentPath.last
                        Button {
                            if let destination = node.destination {
                                select(destination)
                            }
                        } label: {
                            row(for: node, isSelected: false)
                        }
                        .disabled(node.destination == nil)
                        .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : nil)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                        .id(node.id)
                    }
                    .listStyle(.plain)
                    #endif
                }
                // Again once the outline's pages are resolved, if this opened before,
                // and as the reader moves on while it stays open (the Mac's sidebar).
                .task(id: UpdateID(isResolved: model.outlinePageIndices != nil, pageIndex: model.currentPageIndex)) {
                    #if os(macOS)
                    if let chosen, model.outlinePageIndices?[chosen] != model.currentPageIndex {
                        self.chosen = nil   // read on past it
                    }
                    #endif
                    let path = model.currentOutlinePath().map(\.id)
                    let topChanged = path.first != currentPath.first
                    currentPath = path
                    // The top-level entry, which shows even when its children are collapsed.
                    guard let top = path.first else { return }
                    if !hasScrolled {
                        proxy.scrollTo(top, anchor: .center)
                        hasScrolled = model.outlinePageIndices != nil
                    } else if topChanged {
                        withAnimation { proxy.scrollTo(top) }   // only as far as it takes to show it
                    }
                }
            }
        }
    }

    /// `isSelected` rows get the list's highlight, which the accent color
    /// wouldn't show up on.
    private func row(for node: OutlineNode, isSelected: Bool) -> some View {
        HStack {
            Text(node.title)
                .foregroundStyle(currentPath.contains(node.id) && !isSelected ? Color.accentColor : .primary)
            Spacer()
            if let page = model.pageIndex(of: node) {
                Text("\(page + 1)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    #if os(macOS)
    /// The current section; choosing another, by click or arrow keys, goes there.
    private var selection: Binding<OutlineNode.ID?> {
        Binding(
            get: { chosen ?? currentPath.last },
            set: { id in
                guard let id, let destination = Self.node(id, in: model.outline)?.destination else { return }
                chosen = id
                select(destination)
            }
        )
    }

    private static func node(_ id: OutlineNode.ID, in nodes: [OutlineNode]) -> OutlineNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = Self.node(id, in: node.children ?? []) { return found }
        }
        return nil
    }
    #endif
}

/// A thumbnail of every page, with the current one marked.
struct PagesGrid: View {
    let model: ReaderModel
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                #if os(macOS)
                // One column, like Preview's sidebar. The list's selection marks the
                // current page, and arrow keys move through the pages.
                List(0..<model.pageCount, id: \.self, selection: selection) { index in
                    PageThumbnail(model: model, index: index, isCurrent: false)
                        .frame(maxWidth: 130)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .id(index)
                }
                .listStyle(.sidebar)
                #else
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
                #endif
            }
            .onAppear {
                proxy.scrollTo(model.currentPageIndex, anchor: .center)
            }
            // Keeps up with the reader while the grid stays open (the Mac's sidebar).
            .onChange(of: model.currentPageIndex) { _, index in
                withAnimation { proxy.scrollTo(index) }   // only as far as it takes to show it
            }
        }
    }

    #if os(macOS)
    private var selection: Binding<Int?> {
        Binding(
            get: { model.currentPageIndex },
            set: { index in
                if let index { select(index) }
            }
        )
    }
    #endif
}

private struct PageThumbnail: View {
    let model: ReaderModel
    let index: Int
    let isCurrent: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var image: PlatformImage?
    @State private var width: CGFloat = 0

    private struct RenderID: Equatable {
        let size: CGSize?
        let scale: CGFloat
        let inverts: Bool
    }

    /// The cell's width, rounded up to one of a few sizes so cells a few
    /// points apart share cached thumbnails.
    private var renderSize: CGSize? {
        guard width > 0 else { return nil }
        let bucket: CGFloat = width <= 130 ? 130 : width <= 160 ? 160 : 240
        return CGSize(width: bucket, height: bucket * 170 / 130)
    }

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(platformImage: image)
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        // Drawn again for a screen with another scale, e.g. a window moved to a non-Retina display.
        .task(id: RenderID(size: renderSize, scale: displayScale, inverts: model.invertsPages)) {
            guard let renderSize else { return }
            image = await model.thumbnail(forPage: index, fitting: renderSize, scale: displayScale)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
