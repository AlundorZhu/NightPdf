//
//  ReaderView.swift
//  NightPdf
//

import PDFKit
import SwiftUI

struct ReaderView: View {
    let data: Data
    let fileURL: URL?

    @State private var model: ReaderModel?
    /// Identifies the contents `model` was built from.
    @State private var loadedContents: ContentsFingerprint?

    var body: some View {
        Group {
            if let model {
                if let search = model.search {
                    DocumentReader(model: model, search: search)
                        // A new document starts with fresh views and closed sheets.
                        .id(ObjectIdentifier(model))
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
        // DocumentGroup hands over new data when it hears of a change on disk
        // (iCloud, another app saving); reopen it at the same place.
        .onChange(of: ContentsFingerprint(data), initial: true) { _, _ in
            load(data)
        }
        // It doesn't hear of a file rewritten by a tool, like a LaTeX build,
        // so watch the file as well.
        .task(id: fileURL) {
            guard let fileURL else { return }
            for await _ in FileWatcher.changes(at: fileURL) {
                guard !Task.isCancelled, let data = Self.read(fileURL) else { continue }
                load(data)
            }
        }
    }

    /// Shows `data`, unless it's what's already showing. The new reader opens
    /// where the old one was, at the same zoom.
    private func load(_ data: Data) {
        let contents = ContentsFingerprint(data)
        guard contents != loadedContents else { return }
        var zoom: CGFloat?
        if let model {
            #if os(iOS)
            model.listenForKnocks(false)
            #endif
            model.savePosition()
            zoom = model.chosenZoom
        }
        loadedContents = contents
        model = ReaderModel(data: data, fileURL: fileURL, zoom: zoom)
    }

    /// The file's contents, if they're a PDF that opens. A build still writing
    /// the file isn't, and is left for the next change.
    private static func read(_ url: URL) -> Data? {
        var data: Data?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: nil) { url in
            data = try? Data(contentsOf: url)
        }
        guard let data, let document = PDFDocument(data: data), document.pageCount > 0 else { return nil }
        return data
    }
}

/// A cheap stand-in for comparing file contents, which can be large: the size
/// and the bytes at each end. A PDF that's rewritten or appended to changes
/// at the end.
private struct ContentsFingerprint: Equatable {
    let count: Int
    let head: Int
    let tail: Int

    init(_ data: Data) {
        let length = 8192
        count = data.count
        head = Self.hash(data.prefix(length))
        tail = Self.hash(data.suffix(length))
    }

    /// `Data`'s own hash only looks at its first few bytes.
    private static func hash(_ data: Data) -> Int {
        var hasher = Hasher()
        data.withUnsafeBytes { hasher.combine(bytes: $0) }
        return hasher.finalize()
    }
}

/// Back to where the last jump left from; a long press clears the history.
struct ReturnButton: View {
    let model: ReaderModel
    let point: ReturnPoint

    var body: some View {
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

#if os(iOS)
/// The reader on iPhone and iPad: the page full screen, with floating bars
/// that a tap hides. The Mac's is in ReaderView+macOS.swift.
struct DocumentReader: View {
    let model: ReaderModel
    @Bindable var search: DocumentSearch

    @AppStorage("pageAppearance") private var appearance = PageAppearance.automatic
    @AppStorage("pageLayout") private var layout = PageLayout.continuous
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var showingContents = false
    @State private var showingGoToPage = false
    @State private var showingResults = false
    @State private var showingKnockSettings = false
    @State private var showsPageIndicator = false
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            PDFKitView(model: model, layout: layout, invertsPages: appearance.invertsPages(in: colorScheme),
                       hidesBars: model.isChromeHidden,
                       bottomObscuredHeight: search.isActive || !model.isChromeHidden ? Self.barHeight : 0)
                .ignoresSafeArea()

            if search.isActive {
                searchBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if !model.isChromeHidden {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if showsPageIndicator {
                pageIndicator
                    .transition(.opacity)
            }
        }
        .toolbar { toolbar }
        .focusedSceneValue(\.readerActions, actions)
        // (`.statusBarHidden` has no effect under DocumentGroup's navigation controller.)
        .persistentSystemOverlays(model.isChromeHidden ? .hidden : .automatic)
        // With the bars hidden, show the page number for a moment as it changes.
        .task(id: model.currentPageIndex) {
            guard model.isChromeHidden else { return }
            withAnimation(.easeOut(duration: 0.2)) { showsPageIndicator = true }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.4)) { showsPageIndicator = false }
        }
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
        // In the background, or in a window that isn't showing, nothing listens.
        .onChange(of: [model.knocks.isEnabled, showingKnockSettings, model.isSceneActive], initial: true) {
            model.listenForKnocks(model.isSceneActive && (model.knocks.isEnabled || showingKnockSettings))
        }
        .onDisappear {
            model.listenForKnocks(false)
            model.savePosition()
        }
        .goToPageAlert(isPresented: $showingGoToPage, model: model)
    }

    /// For the menu bar, on iPad with a hardware keyboard.
    private var actions: ReaderActions {
        let canStep = search.isActive && !search.results.isEmpty
        return ReaderActions(
            find: { startSearch() },
            findNext: canStep ? { search.next() } : nil,
            findPrevious: canStep ? { search.previous() } : nil,
            goToPage: { showingGoToPage = true },
            print: { model.printDocument() }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let point = model.returnStack.last {
            ToolbarItem(placement: .topBarTrailing) {
                ReturnButton(model: model, point: point)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
    }

    private func endSearch() {
        guard search.isActive else { return }
        searchFieldFocused = false
        withAnimation(.snappy) { search.end() }
    }

    private func startSearch() {
        withAnimation(.snappy) {
            model.isChromeHidden = false
            search.begin()
        }
        searchFieldFocused = true
    }

    /// The floating bars' height above the safe area.
    private static let barHeight: CGFloat = 56

    /// The page number while the bars are hidden. VoiceOver users can show
    /// the bars instead.
    private var pageIndicator: some View {
        Text("\(model.currentPageIndex + 1) / \(model.pageCount)")
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

                Button(action: startSearch) {
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
                Button(action: endSearch) {
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
                    let count = "\(search.countText)\(search.isFinding && !search.isCapped ? "+" : "")"
                    Text("\(index + 1) of \(count)")
                        .accessibilityLabel("Match \(index + 1) of \(count)")
                } else if !search.isFinding {
                    Text("None")
                        .accessibilityLabel("No matches")
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
            Button("Go to Page…", systemImage: "number") {
                showingGoToPage = true
            }

            Section {
                DisplaySettingsPickers(layout: $layout, appearance: $appearance)

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
}
#endif
