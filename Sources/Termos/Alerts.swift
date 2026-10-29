import AppKit

/// Small wrappers around modal NSAlerts.
@MainActor
enum Alerts {
    static func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    /// Returns the index of the chosen button; the first button is the default one.
    static func ask(_ message: String, info: String = "", buttons: [String]) -> Int {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        buttons.forEach { alert.addButton(withTitle: $0) }
        let response = alert.runModal()
        return response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// Asks for a single line of text; `nil` when cancelled or left empty.
    static func askForText(_ message: String, info: String = "", button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 22))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    enum SaveChoice { case save, discard, cancel }

    static func askToSave(_ documents: [EditorDocument]) -> SaveChoice {
        let message = documents.count == 1
            ? "Do you want to save the changes you made to “\(documents[0].name)”?"
            : "Do you want to save the changes you made to \(documents.count) files?"
        switch ask(message, info: "Your changes will be lost if you don’t save them.",
                   buttons: ["Save", "Cancel", "Don’t Save"]) {
        case 0: return .save
        case 2: return .discard
        default: return .cancel
        }
    }
}
