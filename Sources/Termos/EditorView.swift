import AppKit
import CodeEditSourceEditor
import SwiftUI

/// Tabs of the open files above the editor of the active one.
struct EditorView: View {
    let workspace: EditorWorkspace
    /// Bumped by `AppState` when the editor should take keyboard focus back.
    let focusRequest: Int
    let onSelect: (EditorDocument) -> Void
    let onClose: (EditorDocument) -> Void
    let onEscape: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            EditorTabBar(workspace: workspace, onSelect: onSelect, onClose: onClose)
            Divider()
            if let document = workspace.activeDocument {
                EditorHostView(document: document, focusRequest: focusRequest, onEscape: onEscape)
            }
        }
    }
}

private struct EditorTabBar: View {
    let workspace: EditorWorkspace
    let onSelect: (EditorDocument) -> Void
    let onClose: (EditorDocument) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(workspace.documents) { document in
                    EditorTab(
                        document: document,
                        isActive: document.id == workspace.activeDocumentID,
                        onSelect: { onSelect(document) },
                        onClose: { onClose(document) }
                    )
                    Divider()
                }
            }
        }
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct EditorTab: View {
    let document: EditorDocument
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: document.url.path))
                .resizable()
                .frame(width: 14, height: 14)
            Text(document.name)
                .lineLimit(1)
            Button(action: onClose) {
                // A dot marks unsaved changes; it turns into the close button on hover, like in VS Code.
                Image(systemName: document.isDirty && !isHovered ? "circle.fill" : "xmark")
                    .font(.system(size: document.isDirty && !isHovered ? 7 : 9, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .opacity(isActive || isHovered || document.isDirty ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(isActive ? Color(nsColor: .textBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovered = $0 }
        .help(document.url.path)
    }
}

/// Hosts the active document's editor view, swapping it in place like the terminal host.
private struct EditorHostView: NSViewRepresentable {
    let document: EditorDocument
    let focusRequest: Int
    let onEscape: () -> Void

    func makeNSView(context: Context) -> EditorContainerView {
        EditorContainerView()
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        container.onEscape = onEscape
        container.show(document)
        container.handleFocusRequest(focusRequest)
    }
}

final class EditorContainerView: NSView {
    var onEscape: (() -> Void)?
    private weak var current: EditorDocument?
    private var eventMonitor: Any?
    /// Set after Cmd+K, waiting for the second key of the chord.
    private var awaitingChord = false
    private var lastFocusRequest: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Since macOS 14 views do not clip by default; the editor's floating line-number
        // gutter would otherwise slide over the tab bar when scrolling down.
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func handleFocusRequest(_ request: Int) {
        defer { lastFocusRequest = request }
        guard let lastFocusRequest, lastFocusRequest != request else { return }
        focusEditor()
    }

    func show(_ document: EditorDocument) {
        guard current !== document else { return }

        current?.controller.view.removeFromSuperview()
        let view = document.controller.view
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        current = document

        applyTheme()
        refreshCursorPositions()
        focusEditor()
    }

    /// Esc reaches here through the responder chain when the editor does not use it
    /// itself (the find panel and completions take it first). Several cursors
    /// collapse to one first; only then Esc goes back to the terminal.
    override func cancelOperation(_ sender: Any?) {
        if current?.multiCursor.collapseToSingleCursor() == true { return }
        onEscape?()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
        focusEditor()
    }

    // MARK: Multi-cursor input that menus cannot express

    private func updateEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    /// Handles Option+click, the Cmd+K Cmd+D chord and clipboard with several cursors.
    /// Returns nil when the event was used.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let document = current,
              let textView = document.controller.textView,
              event.window === window, window?.firstResponder === textView else {
            awaitingChord = false
            return event
        }
        let multiCursor = document.multiCursor
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if event.type == .leftMouseDown {
            let point = textView.convert(event.locationInWindow, from: nil)
            guard flags == .option, event.clickCount == 1, textView.bounds.contains(point),
                  let offset = textView.layoutManager.textOffsetAtPoint(point) else { return event }
            multiCursor.addCursor(at: offset)
            return nil
        }

        let key = event.charactersIgnoringModifiers?.lowercased()
        if awaitingChord {
            awaitingChord = false
            if flags == .command, key == "d" {
                multiCursor.skipOccurrence()
                return nil
            }
            return event
        }

        guard flags == .command else { return event }
        switch key {
        case "k":
            awaitingChord = true
            return nil
        case "c":
            return multiCursor.copy() ? nil : event
        case "x":
            return multiCursor.cut() ? nil : event
        case "v":
            return multiCursor.paste() ? nil : event
        default:
            return event
        }
    }

    private func applyTheme() {
        guard let controller = current?.controller else { return }
        let theme = EditorAppearance.theme(for: effectiveAppearance)
        if controller.configuration.appearance.theme != theme {
            controller.configuration.appearance.theme = theme
        }
    }

    /// Re-applies the selections once the editor is laid out in the window.
    ///
    /// Each cursor remembers the x position that Up/Down keep to. It is computed when
    /// the cursor is set, and the first cursor is set while the editor has no size and
    /// no gutter yet, so Up/Down would aim outside the text and not move at all.
    private func refreshCursorPositions() {
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.current?.controller.textView, textView.window != nil,
                  let selectionManager = textView.selectionManager else { return }
            textView.layoutSubtreeIfNeeded()
            selectionManager.setSelectedRanges(selectionManager.textSelections.map(\.range))
        }
    }

    private func focusEditor() {
        DispatchQueue.main.async { [weak self] in
            guard let textView = self?.current?.controller.textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }
}
