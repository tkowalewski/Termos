import AppKit
import SwiftTerm
import SwiftUI

/// Shows the terminal view of the given session, swapping it in place when the
/// active session changes so the other sessions' views stay alive off-screen.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    /// Bumped by `AppState` when the terminal should take keyboard focus back.
    let focusRequest: Int

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.show(session.terminalView)
        container.handleFocusRequest(focusRequest)
    }
}

final class TerminalContainerView: NSView {
    static let padding: CGFloat = 10

    private weak var current: TerminalView?
    private var lastFocusRequest = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func show(_ terminalView: TerminalView) {
        guard current !== terminalView else { return }

        current?.removeFromSuperview()
        terminalView.autoresizingMask = []
        addSubview(terminalView)
        current = terminalView

        needsLayout = true
        applyColors()
        focusTerminal()
    }

    /// Lays the terminal out explicitly: autoresizing would keep wrong margins
    /// when the view was added while this container still had a zero size.
    override func layout() {
        super.layout()
        let inset = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        current?.frame = inset.isNull ? .zero : inset
    }

    func handleFocusRequest(_ request: Int) {
        guard request != lastFocusRequest else { return }
        lastFocusRequest = request
        focusTerminal()
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
        guard let terminalView = current else { return }
        if terminalView.nativeBackgroundColor != colors.background {
            terminalView.nativeBackgroundColor = colors.background
        }
        if terminalView.nativeForegroundColor != colors.foreground {
            terminalView.nativeForegroundColor = colors.foreground
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusTerminal()
    }

    private func focusTerminal() {
        // Deferred: right after a switch the view may not be in the window yet.
        DispatchQueue.main.async { [weak self] in
            guard let view = self?.current, let window = view.window else { return }
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
