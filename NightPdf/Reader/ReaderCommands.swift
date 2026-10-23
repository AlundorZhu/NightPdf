//
//  ReaderCommands.swift
//  NightPdf
//

import SwiftUI

/// What the menu bar's commands do in the focused document window. The reader
/// publishes it with `focusedSceneValue`, since its search and Go to Page
/// state live in the view.
struct ReaderActions {
    var find: () -> Void
    /// Nil when there are no matches to step through.
    var findNext: (() -> Void)?
    var findPrevious: (() -> Void)?
    var goToPage: () -> Void
    var print: () -> Void
}

extension FocusedValues {
    @Entry var readerActions: ReaderActions?
}

/// The reader's menu bar items: Find, Go to Page, the display settings and
/// Print. They show on iPad with a hardware keyboard too.
struct ReaderCommands: Commands {
    @FocusedValue(\.readerActions) private var actions
    @AppStorage("pageAppearance") private var appearance = PageAppearance.automatic
    @AppStorage("pageLayout") private var layout = PageLayout.continuous

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            Button("Print…") { actions?.print() }
                .keyboardShortcut("p")
                .disabled(actions == nil)
        }

        // In place of the text Find submenu, which searches a text view, not the document.
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { actions?.find() }
                .menuShortcut("f")
                .disabled(actions == nil)
            Button("Find Next") { actions?.findNext?() }
                .menuShortcut("g")
                .disabled(actions?.findNext == nil)
            Button("Find Previous") { actions?.findPrevious?() }
                .menuShortcut("g", modifiers: [.command, .shift])
                .disabled(actions?.findPrevious == nil)
        }

        CommandGroup(after: .toolbar) {
            DisplaySettingsPickers(layout: $layout, appearance: $appearance)
        }

        CommandMenu("Go") {
            Button("Go to Page…") { actions?.goToPage() }
                .keyboardShortcut("g", modifiers: [.command, .option])
                .disabled(actions == nil)
        }
    }
}

private extension View {
    /// A shortcut the menu bar owns on the Mac. On iPhone and iPad the bar
    /// buttons keep it, so it isn't claimed twice.
    func menuShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command) -> some View {
        #if os(macOS)
        keyboardShortcut(key, modifiers: modifiers)
        #else
        self
        #endif
    }
}

/// The layout and page color choices, for the reader's More menu and the
/// View menu.
struct DisplaySettingsPickers: View {
    @Binding var layout: PageLayout
    @Binding var appearance: PageAppearance

    var body: some View {
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
}

extension PageAppearance {
    func invertsPages(in colorScheme: ColorScheme) -> Bool {
        switch self {
        case .automatic: colorScheme == .dark
        case .light: false
        case .dark: true
        }
    }
}

extension View {
    /// Asks for a page number and goes there.
    func goToPageAlert(isPresented: Binding<Bool>, model: ReaderModel) -> some View {
        modifier(GoToPageAlert(model: model, isPresented: isPresented))
    }
}

private struct GoToPageAlert: ViewModifier {
    let model: ReaderModel
    @Binding var isPresented: Bool

    @State private var pageText = ""

    func body(content: Content) -> some View {
        content
            .alert("Go to Page", isPresented: $isPresented) {
                TextField("Page", text: $pageText)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Go", action: goToEnteredPage)
                    .disabled(enteredPage == nil)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Enter a page number between 1 and \(model.pageCount).")
            }
            #if os(macOS)
            // Only digits, as there's no number pad to limit what's typed. Put
            // back into the state, so the field shows the change.
            .onChange(of: pageText) { _, text in
                let digits = String(text.filter { $0.isASCII && $0.isNumber })
                if digits != text { pageText = digits }
            }
            #endif
            // Cleared on the way out, so the field is empty the next time.
            .onChange(of: isPresented) { _, isPresented in
                if !isPresented { pageText = "" }
            }
    }

    /// The entered page number, if it's one the document has.
    private var enteredPage: Int? {
        guard let number = Int(pageText.trimmingCharacters(in: .whitespaces)),
              (1...model.pageCount).contains(number)
        else { return nil }
        return number
    }

    private func goToEnteredPage() {
        guard let enteredPage else { return }
        model.go(toPage: enteredPage - 1)
    }
}
