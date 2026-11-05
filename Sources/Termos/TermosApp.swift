import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        let canQuit = MainActor.assumeIsolated {
            // No terminals left means the last one was just closed, which already asked.
            (state.sessions.isEmpty || Alerts.confirmQuit(terminalCount: state.sessions.count))
                && state.resolveAllUnsavedDocuments()
        }
        return canQuit ? .terminateNow : .terminateCancel
    }

    /// The window's close button quits instead of closing the window, so the quit
    /// confirmation comes before the window (and every terminal in it) is gone.
    @objc private func closeButtonClicked(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    private func retargetCloseButton(of window: NSWindow) {
        guard let button = window.standardWindowButton(.closeButton), button.target !== self else { return }
        button.target = self
        button.action = #selector(closeButtonClicked(_:))
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // One window with its own terminal list; no window tabs or their shortcuts.
        NSWindow.allowsAutomaticWindowTabbing = false

        // SwiftUI creates the window later and owns its delegate, so the close button is
        // taken over once the window shows up.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.retargetCloseButton(of: window) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when running the bare executable (swift run, Xcode) instead of the .app
        // bundle, which would otherwise get the generic icon from its missing Info.plist.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct TermosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState()

    var body: some Scene {
        Window("Termos", id: "main") {
            ContentView()
                .environment(state)
                .onAppear { appDelegate.state = state }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            TermosCommands(state: state)
        }
    }
}
