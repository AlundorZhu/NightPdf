//
//  ReaderView.swift
//  NightPdf
//

import SwiftUI

struct ReaderView: View {
    let data: Data
    let fileURL: URL?

    @State private var model: ReaderModel?

    var body: some View {
        Group {
            if let model {
                if model.document == nil {
                    ContentUnavailableView(
                        "Can’t Open PDF",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The file may be damaged, password protected, or not a valid PDF.")
                    )
                } else {
                    DocumentReader(model: model)
                }
            } else {
                Color.clear
            }
        }
        .onAppear {
            if model == nil {
                model = ReaderModel(data: data, fileURL: fileURL)
            }
        }
    }
}

private struct DocumentReader: View {
    let model: ReaderModel

    @AppStorage("pageAppearance") private var appearance = PageAppearance.automatic
    @AppStorage("pageLayout") private var layout = PageLayout.continuous
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingContents = false
    @State private var showingGoToPage = false
    @State private var pageText = ""

    private var invertsPages: Bool {
        switch appearance {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            PDFKitView(model: model, layout: layout, invertsPages: invertsPages, hidesBars: model.isChromeHidden)
                .ignoresSafeArea()

            if !model.isChromeHidden && !model.isSearching {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showingContents) {
            ContentsView(model: model)
        }
        .alert("Go to Page", isPresented: $showingGoToPage) {
            TextField("Page", text: $pageText)
                .keyboardType(.numberPad)
            Button("Go", action: goToEnteredPage)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a page number between 1 and \(model.pageCount).")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let point = model.returnStack.last {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation { model.returnToPrevious() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                        Text("\(point.pageIndex + 1)")
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("Back to page \(point.pageIndex + 1)")
                .contextMenu {
                    Button("Clear History", systemImage: "xmark", role: .destructive) {
                        withAnimation { model.clearReturnStack() }
                    }
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
    }

    /// Floating glass controls. DocumentGroup's viewer doesn't show `.bottomBar` items.
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    showingContents = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Contents")

                Spacer(minLength: 0)

                Button {
                    pageText = ""
                    showingGoToPage = true
                } label: {
                    Text("\(model.currentPageIndex + 1) of \(model.pageCount)")
                        .monospacedDigit()
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Page \(model.currentPageIndex + 1) of \(model.pageCount)")
                .accessibilityHint("Go to a page")

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    Button {
                        model.toggleBookmark()
                    } label: {
                        Image(systemName: model.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel(model.isCurrentPageBookmarked ? "Remove Bookmark" : "Add Bookmark")

                    Button {
                        model.showFind()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 48, height: 48)
                    }
                    .accessibilityLabel("Search")
                }
                .padding(.horizontal, 2)
                .glassEffect(.regular.interactive(), in: .capsule)
            }
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .imageScale(.large)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis") {
            Button("Go to Page…", systemImage: "arrow.right.page.on.clipboard") {
                pageText = ""
                showingGoToPage = true
            }

            Section {
                Picker(selection: $layout) {
                    ForEach(PageLayout.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                } label: {
                    Label("Layout", systemImage: layout.systemImage)
                }
                .pickerStyle(.menu)

                Picker(selection: $appearance) {
                    ForEach(PageAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                } label: {
                    Label("Page Color", systemImage: "circle.lefthalf.filled")
                }
                .pickerStyle(.menu)
            }

            Section {
                if let url = model.fileURL {
                    ShareLink(item: url)
                }
                Button("Print", systemImage: "printer") {
                    model.printDocument()
                }
            }
        }
    }

    private func goToEnteredPage() {
        guard let number = Int(pageText.trimmingCharacters(in: .whitespaces)) else { return }
        model.go(toPage: min(max(number, 1), model.pageCount) - 1)
    }
}
