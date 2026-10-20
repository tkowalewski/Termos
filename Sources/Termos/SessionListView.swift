import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        List(selection: $state.activeSessionID) {
            ForEach(state.sessions) { session in
                SessionRow(session: session, shortcut: state.shortcutNumber(for: session))
                    .tag(session.id)
                    .contextMenu {
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
}

private struct SessionRow: View {
    let session: TerminalSession
    let shortcut: Int?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
            Text(session.title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
