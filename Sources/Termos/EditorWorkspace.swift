import Foundation
import Observation

/// The files a terminal session has open in its editor, and whether the editor is shown.
@MainActor
@Observable
final class EditorWorkspace {
    private(set) var documents: [EditorDocument] = []
    var activeDocumentID: EditorDocument.ID?
    /// Shown in place of the terminal when true.
    var isVisible = false

    var activeDocument: EditorDocument? {
        documents.first { $0.id == activeDocumentID }
    }

    var hasUnsavedChanges: Bool {
        documents.contains(where: \.isDirty)
    }

    /// Opens the file, or switches to it if it is already open.
    func open(_ url: URL) throws {
        let url = url.standardizedFileURL
        if let existing = documents.first(where: { $0.url == url }) {
            activeDocumentID = existing.id
        } else {
            let document = try EditorDocument(url: url)
            documents.append(document)
            activeDocumentID = document.id
        }
        isVisible = true
    }

    /// Opens an empty, untitled file: "Untitled", then "Untitled 2" and so on.
    func newDocument() {
        let names = Set(documents.filter { $0.url == nil }.map(\.name))
        let name = (1...).lazy.map { $0 == 1 ? "Untitled" : "Untitled \($0)" }.first { !names.contains($0) }!
        let document = EditorDocument(untitledName: name)
        documents.append(document)
        activeDocumentID = document.id
        isVisible = true
    }

    func close(_ document: EditorDocument) {
        guard let index = documents.firstIndex(where: { $0.id == document.id }) else { return }
        documents.remove(at: index)

        if documents.isEmpty {
            activeDocumentID = nil
            isVisible = false
        } else if activeDocumentID == document.id {
            activeDocumentID = documents[min(index, documents.count - 1)].id
        }
    }
}
