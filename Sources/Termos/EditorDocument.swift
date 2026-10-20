import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import Observation

enum EditorDocumentError: LocalizedError {
    case tooLarge(URL)
    case binary(URL)
    case unreadable(URL)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let url): "“\(url.lastPathComponent)” is larger than 10 MB."
        case .binary(let url): "“\(url.lastPathComponent)” looks like a binary file."
        case .unreadable(let url): "“\(url.lastPathComponent)” could not be read as text."
        }
    }
}

/// A file open in the editor, with its own editor view controller, so undo
/// history and cursor positions survive switching between files.
@MainActor
@Observable
final class EditorDocument: Identifiable {
    static let maximumSize = 10 * 1024 * 1024

    let id = UUID()
    let url: URL
    private(set) var isDirty = false

    @ObservationIgnored let controller: TextViewController
    @ObservationIgnored let multiCursor: MultiCursorController
    @ObservationIgnored private let changeTracker = ChangeTracker()
    @ObservationIgnored private var encoding: String.Encoding
    @ObservationIgnored private var diskModificationDate: Date?

    var name: String { url.lastPathComponent }

    init(url: URL) throws {
        let (text, encoding) = try Self.read(url)
        self.url = url
        self.encoding = encoding
        diskModificationDate = Self.modificationDate(of: url)

        controller = TextViewController(
            string: text,
            language: CodeLanguage.detectLanguageFrom(url: url, prefixBuffer: String(text.prefix(256))),
            configuration: EditorAppearance.configuration(for: NSApp.effectiveAppearance),
            cursorPositions: [CursorPosition(line: 1, column: 1)],
            coordinators: [changeTracker]
        )
        multiCursor = MultiCursorController(textView: controller.textView)
        changeTracker.onChange = { [weak self] in self?.isDirty = true }
    }

    func save() throws {
        trimTrailingWhitespace()
        let text = controller.text
        guard let data = text.data(using: encoding) ?? text.data(using: .utf8) else {
            throw EditorDocumentError.unreadable(url)
        }
        try data.write(to: url, options: .atomic)
        diskModificationDate = Self.modificationDate(of: url)
        isDirty = false
    }

    /// Whether the file on disk changed since it was opened, saved or reloaded here.
    var changedOnDisk: Bool {
        guard let current = Self.modificationDate(of: url) else { return false }
        return current != diskModificationDate
    }

    func reload() throws {
        let (text, encoding) = try Self.read(url)
        self.encoding = encoding
        diskModificationDate = Self.modificationDate(of: url)
        controller.setText(text)
        isDirty = false
    }

    private static let trailingWhitespace = try! NSRegularExpression(pattern: "[ \\t]+$", options: .anchorsMatchLines)

    /// Removes spaces and tabs at line ends in the editor itself, as one undo step.
    /// Markdown is left alone: two trailing spaces there are a line break.
    private func trimTrailingWhitespace() {
        guard !["md", "markdown"].contains(url.pathExtension.lowercased()),
              let textView = controller.textView else { return }
        let text = textView.string
        let ranges = Self.trailingWhitespace
            .matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .map(\.range)
        guard !ranges.isEmpty else { return }

        textView.undoManager?.beginUndoGrouping()
        textView.replaceCharacters(in: ranges, with: "")
        textView.undoManager?.endUndoGrouping()
    }

    /// Records the current disk state as seen, so the user is not asked again.
    func ignoreDiskChange() {
        diskModificationDate = Self.modificationDate(of: url)
    }

    private static func read(_ url: URL) throws -> (String, String.Encoding) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maximumSize else { throw EditorDocumentError.tooLarge(url) }
        guard let data = try? Data(contentsOf: url) else { throw EditorDocumentError.unreadable(url) }
        guard !data.prefix(8000).contains(0) else { throw EditorDocumentError.binary(url) }

        if let text = String(data: data, encoding: .utf8) {
            return (text, .utf8)
        }
        var converted: NSString?
        let detected = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        guard detected != 0, let converted else { throw EditorDocumentError.unreadable(url) }
        return (converted as String, String.Encoding(rawValue: detected))
    }

    private static func modificationDate(of url: URL) -> Date? {
        // Uncached read: URL resource values may be served from a stale cache.
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

/// Reports edits from the editor. The controller keeps coordinators weakly,
/// so the document owns this object.
private final class ChangeTracker: TextViewCoordinator {
    var onChange: (() -> Void)?

    func prepareCoordinator(controller: TextViewController) {}

    func textViewDidChangeText(controller: TextViewController) {
        onChange?()
    }
}
