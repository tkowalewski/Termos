import AppKit
import Observation
import SwiftTerm

/// One shell running in a pseudo-terminal, with its view.
///
/// The view is kept alive while the session is hidden, so switching terminals
/// never loses scrollback or the state of the running program.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    let id = UUID()
    /// Title set by the shell or the running program.
    private(set) var title: String
    /// Name given by the user in the terminal list. Overrides `title` while set.
    var customTitle: String?

    var displayTitle: String {
        customTitle ?? title
    }

    /// Last directory reported by the shell through OSC 7, if it reports one.
    private(set) var reportedDirectory: URL?

    /// Files this terminal has open, shown in place of the terminal when visible.
    let editor = EditorWorkspace()

    @ObservationIgnored let terminalView: LocalProcessTerminalView
    @ObservationIgnored var onExit: ((TerminalSession) -> Void)?

    init(startDirectory: URL?) {
        let shell = Self.loginShell()
        title = (shell as NSString).lastPathComponent

        terminalView = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.processDelegate = self
        // Option types characters (e.g. Option+L = "ł" on the Polish layout) instead of acting as Meta.
        terminalView.optionAsMetaKey = false
        // SwiftTerm keeps only 500 lines by default.
        terminalView.changeScrollback(10_000)

        let directory = startDirectory?.path ?? FileManager.default.homeDirectoryForCurrentUser.path
        terminalView.startProcess(
            executable: shell,
            environment: Self.environment(),
            // A leading "-" in argv[0] makes the shell a login shell, like Terminal.app does.
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: directory
        )
    }

    var processID: pid_t {
        terminalView.process.shellPid
    }

    /// The shell's working directory: read straight from the process, falling back to OSC 7.
    func currentDirectory() -> URL? {
        ProcessDirectory.currentDirectory(of: processID) ?? reportedDirectory
    }

    func terminate() {
        onExit = nil
        terminalView.terminate()
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
            if !title.isEmpty { self.title = title }
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        MainActor.assumeIsolated {
            reportedDirectory = directory.flatMap(ProcessDirectory.url(fromOSC7:))
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        MainActor.assumeIsolated {
            onExit?(self)
        }
    }
}
