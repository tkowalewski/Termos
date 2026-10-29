import AppKit
import SwiftTerm
import SwiftUI

/// Shows the terminal views of the given session, swapping them in place when the
/// active session changes so the other sessions' views stay alive off-screen.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    /// Bumped by `AppState` when the terminal should take keyboard focus back.
    let focusRequest: Int

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.onFocusPane = { [weak session] index in session?.focusedPaneIndex = index }
        container.show(session.panes, focused: session.focusedPaneIndex)
        container.handleFocusRequest(focusRequest)
    }
}

/// Lays out one terminal view, or two split into an upper and a lower pane.
final class TerminalContainerView: NSView {
    static let padding: CGFloat = 10

    /// Reports the pane the user clicked into.
    var onFocusPane: ((Int) -> Void)?

    private var panes: [LocalProcessTerminalView] = []
    private var focusedIndex = 0
    private let separator = NSBox()
    private var lastFocusRequest = 0
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        separator.boxType = .separator
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                trackClickedPane(event)
                return event
            }
            return handleWordJump(event)
        }
    }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    private var focusedPane: LocalProcessTerminalView? {
        panes.isEmpty ? nil : panes[min(focusedIndex, panes.count - 1)]
    }

    func show(_ newPanes: [LocalProcessTerminalView], focused index: Int) {
        let panesChanged = newPanes.count != panes.count || zip(newPanes, panes).contains { $0 !== $1 }
        let focusChanged = index != focusedIndex
        guard panesChanged || focusChanged else { return }

        if panesChanged {
            for pane in panes where !newPanes.contains(where: { $0 === pane }) {
                pane.removeFromSuperview()
            }
            for pane in newPanes where pane.superview !== self {
                pane.autoresizingMask = []
                addSubview(pane)
            }
            panes = newPanes
            if panes.count > 1 {
                if separator.superview == nil { addSubview(separator) }
            } else {
                separator.removeFromSuperview()
            }
            needsLayout = true
            applyColors()
        }
        focusedIndex = index
        focusTerminal()
    }

    /// Lays the terminals out explicitly: autoresizing would keep wrong margins
    /// when a view was added while this container still had a zero size.
    override func layout() {
        super.layout()
        guard panes.count > 1 else {
            let inset = bounds.insetBy(dx: Self.padding, dy: Self.padding)
            panes.first?.frame = inset.isNull ? .zero : inset
            return
        }

        // Two equal halves, upper pane first (the container is not flipped, so it gets the higher y).
        let half = (bounds.height / 2).rounded(.down)
        let lower = NSRect(x: 0, y: 0, width: bounds.width, height: half)
        let upper = NSRect(x: 0, y: half + 1, width: bounds.width, height: bounds.height - half - 1)
        separator.frame = NSRect(x: 0, y: half, width: bounds.width, height: 1)
        for (pane, rect) in zip(panes, [upper, lower]) {
            let inset = rect.insetBy(dx: Self.padding, dy: Self.padding)
            pane.frame = inset.isNull ? .zero : inset
        }
    }

    func handleFocusRequest(_ request: Int) {
        guard request != lastFocusRequest else { return }
        lastFocusRequest = request
        focusTerminal()
    }

    /// Clicking into a pane (or the padding around it) focuses that pane.
    private func trackClickedPane(_ event: NSEvent) {
        guard event.window === window, panes.count > 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        let index = point.y >= bounds.height / 2 ? 0 : 1
        if index != focusedIndex { onFocusPane?(index) }
    }

    /// Option+Left/Right jump by word, like Terminal.app.
    ///
    /// With Option no longer acting as Meta (see `TerminalSession`), SwiftTerm
    /// sends nothing for these keys, so the Emacs word motions are sent here.
    private func handleWordJump(_ event: NSEvent) -> NSEvent? {
        guard let terminalView = panes.first(where: { $0.window?.firstResponder === $0 }),
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .option,
              let key = event.charactersIgnoringModifiers?.unicodeScalars.first else { return event }
        let sequence: [UInt8]
        switch Int(key.value) {
        case NSLeftArrowFunctionKey: sequence = [0x1B, 0x62]  // ESC b
        case NSRightArrowFunctionKey: sequence = [0x1B, 0x66]  // ESC f
        default: return event
        }
        terminalView.send(source: terminalView, data: sequence[...])
        return nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Gives the terminal and the padding around it the same explicit colors.
    ///
    /// SwiftTerm's defaults can't be trusted for this: it renders the system text
    /// background (white in light mode) while `nativeBackgroundColor` reports black,
    /// so a padding painted from that property came out in the wrong color.
    private func applyColors() {
        let colors = TerminalColors(for: effectiveAppearance)
        layer?.backgroundColor = colors.background.cgColor
        for terminalView in panes {
            if terminalView.nativeBackgroundColor != colors.background {
                terminalView.nativeBackgroundColor = colors.background
            }
            if terminalView.nativeForegroundColor != colors.foreground {
                terminalView.nativeForegroundColor = colors.foreground
            }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTerminal()
    }

    private func focusTerminal() {
        // Deferred: right after a switch the view may not be in the window yet.
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.focusedPane, let window = view.window else { return }
            window.makeFirstResponder(view)
        }
    }
}

/// Terminal colors matching the editor themes (see `EditorAppearance`).
private struct TerminalColors {
    let background: NSColor
    let foreground: NSColor

    init(for appearance: NSAppearance) {
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            background = NSColor(srgbRed: 0x1F / 255, green: 0x1F / 255, blue: 0x24 / 255, alpha: 1)
            foreground = NSColor(srgbRed: 0xDF / 255, green: 0xDF / 255, blue: 0xE0 / 255, alpha: 1)
        } else {
            background = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            foreground = NSColor(srgbRed: 0x1F / 255, green: 0x1F / 255, blue: 0x24 / 255, alpha: 1)
        }
    }
}
