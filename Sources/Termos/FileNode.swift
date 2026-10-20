import Foundation

/// A file or directory in the file browser. Directory contents load lazily.
final class FileNode {
    /// Names never shown in the browser (configurable later).
    static let ignoredNames: Set<String> = [".git", ".DS_Store", "node_modules"]

    let url: URL
    let isDirectory: Bool

    /// `nil` until the directory is first expanded.
    private(set) var children: [FileNode]?

    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.isDirectory = isDirectory
    }

    func loadedChildren() -> [FileNode] {
        if children == nil { reloadChildren() }
        return children ?? []
    }

    /// Re-reads the directory, reusing nodes for entries that still exist so their
    /// own loaded children survive. Returns whether the list of entries changed.
    @discardableResult
    func reloadChildren() -> Bool {
        guard isDirectory else { return false }

        let existing = Dictionary((children ?? []).map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: keys, options: []
        )) ?? []

        let nodes = entries
            .filter { !Self.ignoredNames.contains($0.lastPathComponent) }
            .map { entry -> FileNode in
                let directory = Self.isDirectory(entry)
                if let node = existing[entry.lastPathComponent], node.isDirectory == directory {
                    return node
                }
                return FileNode(url: entry, isDirectory: directory)
            }
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }

        let changed = children.map { $0.map(\.name) != nodes.map(\.name) } ?? true
        children = nodes
        return changed
    }

    /// Finds an already loaded descendant directory by its path.
    func loadedDescendant(atPath path: String) -> FileNode? {
        if url.path == path { return self }
        let prefix = url.path.hasSuffix("/") ? url.path : url.path + "/"
        guard path.hasPrefix(prefix) else { return nil }

        var node = self
        for component in path.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children?.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    /// Every directory whose contents are currently loaded, including this one.
    func loadedDirectories() -> [FileNode] {
        guard let children else { return [] }
        return [self] + children.flatMap { $0.loadedDirectories() }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            // Show symlinked directories as directories, like Finder does.
            return (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
        return values?.isDirectory ?? false
    }
}
