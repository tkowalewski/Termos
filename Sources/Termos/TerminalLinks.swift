import AppKit
import SwiftTerm

/// A terminal pane that hands Cmd+clicked links to Termos instead of SwiftTerm's
/// default handler, which opens everything with the system's default app and
/// resolves relative paths against the app's directory instead of the shell's.
final class TermosTerminalView: LocalProcessTerminalView {
    /// Called with the text of a Cmd+clicked link: a URL, or a path that may end in ":line" or ":line:column".
    var onOpenLink: ((TermosTerminalView, String) -> Void)?

    override func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let onOpenLink {
            onOpenLink(self, link)
        } else {
            super.requestOpenLink(source: source, link: link, params: params)
        }
    }
}

/// An existing file or directory named in terminal output, such as
/// `Sources/App.swift:12:5` from a compiler, `rg -n` or a stack trace.
struct TerminalFileLink {
    let url: URL
    /// 1-based line and column, when the link names them.
    let line: Int?
    let column: Int?

    private static let location = try! NSRegularExpression(pattern: #":([0-9]+)(?::([0-9]+))?$"#)

    /// Resolves `text` against `directory` (the pane's working directory). Nil when
    /// it is a non-file URL or names nothing that exists.
    init?(_ text: String, relativeTo directory: URL?) {
        var path = text
        if let url = URL(string: text), let scheme = url.scheme {
            guard scheme == "file" else { return nil }
            path = url.path
        }

        // The whole text first, in case the file name itself contains a colon.
        var candidates: [(path: String, line: Int?, column: Int?)] = [(path, nil, nil)]
        let ns = path as NSString
        if let match = Self.location.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) {
            let number = { (index: Int) -> Int? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : Int(ns.substring(with: range))
            }
            candidates.append((ns.substring(to: match.range.location), number(1), number(2)))
        }

        for candidate in candidates {
            if let url = Self.existingURL(for: candidate.path, relativeTo: directory) {
                self.url = url
                line = candidate.line
                column = candidate.column
                return
            }
        }
        return nil
    }

    private static func existingURL(for path: String, relativeTo directory: URL?) -> URL? {
        guard !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return exists(URL(fileURLWithPath: expanded))
        }
        guard let directory else { return nil }
        if let url = exists(directory.appendingPathComponent(expanded)) {
            return url
        }
        // `git diff` prints paths as "a/Sources/App.swift" and "b/Sources/App.swift".
        if expanded.hasPrefix("a/") || expanded.hasPrefix("b/") {
            return exists(directory.appendingPathComponent(String(expanded.dropFirst(2))))
        }
        return nil
    }

    private static func exists(_ url: URL) -> URL? {
        let url = url.standardizedFileURL
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    var isDirectory: Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
