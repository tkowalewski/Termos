import AppKit
import Observation
import SwiftTerm

/// A terminal in the list: one shell running in a pseudo-terminal, with its view,
/// or two of them when split into an upper and a lower pane (Cmd+H).
///
/// The views are kept alive while the session is hidden, so switching terminals
/// never loses scrollback or the state of the running program.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id = UUID()
    /// Name given by the user in the terminal list. Overrides the shell's title while set.
    var customTitle: String?

    /// Title set by the shell or the running program in the focused pane.
    var displayTitle: String {
        customTitle ?? titles[ObjectIdentifier(focusedPane)] ?? shellName
    }

    /// The upper pane, then the lower one when split.
    private(set) var panes: [LocalProcessTerminalView] = []
    /// The pane that has (or gets back) keyboard focus and whose directory the file browser follows.
    var focusedPaneIndex = 0

    var focusedPane: LocalProcessTerminalView {
        panes[min(focusedPaneIndex, panes.count - 1)]
    }

    var isSplit: Bool { panes.count > 1 }

    private let shellName: String
    /// Titles set by the shell or the running program, per pane.
    private var titles: [ObjectIdentifier: String] = [:]
    /// Last directory reported by each pane's shell through OSC 7, if it reports one.
    @ObservationIgnored private var reportedDirectories: [ObjectIdentifier: URL] = [:]

    /// Files this terminal has open, shown in place of the terminal when visible.
    let editor = EditorWorkspace()
    /// Each terminal shows or hides its own file browser (Cmd+B); hidden by default.
    var isFileBrowserVisible = false
    /// Review mode (Cmd+R) while it is shown, in place of the file browser and the terminal or editor.
    var review: ReviewModel?
    /// The file last selected in review mode, selected again when it opens next time.
    @ObservationIgnored var lastReviewSelection: GitChange.ID?

    /// Called when the shell of the last pane exits.
    @ObservationIgnored var onExit: ((TerminalSession) -> Void)?

    init(startDirectory: URL?) {
        shellName = (Self.loginShell() as NSString).lastPathComponent
        panes = [makePane(directory: startDirectory)]
    }

    /// Opens a second shell below, in the focused pane's working directory, and focuses it.
    func split() {
        guard !isSplit else { return }
        panes.append(makePane(directory: currentDirectory()))
        focusedPaneIndex = panes.count - 1
    }

    /// Closes the focused pane's shell; the other pane takes the whole terminal.
    func closeFocusedPane() {
        guard isSplit else { return }
        let pane = focusedPane
        remove(pane)
        pane.terminate()
    }

    /// The focused pane's working directory: read straight from its process, falling back to OSC 7.
    func currentDirectory() -> URL? {
        let pane = focusedPane
        return ProcessDirectory.currentDirectory(of: pane.process.shellPid)
            ?? reportedDirectories[ObjectIdentifier(pane)]
    }

    func terminate() {
        onExit = nil
        panes.forEach { $0.terminate() }
    }

    private func makePane(directory: URL?) -> LocalProcessTerminalView {
        let shell = Self.loginShell()
        let pane = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        pane.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        pane.processDelegate = self
        // Option types characters (e.g. Option+L = "ł" on the Polish layout) instead of acting as Meta.
        pane.optionAsMetaKey = false
        // SwiftTerm keeps only 500 lines by default.
        pane.changeScrollback(10_000)

        pane.startProcess(
            executable: shell,
            environment: Self.environment(),
            // A leading "-" in argv[0] makes the shell a login shell, like Terminal.app does.
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: directory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        )
        return pane
    }

    private func remove(_ pane: LocalProcessTerminalView) {
        guard let index = panes.firstIndex(where: { $0 === pane }) else { return }
        panes.remove(at: index)
        titles[ObjectIdentifier(pane)] = nil
        reportedDirectories[ObjectIdentifier(pane)] = nil
        focusedPaneIndex = min(focusedPaneIndex, panes.count - 1)
    }

    private static func loginShell() -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static func environment() -> [String] {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["TERM_PROGRAM"] = "Termos"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        return environment.map { "\($0.key)=\($0.value)" }
    }
}

extension TerminalSession: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        MainActor.assumeIsolated {
            if !title.isEmpty { titles[ObjectIdentifier(source)] = title }
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            reportedDirectories[ObjectIdentifier(source)] = directory.flatMap(ProcessDirectory.url(fromOSC7:))
        }
    }

    /// A pane whose shell exits closes; the terminal closes with its last pane.
    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            guard let pane = panes.first(where: { $0 === source }) else { return }
            if isSplit {
                remove(pane)
            } else {
                onExit?(self)
            }
        }
    }
}
