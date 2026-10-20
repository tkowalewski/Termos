import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var sessionListWidth: CGFloat = 190
    @State private var fileBrowserWidth: CGFloat = 240

    var body: some View {
        // Fixed panel widths with our own resize handles: HSplitView redistributes
        // space unpredictably when the file browser appears.
        HStack(spacing: 0) {
            SessionListView()
                .frame(width: sessionListWidth)
            ResizeHandle(width: $sessionListWidth, range: 140...320)

            if state.isFileBrowserVisible, let root = state.fileBrowserRoot {
                FileBrowserPanel(
                    root: root,
                    memory: state.fileBrowserMemory,
                    onOpenFile: { state.openFile($0) },
                    onDismiss: { state.hideFileBrowser() }
                )
                .frame(width: fileBrowserWidth)
                ResizeHandle(width: $fileBrowserWidth, range: 160...480)
            }

            Group {
                if let session = state.activeSession {
                    if session.editor.isVisible, session.editor.activeDocument != nil {
                        EditorView(
                            workspace: session.editor,
                            focusRequest: state.mainFocusRequest,
                            onSelect: { state.selectDocument($0) },
                            onClose: { state.closeDocument($0) },
                            onEscape: { state.showTerminal() }
                        )
                    } else {
                        TerminalHostView(session: session, focusRequest: state.mainFocusRequest)
                    }
                } else {
                    Color(nsColor: .textBackgroundColor)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if let quickOpen = state.quickOpen {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.12)
                            .onTapGesture { state.dismissQuickOpen() }
                        QuickOpenView(
                            model: quickOpen,
                            onOpen: { state.openFromQuickOpen($0) },
                            onDismiss: { state.dismissQuickOpen() }
                        )
                        .padding(.top, 48)
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 400)
        .navigationTitle(state.activeSession?.displayTitle ?? "Termos")
    }
}

/// A one-point divider with a wider invisible grab area that resizes the panel to its left.
private struct ResizeHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    @State private var widthAtDragStart: CGFloat?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = widthAtDragStart ?? width
                                widthAtDragStart = start
                                width = min(max(start + drag.translation.width, range.lowerBound), range.upperBound)
                            }
                            .onEnded { _ in widthAtDragStart = nil }
                    )
            }
    }
}
