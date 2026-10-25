import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The list of changed files shown in place of the file browser in review mode.
struct ReviewChangesPanel: View {
    let model: ReviewModel
    let onOpenFile: (URL) -> Void
    let onDismiss: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectionID) {
            if !model.staged.isEmpty {
                Section {
                    ForEach(model.staged) { ReviewChangeRow(change: $0) }
                } header: {
                    ReviewSectionHeader(title: "Staged Changes", count: model.staged.count,
                                        symbol: "minus", help: "Unstage All", action: model.unstageAll)
                }
            }
            if !model.unstaged.isEmpty {
                Section {
                    ForEach(model.unstaged) { ReviewChangeRow(change: $0) }
                } header: {
                    ReviewSectionHeader(title: "Changes", count: model.unstaged.count,
                                        symbol: "plus", help: "Stage All", action: model.stageAll)
                }
            }
        }
        .listStyle(.sidebar)
        .focused($isFocused)
        .contextMenu(forSelectionType: GitChange.ID.self) { ids in
            if let change = change(for: ids) { menu(for: change) }
        } primaryAction: { ids in
            if let change = change(for: ids) { open(change) }
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .overlay {
            if model.isLoaded, model.changes.isEmpty {
                Text(model.problem ?? "No changes")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .onAppear { isFocused = true }
    }

    private func change(for ids: Set<GitChange.ID>) -> GitChange? {
        guard let id = ids.first else { return nil }
        return model.changes.first { $0.id == id }
    }

    @ViewBuilder
    private func menu(for change: GitChange) -> some View {
        switch change.area {
        case .staged:
            Button("Unstage File") { model.unstage(change) }
        case .unstaged:
            Button("Stage File") { model.stage(change) }
            if !change.isConflict {
                Button("Discard Changes…") { model.discard(change) }
            }
        }
        if !change.isDeleted {
            Divider()
            Button("Open in Editor") { open(change) }
        }
    }

    private func open(_ change: GitChange) {
        guard !change.isDeleted, let url = model.url(of: change) else { return }
        onOpenFile(url)
    }
}

private struct ReviewSectionHeader: View {
    let title: String
    let count: Int
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Text("\(count)")
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Button(action: action) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help(help)
        }
    }
}

private struct ReviewChangeRow: View {
    let change: GitChange

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: (change.path as NSString).pathExtension) ?? .data))
                .resizable()
                .frame(width: 16, height: 16)
            Text(change.name)
                .lineLimit(1)
                .strikethrough(change.isDeleted)
                .layoutPriority(1)
            Text(change.folder)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 4)
            Text(ReviewStatus.label(change))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(ReviewStatus.color(change))
        }
        .help(change.originalPath.map { "\($0) → \(change.path)" } ?? change.path)
    }
}

/// Status letters as in VS Code: untracked files are U, merge conflicts !.
enum ReviewStatus {
    static func label(_ change: GitChange) -> String {
        switch change.status {
        case "?": "U"
        case "U": "!"
        default: String(change.status)
        }
    }

    static func color(_ change: GitChange) -> Color {
        switch change.status {
        case "?", "A": .green
        case "D", "U": .red
        case "R", "C": .blue
        default: .orange
        }
    }
}

/// The diff of the file selected in review mode, in place of the terminal or editor.
struct ReviewDiffView: View {
    let model: ReviewModel
    let onOpenFile: (URL) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let change = model.selectedChange {
                if let shown = model.diff, shown.change.id == change.id {
                    if let file = shown.file, shown.notice == nil {
                        DiffTableView(
                            shown: shown,
                            allowsLineActions: file.allowsLineSelection,
                            onAction: { model.apply($0, to: $1) },
                            onOpenFile: { open(change) },
                            onEscape: onDismiss
                        )
                    } else {
                        placeholder(shown.notice ?? "")
                    }
                } else {
                    Spacer()
                }
                Divider()
                ReviewStatusBar(change: change, model: model)
            } else if model.isLoaded {
                placeholder(model.problem ?? (model.changes.isEmpty ? "No changes" : "Select a file to see its changes"))
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func open(_ change: GitChange) {
        guard !change.isDeleted, let url = model.url(of: change) else { return }
        onOpenFile(url)
    }
}

/// The path of the shown file and the actions for the whole file, like the editor's status bar.
private struct ReviewStatusBar: View {
    let change: GitChange
    let model: ReviewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: (change.path as NSString).pathExtension) ?? .data))
                .resizable()
                .frame(width: 14, height: 14)
            Text(change.originalPath.map { "\($0) → \(change.path)" } ?? change.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text(change.area == .staged ? "Staged" : "Changes")
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            switch change.area {
            case .staged:
                Button("Unstage File") { model.unstage(change) }
            case .unstaged:
                if !change.isConflict {
                    Button("Discard File…") { model.discard(change) }
                }
                Button("Stage File") { model.stage(change) }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(SidebarMaterial())
    }
}

// MARK: Diff table

/// The lines of a diff in a table: click, Shift-click or drag to select lines,
/// click a hunk header to select the whole hunk, right-click for actions.
private struct DiffTableView: NSViewRepresentable {
    let shown: ShownDiff
    let allowsLineActions: Bool
    let onAction: (ReviewModel.LineAction, Set<FileDiff.LineID>) -> Void
    let onOpenFile: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> DiffTableController {
        DiffTableController()
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.allowsLineActions = allowsLineActions
        controller.onAction = onAction
        controller.onOpenFile = onOpenFile
        controller.onEscape = onEscape
        controller.show(shown)
    }
}

final class DiffTableController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    enum Row {
        case hunk(Int)
        case line(FileDiff.LineID)
    }

    let scrollView = DiffScrollView()
    private let tableView = DiffTable()
    private let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("diff"))
    private var file: FileDiff?
    private var area: GitChange.Area = .unstaged
    private var shownID: GitChange.ID?
    private var shownText: String?
    private var rows: [Row] = []
    private var layout = DiffLayout(maxLineNumber: 0)
    private var contentWidth: CGFloat = 0

    var allowsLineActions = true
    var onAction: ((ReviewModel.LineAction, Set<FileDiff.LineID>) -> Void)?
    var onOpenFile: (() -> Void)?
    var onEscape: (() -> Void)?

    override init() {
        super.init()
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.backgroundColor = .textBackgroundColor
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menuProvider = { [weak self] row in self?.menu(forClickedRow: row) }
        tableView.onCancel = { [weak self] in self?.onEscape?() }

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.onLayout = { [weak self] in self?.updateColumnWidth() }
    }

    func show(_ shown: ShownDiff) {
        guard shown.change.id != shownID || shown.text != shownText else { return }
        let isSameFile = shown.change.id == shownID
        shownID = shown.change.id
        shownText = shown.text
        area = shown.change.area
        file = shown.file

        rows = []
        var maxLineNumber = 0
        var maxLength = 0
        for (hunkIndex, hunk) in (shown.file?.hunks ?? []).enumerated() {
            rows.append(.hunk(hunkIndex))
            maxLength = max(maxLength, hunk.header.count)
            for (lineIndex, line) in hunk.lines.enumerated() {
                rows.append(.line(FileDiff.LineID(hunk: hunkIndex, line: lineIndex)))
                maxLineNumber = max(maxLineNumber, line.oldNumber ?? 0, line.newNumber ?? 0)
                maxLength = max(maxLength, DiffLayout.displayText(line.text).count)
            }
        }
        layout = DiffLayout(maxLineNumber: maxLineNumber)
        contentWidth = layout.textX + CGFloat(maxLength) * layout.characterWidth + 20

        tableView.reloadData()
        updateColumnWidth()
        // After staging some lines the same file comes back changed: stay where the user was.
        if !isSameFile { tableView.scrollRowToVisible(0) }
    }

    private func updateColumnWidth() {
        let width = max(contentWidth, scrollView.contentView.bounds.width)
        if abs(column.width - width) > 0.5 { column.width = width }
    }

    // MARK: Selection

    private func hunkIndex(ofRow row: Int) -> Int {
        switch rows[row] {
        case .hunk(let index): index
        case .line(let id): id.hunk
        }
    }

    private func rowIndexes(ofHunk hunk: Int) -> IndexSet {
        IndexSet(rows.indices.filter { hunkIndex(ofRow: $0) == hunk })
    }

    /// The changed lines among the selected rows; context lines don't count.
    private func lineIDs(in rowIndexes: IndexSet) -> Set<FileDiff.LineID> {
        guard let file else { return [] }
        return Set(rowIndexes.compactMap { row in
            guard case .line(let id) = rows[row], file.hunks[id.hunk].lines[id.line].isChange else { return nil }
            return id
        })
    }

    func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
        var indexes = proposed
        for row in proposed {
            if case .hunk(let hunk) = rows[row] { indexes.formUnion(rowIndexes(ofHunk: hunk)) }
        }
        return indexes
    }

    // MARK: Menu

    /// Right-clicking outside the selection selects the clicked row first, like in Finder.
    private func menu(forClickedRow row: Int) -> NSMenu? {
        guard row >= 0, row < rows.count else { return nil }
        if !tableView.selectedRowIndexes.contains(row) {
            let indexes = tableView(tableView, selectionIndexesForProposedSelection: IndexSet(integer: row))
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        }

        let selected = lineIDs(in: tableView.selectedRowIndexes)
        let hunk = lineIDs(in: rowIndexes(ofHunk: hunkIndex(ofRow: row)))
        let menu = NSMenu()
        menu.autoenablesItems = false

        if allowsLineActions {
            switch area {
            case .staged:
                addItem(to: menu, "Unstage Selected Lines", lines: selected, action: .unstage)
                addItem(to: menu, "Unstage Hunk", lines: hunk, action: .unstage)
            case .unstaged:
                addItem(to: menu, "Stage Selected Lines", lines: selected, action: .stage)
                addItem(to: menu, "Stage Hunk", lines: hunk, action: .stage)
                menu.addItem(.separator())
                addItem(to: menu, "Discard Selected Lines…", lines: selected, action: .discard)
                addItem(to: menu, "Discard Hunk…", lines: hunk, action: .discard)
            }
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: "Open in Editor") { [weak self] in self?.onOpenFile?() })
        return menu
    }

    private func addItem(to menu: NSMenu, _ title: String, lines: Set<FileDiff.LineID>, action: ReviewModel.LineAction) {
        let item = ClosureMenuItem(title: title) { [weak self] in self?.onAction?(action, lines) }
        item.isEnabled = !lines.isEmpty
        menu.addItem(item)
    }

    // MARK: NSTableViewDataSource, NSTableViewDelegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .hunk = rows[row] { return DiffLayout.hunkHeight }
        return DiffLayout.lineHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        nil
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let file else { return nil }
        let view = tableView.makeView(withIdentifier: DiffRowView.identifier, owner: self) as? DiffRowView
            ?? DiffRowView()
        switch rows[row] {
        case .hunk(let index):
            view.content = .hunk(file.hunks[index].header)
        case .line(let id):
            view.content = .line(file.hunks[id.hunk].lines[id.line])
        }
        view.layout = layout
        view.needsDisplay = true
        return view
    }
}

/// Column positions of the diff: old and new line numbers, the sign, then the text.
struct DiffLayout {
    static let font = EditorAppearance.font
    static let lineHeight: CGFloat = 18
    static let hunkHeight: CGFloat = 24

    let characterWidth: CGFloat
    let numberWidth: CGFloat

    init(maxLineNumber: Int) {
        characterWidth = ("0" as NSString).size(withAttributes: [.font: Self.font]).width
        numberWidth = CGFloat(max(String(maxLineNumber).count, 3)) * characterWidth + 12
    }

    var signX: CGFloat { numberWidth * 2 + 6 }
    var textX: CGFloat { signX + characterWidth * 2 }

    /// Tabs as spaces, and no carriage return of Windows line endings.
    static func displayText(_ text: String) -> String {
        var text = text
        if text.hasSuffix("\r") { text.removeLast() }
        return text.replacingOccurrences(of: "\t", with: "    ")
    }
}

/// Draws one row of the diff itself; the table has no cell views.
private final class DiffRowView: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("DiffRow")

    enum Content {
        case hunk(String)
        case line(FileDiff.Line)
    }

    var content: Content = .hunk("")
    var layout = DiffLayout(maxLineNumber: 0)

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func drawBackground(in dirtyRect: NSRect) {
        let color: NSColor = switch content {
        case .hunk: .secondaryLabelColor.withAlphaComponent(0.08)
        case .line(let line) where line.kind == .added: .systemGreen.withAlphaComponent(0.14)
        case .line(let line) where line.kind == .removed: .systemRed.withAlphaComponent(0.14)
        case .line: .textBackgroundColor
        }
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
        color.setFill()
        dirtyRect.fill(using: .sourceOver)
    }

    /// Translucent, so the green and red of the lines still show through.
    override func drawSelection(in dirtyRect: NSRect) {
        let color: NSColor = isEmphasized
            ? .selectedContentBackgroundColor.withAlphaComponent(0.35)
            : .unemphasizedSelectedContentBackgroundColor.withAlphaComponent(0.8)
        color.setFill()
        bounds.fill(using: .sourceOver)
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let font = DiffLayout.font
        let y = (bounds.height - (font.ascender - font.descender)) / 2

        switch content {
        case .hunk(let header):
            draw(header, x: 8, y: y, color: .secondaryLabelColor)
        case .line(let line):
            if line.kind == .noNewline {
                draw(line.text.trimmingCharacters(in: .whitespaces), x: layout.textX, y: y, color: .tertiaryLabelColor)
                return
            }
            let numberColor = NSColor.secondaryLabelColor
            if let number = line.oldNumber { drawNumber(number, columnX: 0, y: y, color: numberColor) }
            if let number = line.newNumber { drawNumber(number, columnX: layout.numberWidth, y: y, color: numberColor) }
            switch line.kind {
            case .added: draw("+", x: layout.signX, y: y, color: .systemGreen)
            case .removed: draw("-", x: layout.signX, y: y, color: .systemRed)
            default: break
            }
            draw(DiffLayout.displayText(line.text), x: layout.textX, y: y, color: .labelColor)
        }
    }

    private func drawNumber(_ number: Int, columnX: CGFloat, y: CGFloat, color: NSColor) {
        let text = String(number)
        let x = columnX + layout.numberWidth - 6 - CGFloat(text.count) * layout.characterWidth
        draw(text, x: x, y: y, color: color)
    }

    private func draw(_ text: String, x: CGFloat, y: CGFloat, color: NSColor) {
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: DiffLayout.font, .foregroundColor: color])
    }

    override var isFlipped: Bool { true }
}

/// Table that builds its context menu for the clicked row and reports Esc.
final class DiffTable: NSTableView {
    var menuProvider: ((Int) -> NSMenu?)?
    var onCancel: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        return menuProvider?(row)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Scroll view that reports layout passes, so the table can stay as wide as the view.
final class DiffScrollView: NSScrollView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// A menu item that runs a closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func run() {
        handler()
    }
}
