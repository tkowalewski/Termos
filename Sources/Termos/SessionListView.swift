import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var state
    /// The terminal whose name is being edited inline.
    @State private var renamingID: TerminalSession.ID?

    var body: some View {
        @Bindable var state = state

        List(selection: $state.activeSessionID) {
            ForEach(state.sessions) { session in
                SessionRow(
                    session: session,
                    shortcut: state.shortcutNumber(for: session),
                    isRenaming: renamingID == session.id,
                    onTitleClick: { titleClicked(session) },
                    onRenameEnd: { name in endRename(session, name: name) }
                )
                .tag(session.id)
                .contextMenu {
                    Button("Rename Terminal") { renamingID = session.id }
                    Button("Close Terminal") { state.close(session) }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                state.newSession()
            } label: {
                Label("New Terminal", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
    }

    /// Clicking the title of the active terminal renames it, like a file in Finder.
    /// On any other terminal the click just selects it.
    private func titleClicked(_ session: TerminalSession) {
        if state.activeSessionID == session.id {
            renamingID = session.id
        } else {
            state.activeSessionID = session.id
        }
    }

    /// `name` is nil when editing was cancelled.
    private func endRename(_ session: TerminalSession, name: String?) {
        guard renamingID == session.id else { return }
        renamingID = nil
        if let name { state.rename(session, to: name) }
        state.requestMainFocus()
    }
}

private struct SessionRow: View {
    let session: TerminalSession
    let shortcut: Int?
    let isRenaming: Bool
    let onTitleClick: () -> Void
    let onRenameEnd: (String?) -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
            if isRenaming {
                RenameField(initialName: session.displayTitle, onEnd: onRenameEnd)
            } else {
                Text(session.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .onTapGesture(perform: onTitleClick)
            }
            Spacer(minLength: 4)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Inline editor for a terminal's name. Return or clicking elsewhere saves, Esc cancels.
private struct RenameField: View {
    let onEnd: (String?) -> Void
    @State private var name: String
    @State private var finished = false
    @FocusState private var isFocused: Bool

    init(initialName: String, onEnd: @escaping (String?) -> Void) {
        self.onEnd = onEnd
        _name = State(initialValue: initialName)
    }

    var body: some View {
        TextField("Terminal name", text: $name)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { finish(name) }
            .onExitCommand { finish(nil) }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish(name) }
            }
            .onAppear { isFocused = true }
    }

    private func finish(_ result: String?) {
        guard !finished else { return }
        finished = true
        onEnd(result)
    }
}
