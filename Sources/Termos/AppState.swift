import AppKit
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var sessions: [TerminalSession] = []
    var activeSessionID: TerminalSession.ID? {
        didSet {
            updateDirectoryPolling()
            quickOpen = nil
            contentSearch = nil
        }
    }

    var activeSession: TerminalSession? {
        sessions.first { $0.id == activeSessionID }
    }

    /// Whether the active terminal shows its file browser.
    var isFileBrowserVisible: Bool {
        activeSession?.isFileBrowserVisible == true
    }
    /// Working directory of the active terminal, shown in the file browser.
    private(set) var fileBrowserRoot: URL?
    /// Bumped whenever the terminal or editor should take keyboard focus back.
    private(set) var mainFocusRequest = 0
    /// The Cmd+P file finder, while it is open.
    private(set) var quickOpen: QuickOpenModel?
    /// The Cmd+E content search, while it is open.
    private(set) var contentSearch: ContentSearchModel?

    @ObservationIgnored let fileBrowserMemory = FileBrowserMemory()
    @ObservationIgnored private var directoryPollTimer: Timer?

    init() {
        newSession()

        // Files edited from the terminal (or elsewhere) while Termos was in the background.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkActiveDocumentOnDisk() }
        }
    }

    // MARK: File browser

    func toggleFileBrowser() {
        if activeSession?.review != nil {
            hideReview()
            showFileBrowser()
        } else if isFileBrowserVisible {
            hideFileBrowser()
        } else {
            showFileBrowser()
        }
    }

    func showFileBrowser() {
        guard let session = activeSession, !session.isFileBrowserVisible else { return }
        session.isFileBrowserVisible = true
        updateDirectoryPolling()
    }

    func hideFileBrowser() {
        guard let session = activeSession, session.isFileBrowserVisible else { return }
        session.isFileBrowserVisible = false
        updateDirectoryPolling()
        requestMainFocus()
    }

    /// Follows `cd` in the active terminal while its browser is visible, and only then.
    private func updateDirectoryPolling() {
        guard isFileBrowserVisible else {
            directoryPollTimer?.invalidate()
            directoryPollTimer = nil
            return
        }
        refreshFileBrowserRoot()
        guard directoryPollTimer == nil else { return }
        directoryPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFileBrowserRoot() }
        }
    }

    private func refreshFileBrowserRoot() {
        guard isFileBrowserVisible,
              let directory = activeSession?.currentDirectory(),
              directory.path != fileBrowserRoot?.path else { return }
        fileBrowserRoot = directory
    }

    // MARK: Review

    /// Cmd+R: the git changes of the active terminal's repository, to stage or discard.
    func toggleReview() {
        if activeSession?.review != nil {
            hideReview()
        } else {
            showReview()
        }
    }

    func showReview() {
        guard let session = activeSession, session.review == nil,
              let directory = session.currentDirectory() else { return }
        quickOpen = nil
        contentSearch = nil
        session.review = ReviewModel(directory: directory, initialSelection: session.lastReviewSelection)
    }

    func hideReview() {
        guard let session = activeSession, let review = session.review else { return }
        session.lastReviewSelection = review.selectionID
        session.review = nil
        mainFocusRequest += 1
    }

    // MARK: Quick open

    /// Cmd+P: searches the active terminal's working directory, from the terminal or
    /// the editor. The chosen file opens in the editor.
    func toggleQuickOpen() {
        if quickOpen != nil {
            dismissQuickOpen()
        } else if let root = activeSession?.currentDirectory() {
            contentSearch = nil
            quickOpen = QuickOpenModel(root: root)
        }
    }

    func dismissQuickOpen() {
        quickOpen = nil
        mainFocusRequest += 1
    }

    func openFromQuickOpen(_ url: URL) {
        quickOpen = nil
        openFile(url)
        mainFocusRequest += 1
    }

    // MARK: Content search

    /// Cmd+E: searches the contents of the files under the active terminal's working
    /// directory. Starts with the text selected in the editor, if any.
    func toggleContentSearch() {
        if contentSearch != nil {
            dismissContentSearch()
        } else if let root = activeSession?.currentDirectory() {
            quickOpen = nil
            contentSearch = ContentSearchModel(root: root, query: selectedEditorText())
        }
    }

    func dismissContentSearch() {
        contentSearch = nil
        mainFocusRequest += 1
    }

    /// Opens the file of a found line and selects the match in it.
    func openFromContentSearch(_ match: ContentMatch, in model: ContentSearchModel) {
        contentSearch = nil
        openFile(model.url(of: match))
        if let document = activeDocument, document.url == model.url(of: match).standardizedFileURL {
            document.reveal(line: match.line, column: match.column, length: match.length)
        }
        mainFocusRequest += 1
    }

    /// The editor's selection when it is a single, non-empty line.
    private func selectedEditorText() -> String? {
        guard let textView = activeDocument?.controller.textView,
              let range = textView.selectionManager.textSelections.first?.range,
              range.length > 0, range.length <= 200 else { return nil }
        let text = (textView.string as NSString).substring(with: range)
        return text.contains(where: \.isNewline) ? nil : text
    }

    // MARK: Editor

    var isEditorVisible: Bool {
        activeSession?.editor.isVisible == true
    }

    var activeDocument: EditorDocument? {
        guard let session = activeSession, session.review == nil, session.editor.isVisible else { return nil }
        let editor = session.editor
        return editor.activeDocument
    }

    func openFile(_ url: URL) {
        guard let editor = activeSession?.editor else { return }
        hideReview()
        do {
            try editor.open(url)
            checkActiveDocumentOnDisk()
        } catch {
            Alerts.show(error)
        }
    }

    /// Cmd+N: a new, empty file in the editor. Where it goes is asked on the first save.
    func newDocument() {
        guard let editor = activeSession?.editor else { return }
        hideReview()
        editor.newDocument()
        mainFocusRequest += 1
    }

    func selectDocument(_ document: EditorDocument) {
        activeSession?.editor.activeDocumentID = document.id
        checkActiveDocumentOnDisk()
    }

    func showTerminal() {
        guard let editor = activeSession?.editor, editor.isVisible else { return }
        editor.isVisible = false
        mainFocusRequest += 1
    }

    /// Switches between the terminal and the editor of the active session.
    func toggleEditor() {
        guard let editor = activeSession?.editor else { return }
        if activeSession?.review != nil {
            hideReview()
        } else if editor.isVisible {
            showTerminal()
        } else if editor.activeDocument != nil {
            editor.isVisible = true
            checkActiveDocumentOnDisk()
        }
    }

    func saveActiveDocument() {
        guard let document = activeDocument else { return }
        save(document)
    }

    func closeDocument(_ document: EditorDocument) {
        guard let editor = activeSession?.editor else { return }
        if document.isDirty {
            switch Alerts.askToSave([document]) {
            case .save: guard save(document) else { return }
            case .discard: break
            case .cancel: return
            }
        }
        editor.close(document)
        if !editor.isVisible { mainFocusRequest += 1 }
    }

    /// Cmd+W: closes review mode or the open file when shown, otherwise the terminal.
    func closeActiveItem() {
        if activeSession?.review != nil {
            hideReview()
        } else if let document = activeDocument {
            closeDocument(document)
        } else {
            closeActiveSession()
        }
    }

    @discardableResult
    private func save(_ document: EditorDocument) -> Bool {
        do {
            if document.url == nil {
                guard let url = askWhereToSave(document) else { return false }
                try document.save(to: url)
            } else {
                try document.save()
            }
            return true
        } catch {
            Alerts.show(error)
            return false
        }
    }

    /// Save panel for a new file, starting in the active terminal's working directory.
    private func askWhereToSave(_ document: EditorDocument) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = document.name
        panel.directoryURL = activeSession?.currentDirectory()
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Asks before discarding unsaved files. Returns false when the user cancels.
    private func resolveUnsavedDocuments(in session: TerminalSession) -> Bool {
        let dirty = session.editor.documents.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        switch Alerts.askToSave(dirty) {
        case .save: return dirty.allSatisfy { save($0) }
        case .discard: return true
        case .cancel: return false
        }
    }

    /// Asks about unsaved files in every terminal, e.g. before quitting.
    func resolveAllUnsavedDocuments() -> Bool {
        sessions.allSatisfy { resolveUnsavedDocuments(in: $0) }
    }

    /// Reloads the visible file if it changed on disk, asking first when it has unsaved edits.
    private func checkActiveDocumentOnDisk() {
        guard let document = activeDocument, document.changedOnDisk else { return }
        if document.isDirty {
            let choice = Alerts.ask(
                "“\(document.name)” changed on disk.",
                info: "Do you want to reload it and lose your unsaved changes?",
                buttons: ["Keep My Version", "Reload"]
            )
            guard choice == 1 else {
                document.ignoreDiskChange()
                return
            }
        }
        do {
            try document.reload()
        } catch {
            Alerts.show(error)
        }
    }

    /// Hands keyboard focus back to whatever fills the main area.
    func requestMainFocus() {
        mainFocusRequest += 1
    }

    // MARK: Sessions

    /// Opens a new terminal in the working directory of the active one.
    func newSession() {
        let directory = activeSession?.currentDirectory()
        let session = TerminalSession(startDirectory: directory)
        session.onExit = { [weak self] session in
            // The shell is already gone; unsaved files can still be saved.
            _ = self?.resolveUnsavedDocuments(in: session)
            self?.remove(session)
        }
        sessions.append(session)
        activeSessionID = session.id
    }

    /// Names a terminal in the list. An empty name goes back to the title set by the shell.
    func rename(_ session: TerminalSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        session.customTitle = trimmed.isEmpty ? nil : trimmed
    }

    func closeActiveSession() {
        guard let session = activeSession else { return }
        close(session)
    }

    func close(_ session: TerminalSession) {
        guard resolveUnsavedDocuments(in: session) else { return }
        session.terminate()
        remove(session)
    }

    /// Cmd+1…8 pick the terminal at that position, Cmd+9 always picks the last one.
    func selectSession(shortcut number: Int) {
        guard !sessions.isEmpty else { return }
        if number == 9 {
            activeSessionID = sessions.last?.id
        } else if number - 1 < sessions.count {
            activeSessionID = sessions[number - 1].id
        }
    }

    /// Reorders terminals dragged in the list; their shortcuts follow the new positions.
    func moveSessions(fromOffsets source: IndexSet, toOffset destination: Int) {
        sessions.move(fromOffsets: source, toOffset: destination)
    }

    func selectAdjacentSession(offset: Int) {
        guard let index = activeIndex, !sessions.isEmpty else { return }
        let next = (index + offset + sessions.count) % sessions.count
        activeSessionID = sessions[next].id
    }

    /// The shortcut shown next to a terminal in the list, matching `selectSession(shortcut:)`.
    func shortcutNumber(for session: TerminalSession) -> Int? {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return nil }
        if index < 8 { return index + 1 }
        return index == sessions.count - 1 ? 9 : nil
    }

    private var activeIndex: Int? {
        sessions.firstIndex { $0.id == activeSessionID }
    }

    private func remove(_ session: TerminalSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions.remove(at: index)

        if sessions.isEmpty {
            NSApp.terminate(nil)
        } else if activeSessionID == session.id {
            activeSessionID = sessions[min(index, sessions.count - 1)].id
        }
    }
}
