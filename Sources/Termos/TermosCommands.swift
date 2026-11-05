import SwiftUI

/// Application menus and their keyboard shortcuts.
///
/// Shortcuts live in the menu so AppKit resolves them before the focused
/// terminal view sees the key, which keeps Cmd+… away from the shell.
///
/// Items stay enabled with fixed titles: SwiftUI does not re-evaluate menu
/// commands when `AppState` changes, so `.disabled` would get stuck. Actions
/// that do not apply simply do nothing.
struct TermosCommands: Commands {
    let state: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Terminal") { state.newSession() }
                .keyboardShortcut("t")
            Button("New File") { state.newDocument() }
                .keyboardShortcut("n")
            Button("Open…") { state.showOpenPanel() }
                .keyboardShortcut("o")
            Button("Close") { state.closeActiveItem() }
                .keyboardShortcut("w")
        }

        // Replaces the default "Close" (Cmd+W) that would close the whole window.
        CommandGroup(replacing: .saveItem) {
            Button("Save") { state.saveActiveDocument() }
                .keyboardShortcut("s")
        }

        // Cmd+P is file search here, not Print.
        CommandGroup(replacing: .printItem) {
            Button("Go to File…") { state.toggleQuickOpen() }
                .keyboardShortcut("p")
            Button("Search in Files…") { state.toggleContentSearch() }
                .keyboardShortcut("e")
        }

        CommandGroup(before: .toolbar) {
            Button("Toggle File Browser") { state.toggleFileBrowser() }
                .keyboardShortcut("b")
            Button("Toggle Terminal / Editor") { state.toggleEditor() }
                .keyboardShortcut("`")
            Button("Review Changes") { state.toggleReview() }
                .keyboardShortcut("r")
            Button("Toggle Markdown Preview") { state.toggleMarkdownPreview() }
                .keyboardShortcut("m")
            Divider()
        }

        // Cmd+H splits the terminal instead of hiding the app; Hide Termos stays in the app menu.
        CommandGroup(replacing: .appVisibility) {
            Button("Hide Termos") { NSApp.hide(nil) }
            Button("Hide Others") { NSApp.hideOtherApplications(nil) }
                .keyboardShortcut("h", modifiers: [.command, .option])
            Button("Show All") { NSApp.unhideAllApplications(nil) }
        }

        // No Cmd+Q, so a stray keystroke cannot kill every shell; Quit stays in the app menu.
        CommandGroup(replacing: .appTermination) {
            Button("Quit Termos") { NSApp.terminate(nil) }
        }

        // Cmd+M is the Markdown preview; Minimize stays in the Window menu without a shortcut.
        CommandGroup(replacing: .windowSize) {
            Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
            Button("Zoom") { NSApp.keyWindow?.zoom(nil) }
        }

        CommandMenu("Terminal") {
            Button("Split Terminal") { state.splitTerminal() }
                .keyboardShortcut("h")
            Button("Focus Upper Pane") { state.focusPane(0) }
            Button("Focus Lower Pane") { state.focusPane(1) }

            Divider()

            Button("Find…") { state.performTerminalFind(.showFindInterface) }
                .keyboardShortcut("f")
            Button("Find Next") { state.performTerminalFind(.nextMatch) }
                .keyboardShortcut("g")
            Button("Find Previous") { state.performTerminalFind(.previousMatch) }
                .keyboardShortcut("g", modifiers: [.command, .shift])

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Last Terminal" : "Terminal \(number)") {
                    state.selectSession(shortcut: number)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))))
            }

        }
    }
}
