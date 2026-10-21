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
                if let search = model.search {
                    DocumentReader(model: model, search: search)
                } else {
                    ContentUnavailableView(
                        "Can’t Open PDF",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The file may be damaged, password protected, or not a valid PDF.")
                    )
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
    @Bindable var search: DocumentSearch

    @AppStorage("pageAppearance") private var appearance = PageAppearance.automatic
    @AppStorage("pageLayout") private var layout = PageLayout.continuous
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showingContents = false
    @State private var showingGoToPage = false
    @State private var pageText = ""
    @State private var showingResults = false
    @State private var showingKnockSettings = false
    @FocusState private var searchFieldFocused: Bool

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

            if search.isActive {
                searchBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !model.isChromeHidden {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showingContents) {
            ContentsView(model: model)
        }
        .sheet(isPresented: $showingResults) {
            SearchResultsView(search: search)
        }
        .sheet(isPresented: $showingKnockSettings) {
            KnockSettingsView(knocks: model.knocks, isRegularWidth: sizeClass == .regular)
        }
        // The settings listen too, so the meter works before knocking is turned on.
        .onChange(of: [model.knocks.isEnabled, showingKnockSettings], initial: true) {
            model.listenForKnocks(model.knocks.isEnabled || showingKnockSettings)
        }
        .onDisappear { model.listenForKnocks(false) }
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
    /// Plain buttons only hit-test their drawn content, so each label sets a
    /// content shape; otherwise taps beside the glyph fall through to the page.
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Signposts.begin("Show Contents")
                    showingContents = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 48, height: 48)
                        .contentShape(.circle)
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
                        .contentShape(.capsule)
                }
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("Page \(model.currentPageIndex + 1) of \(model.pageCount)")
                .accessibilityHint("Go to a page")

                Spacer(minLength: 0)

                Button {
                    withAnimation(.snappy) { search.begin() }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 48, height: 48)
                        .contentShape(.circle)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Search")
                .keyboardShortcut("f")
            }
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .imageScale(.large)
        .foregroundStyle(.primary)
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    /// Replaces the bottom bar while searching. Return searches and puts the
    /// keyboard away so the matches can be read; tap the field to refine.
    private var searchBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    searchFieldFocused = false
                    withAnimation(.snappy) { search.end() }
                } label: {
                    Image(systemName: "checkmark")
                        .frame(width: 48, height: 48)
                        .contentShape(.circle)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Done")
                .keyboardShortcut(.cancelAction)

                searchField

                HStack(spacing: 0) {
                    Button(action: search.previous) {
                        Image(systemName: "chevron.up")
                            .frame(width: 40, height: 48)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Previous Match")
                    .keyboardShortcut("g", modifiers: [.command, .shift])

                    Button(action: search.next) {
                        Image(systemName: "chevron.down")
                            .frame(width: 40, height: 48)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Next Match")
                    .keyboardShortcut("g")
                }
                .padding(.horizontal, 2)
                .glassEffect(.regular.interactive(), in: .capsule)
                .disabled(search.results.isEmpty)

                Button {
                    searchFieldFocused = false
                    showingResults = true
                } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 48, height: 48)
                        .contentShape(.circle)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("All Results")
                .disabled(search.results.isEmpty)
            }
        }
        .buttonStyle(.plain)
        .font(.body.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            TextField("Search", text: $search.query)
                .focused($searchFieldFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit {
                    search.submit()
                    searchFieldFocused = false
                }
                .onAppear { searchFieldFocused = true }
            if !searchFieldFocused {
                searchStatus
            } else if !search.query.isEmpty {
                Button {
                    search.query = ""
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.body)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    @ViewBuilder
    private var searchStatus: some View {
        let isCurrent = search.query.trimmingCharacters(in: .whitespacesAndNewlines) == search.searchedQuery
        if isCurrent && search.isFinding && search.results.isEmpty {
            ProgressView()
        } else if isCurrent && !search.searchedQuery.isEmpty {
            Group {
                if let index = search.currentIndex {
                    Text("\(index + 1) of \(search.results.count)\(search.isFinding ? "+" : "")")
                } else if !search.isFinding {
                    Text("None")
                }
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
        }
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

                Button {
                    showingKnockSettings = true
                } label: {
                    Label("Knock to Scroll…", systemImage: "hand.tap")
                    Text(model.knocks.isEnabled ? "On" : "Off")
                }
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
