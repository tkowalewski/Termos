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
        }

        CommandGroup(before: .toolbar) {
            Button("Toggle File Browser") { state.toggleFileBrowser() }
                .keyboardShortcut("b")
            Button("Toggle Terminal / Editor") { state.toggleEditor() }
                .keyboardShortcut("`")
            Button("Review Changes") { state.toggleReview() }
                .keyboardShortcut("r")
            Divider()
        }

        // Multiple cursors, with VS Code's shortcuts. Cmd+K Cmd+D (skip occurrence)
        // is a chord, handled by the editor itself.
        CommandMenu("Selection") {
            Button("Add Next Occurrence") { state.activeDocument?.multiCursor.addNextOccurrence() }
                .keyboardShortcut("d")
            Button("Skip Occurrence (⌘K ⌘D)") { state.activeDocument?.multiCursor.skipOccurrence() }
            Button("Select All Occurrences") { state.activeDocument?.multiCursor.selectAllOccurrences() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Undo Last Cursor") { state.activeDocument?.multiCursor.undoLastCursor() }
                .keyboardShortcut("u")

            Divider()

            Button("Add Cursor Above") { state.activeDocument?.multiCursor.addCursor(above: true) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Add Cursor Below") { state.activeDocument?.multiCursor.addCursor(above: false) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
        }

        CommandMenu("Terminal") {
            ForEach(1...9, id: \.self) { number in
                Button(number == 9 ? "Last Terminal" : "Terminal \(number)") {
                    state.selectSession(shortcut: number)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(number))))
            }

            Divider()

            Button("Previous Terminal") { state.selectAdjacentSession(offset: -1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Next Terminal") { state.selectAdjacentSession(offset: 1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
        }
    }
}
