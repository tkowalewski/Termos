import Foundation

/// Lists the files under a directory for quick open.
enum FileIndex {
    static let limit = 100_000

    /// Relative paths of the files under `root`. Uses `git ls-files` inside a repository
    /// (which honours .gitignore) and a directory walk elsewhere.
    static func files(in root: URL) -> [String] {
        let files = gitFiles(in: root) ?? walk(root)
        return Array(files.prefix(limit))
    }

    private static func gitFiles(in root: URL) -> [String]? {
        let git = URL(fileURLWithPath: "/usr/bin/git")
        guard FileManager.default.isExecutableFile(atPath: git.path) else { return nil }

        let process = Process()
        process.executableURL = git
        process.arguments = ["-C", root.path, "ls-files", "--cached", "--others", "--exclude-standard", "-z"]
        process.environment = ["GIT_OPTIONAL_LOCKS": "0"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        // ls-files lists tracked files that may already be deleted; checking each one
        // would be slow on big repositories, so they are filtered when opened instead.
        return data.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
    }

    private static func walk(_ root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ) else { return [] }

        let prefixLength = root.standardizedFileURL.path.count + 1
        var files: [String] = []
        for case let url as URL in enumerator {
            if FileNode.ignoredNames.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDirectory {
                files.append(String(url.standardizedFileURL.path.dropFirst(prefixLength)))
                if files.count >= limit { break }
            }
        }
        return files
    }
}
