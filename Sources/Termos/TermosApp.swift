import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state else { return .terminateNow }
        return MainActor.assumeIsolated { state.resolveAllUnsavedDocuments() } ? .terminateNow : .terminateCancel
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Cmd+Shift+[ / ] are ours (switching terminals), not window tabs.
        NSWindow.allowsAutomaticWindowTabbing = false
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
