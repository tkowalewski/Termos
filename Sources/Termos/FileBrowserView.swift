import AppKit
import SwiftUI

/// Remembers which folders were expanded, per browser root, across hide/show.
final class FileBrowserMemory {
    var expandedPaths: [String: Set<String>] = [:]
}

/// The file tree panel showing the contents of the active terminal's working directory.
struct FileBrowserPanel: NSViewRepresentable {
    let root: URL
    let memory: FileBrowserMemory
    let onOpenFile: (URL) -> Void
    let onDismiss: () -> Void

    func makeCoordinator() -> FileBrowserController {
        FileBrowserController(memory: memory)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let controller = context.coordinator
        controller.onOpenFile = onOpenFile
        controller.onDismiss = onDismiss
        controller.setRoot(root)
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: FileBrowserController) {
        coordinator.close()
    }
}

/// Drives the NSOutlineView: lazy loading, live updates from FSEvents and keyboard actions.
final class FileBrowserController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let scrollView = NSScrollView()
    private let outlineView = FileOutlineView()
    private let memory: FileBrowserMemory
    private var root: FileNode?
    private var watcher: DirectoryWatcher?

    var onOpenFile: ((URL) -> Void)?
    var onDismiss: (() -> Void)?

    init(memory: FileBrowserMemory) {
        self.memory = memory
        super.init()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(rowClicked)
        outlineView.onActivate = { [weak self] in self?.activateSelectedRow() }
        outlineView.onCancel = { [weak self] in self?.onDismiss?() }

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
    }

    func setRoot(_ url: URL) {
        guard url.path != root?.url.path else { return }

        saveExpansion()
        let node = FileNode(url: url, isDirectory: true)
        node.reloadChildren()
        root = node
        outlineView.reloadData()
        restoreExpansion(memory.expandedPaths[url.path] ?? [])

        watcher = DirectoryWatcher(url: url) { [weak self] paths, mustRescan in
            self?.handleChanges(paths: paths, mustRescan: mustRescan)
        }
    }

    func close() {
        saveExpansion()
        watcher = nil
    }

    // MARK: Live updates

    private func handleChanges(paths: [String], mustRescan: Bool) {
        guard let root else { return }

        let directories = mustRescan
            ? root.loadedDirectories()
            : paths.compactMap { root.loadedDescendant(atPath: $0) }.filter(\.isDirectory)
        let changed = directories.filter { $0.reloadChildren() }
        guard !changed.isEmpty else { return }

        let expanded = expandedPaths()
        let selected = (outlineView.item(atRow: outlineView.selectedRow) as? FileNode)?.url
        for directory in changed {
            outlineView.reloadItem(directory === root ? nil : directory, reloadChildren: true)
        }
        restoreExpansion(expanded)
        if let selected { select(url: selected) }
    }

    // MARK: Expansion state

    private func expandedPaths() -> Set<String> {
        Set((0..<outlineView.numberOfRows).compactMap { row in
            guard let node = outlineView.item(atRow: row) as? FileNode,
                  outlineView.isItemExpanded(node) else { return nil }
            return node.url.path
        })
    }

    private func saveExpansion() {
        guard let root else { return }
        memory.expandedPaths[root.url.path] = expandedPaths()
    }

    /// Expands rows top-down; expanding a row inserts its children, which the loop then visits.
    private func restoreExpansion(_ paths: Set<String>) {
        guard !paths.isEmpty else { return }
        var row = 0
        while row < outlineView.numberOfRows {
            if let node = outlineView.item(atRow: row) as? FileNode,
               node.isDirectory, paths.contains(node.url.path), !outlineView.isItemExpanded(node) {
                outlineView.expandItem(node)
            }
            row += 1
        }
    }

    private func select(url: URL) {
        for row in 0..<outlineView.numberOfRows {
            if (outlineView.item(atRow: row) as? FileNode)?.url == url {
                outlineView.selectRowIndexes([row], byExtendingSelection: false)
                return
            }
        }
    }

    // MARK: Actions

    @objc private func rowClicked() {
        guard outlineView.clickedRow >= 0 else { return }
        activate(row: outlineView.clickedRow)
    }

    private func activateSelectedRow() {
        guard outlineView.selectedRow >= 0 else { return }
        activate(row: outlineView.selectedRow)
    }

    private func activate(row: Int) {
        guard let node = outlineView.item(atRow: row) as? FileNode else { return }
        if node.isDirectory {
            if outlineView.isItemExpanded(node) {
                outlineView.collapseItem(node)
            } else {
                outlineView.expandItem(node)
            }
        } else {
            onOpenFile?(node.url)
        }
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        node(for: item)?.loadedChildren().count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        node(for: item)!.loadedChildren()[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }

    private func node(for item: Any?) -> FileNode? {
        item == nil ? root : item as? FileNode
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let cell = outlineView.makeView(withIdentifier: FileCellView.identifier, owner: self) as? FileCellView
            ?? FileCellView()
        cell.configure(with: node)
        return cell
    }
}

/// Outline view that reports Enter (open) and Esc (dismiss), and focuses itself when shown.
final class FileOutlineView: NSOutlineView {
    var onActivate: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
            if selectedRow < 0, numberOfRows > 0 {
                selectRowIndexes([0], byExtendingSelection: false)
            }
        }
    }
}

private final class FileCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FileCell")

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier

        let icon = NSImageView()
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingMiddle
        for view in [icon, label] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        imageView = icon
        textField = label
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func configure(with node: FileNode) {
        textField?.stringValue = node.name
        imageView?.image = NSWorkspace.shared.icon(forFile: node.url.path)
        toolTip = node.url.path
    }
}
