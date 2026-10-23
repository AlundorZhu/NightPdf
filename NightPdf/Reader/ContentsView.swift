//
//  ContentsView.swift
//  NightPdf
//

import SwiftUI

struct ContentsView: View {
    let model: ReaderModel

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab?
    /// IDs of the current section and the entries above it.
    @State private var currentPath: [Int] = []

    enum Tab: String, CaseIterable, Identifiable {
        case outline = "Contents"
        case pages = "Pages"

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
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .onAppear { Signposts.end("Show Contents") }
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
            ScrollViewReader { proxy in
                List(model.outline, children: \.children) { node in
                    let isCurrent = node.id == currentPath.last
                    Button {
                        if let destination = node.destination {
                            model.go(to: destination)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(node.title)
                                .foregroundStyle(currentPath.contains(node.id) ? Color.accentColor : .primary)
                            Spacer()
                            if let page = model.pageIndex(of: node) {
                                Text("\(page + 1)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(node.destination == nil)
                    .listRowBackground(isCurrent ? Color.accentColor.opacity(0.15) : nil)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    .id(node.id)
                }
                .listStyle(.plain)
                // Again once the outline's pages are resolved, if the sheet opened before.
                .task(id: model.outlinePageIndices == nil) {
                    currentPath = model.currentOutlinePath().map(\.id)
                    // The top-level entry, which shows even when its children are collapsed.
                    if let top = currentPath.first {
                        proxy.scrollTo(top, anchor: .center)
                    }
                }
            }
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
    @State private var width: CGFloat = 0

    private struct RenderID: Equatable {
        let size: CGSize?
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
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: RenderID(size: renderSize, inverts: model.invertsPages)) {
            guard let renderSize else { return }
            image = await model.thumbnail(forPage: index, fitting: renderSize)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}
