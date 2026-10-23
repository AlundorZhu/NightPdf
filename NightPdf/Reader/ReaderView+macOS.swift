//
//  ReaderView+macOS.swift
//  NightPdf
//

#if os(macOS)
import SwiftUI

/// The reader on the Mac: contents and pages in a sidebar, search and the
/// display settings in the toolbar, the page number under the window title,
/// and nothing floating over the pages. The
/// iPhone and iPad's is in ReaderView.swift.
struct DocumentReader: View {
    let model: ReaderModel
    @Bindable var search: DocumentSearch

    @AppStorage("pageAppearance") private var appearance = PageAppearance.automatic
    @AppStorage("pageLayout") private var layout = PageLayout.continuous
    /// Whether the sidebar was showing when last shown or hidden, for the next
    /// window to open. Each window keeps its own after that, rather than all
    /// of them following one.
    @AppStorage(Self.showsSidebarKey) private var showsSidebar = true
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarVisibility: NavigationSplitViewVisibility
    @State private var sidebarTab: ContentsTab?
    @State private var showingGoToPage = false
    @State private var showingResults = false
    @FocusState private var searchFieldFocused: Bool

    private static let showsSidebarKey = "showsSidebar"

    init(model: ReaderModel, search: DocumentSearch) {
        self.model = model
        self.search = search
        let showsSidebar = UserDefaults.standard.object(forKey: Self.showsSidebarKey) as? Bool ?? true
        _sidebarVisibility = State(initialValue: showsSidebar ? .all : .detailOnly)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 420)
        } detail: {
            PDFKitView(model: model, layout: layout, invertsPages: appearance.invertsPages(in: colorScheme))
                .toolbar { toolbar }
                // Where Preview shows it. In the toolbar it would sit in a glass bubble.
                .navigationSubtitle("Page \(model.currentPageIndex + 1) of \(model.pageCount)")
        }
        .onChange(of: sidebarVisibility) { _, visibility in
            showsSidebar = visibility != .detailOnly
        }
        .searchable(text: $search.query, placement: .toolbar, prompt: "Search")
        .searchFocused($searchFieldFocused)
        .onSubmit(of: .search) {
            search.begin()
            search.submit()
        }
        // Searches as you type, once the typing pauses; Return searches at once.
        .task(id: search.query) {
            guard !search.query.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            search.begin()
            search.searchAsTyped()
        }
        // Clearing the field, with its button or Escape, ends the search and its highlights.
        .onChange(of: search.query) { _, query in
            if query.isEmpty && search.isActive { search.end() }
        }
        // So does leaving it empty, e.g. ⌘F and then Escape.
        .onChange(of: searchFieldFocused) { _, isFocused in
            if !isFocused && search.query.isEmpty && search.isActive { search.end() }
        }
        .focusedSceneValue(\.readerActions, actions)
        .onDisappear {
            model.savePosition()
        }
        .goToPageAlert(isPresented: $showingGoToPage, model: model)
    }

    /// For the menu bar.
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

    private func startSearch() {
        search.begin()
        searchFieldFocused = true
    }

    // MARK: - Sidebar

    private var selectedTab: Binding<ContentsTab> {
        Binding(
            get: { sidebarTab ?? .initial(for: model) },
            set: { sidebarTab = $0 }
        )
    }

    /// Choosing an entry or a page goes there and leaves the sidebar open; the
    /// current one stays marked as the reader scrolls.
    private var sidebar: some View {
        VStack(spacing: 0) {
            Picker("View", selection: selectedTab) {
                ForEach(ContentsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            switch selectedTab.wrappedValue {
            case .outline:
                OutlineList(model: model) { destination in model.go(to: destination) }
            case .pages:
                PagesGrid(model: model) { index in model.go(toPage: index) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Toolbar

    /// Icons only, each for one thing, rather than a "More" menu: the Mac's
    /// toolbar has the room, and Print and Go to Page are in the menu bar.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let point = model.returnStack.last {
            ToolbarItem(placement: .navigation) {
                ReturnButton(model: model, point: point)
                    .help("Back to Page \(point.pageIndex + 1)")
            }
        }

        if search.isActive {
            // Plain text, not a control, so no bubble behind it.
            ToolbarItem(placement: .primaryAction) {
                searchStatus
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button("Previous Match", systemImage: "chevron.up", action: search.previous)
                        .help("Previous Match (⇧⌘G)")
                    Button("Next Match", systemImage: "chevron.down", action: search.next)
                        .help("Next Match (⌘G)")
                }
                .disabled(search.results.isEmpty)
            }

            ToolbarItem(placement: .primaryAction) {
                Button("All Results", systemImage: "list.bullet") {
                    showingResults = true
                }
                .help("All Results")
                .disabled(search.results.isEmpty)
                .popover(isPresented: $showingResults, arrowEdge: .bottom) {
                    SearchResultsView(search: search)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Layout", selection: $layout) {
                    ForEach(PageLayout.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Layout", systemImage: layout.systemImage)
            }
            .help("Layout")
        }

        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Page Color", selection: $appearance) {
                    ForEach(PageAppearance.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Page Color", systemImage: "circle.lefthalf.filled")
            }
            .help("Page Color")
        }

        if let url = model.fileURL {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: url)
                    .help("Share")
            }
        }
    }

    @ViewBuilder
    private var searchStatus: some View {
        let isCurrent = search.query.trimmingCharacters(in: .whitespacesAndNewlines) == search.searchedQuery
        if isCurrent && search.isFinding && search.results.isEmpty {
            ProgressView()
                .controlSize(.small)
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
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
        }
    }
}
#endif
