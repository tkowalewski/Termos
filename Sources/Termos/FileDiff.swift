import Foundation

/// One file's diff as printed by `git diff`, split into hunks, and partial patches built from it.
struct FileDiff {
    enum LineKind { case context, added, removed, noNewline }

    struct Line {
        let kind: LineKind
        /// Without the leading sign.
        let text: String
        let oldNumber: Int?
        let newNumber: Int?

        var isChange: Bool { kind == .added || kind == .removed }
    }

    struct Hunk {
        let oldStart: Int
        let newStart: Int
        /// The whole `@@` line, as shown above the hunk.
        let header: String
        var lines: [Line] = []

        /// Parses `@@ -oldStart,oldCount +newStart,newCount @@ heading`.
        init?(header line: String) {
            guard line.hasPrefix("@@ -") else { return nil }
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4, parts[3].hasPrefix("@@"),
                  let old = Self.start(of: parts[1], sign: "-"),
                  let new = Self.start(of: parts[2], sign: "+") else { return nil }
            oldStart = old
            newStart = new
            header = line
        }

        private static func start(of range: Substring, sign: Character) -> Int? {
            guard range.first == sign else { return nil }
            return Int(range.dropFirst().prefix { $0 != "," })
        }
    }

    /// Picks one line: its hunk and its position in the hunk.
    struct LineID: Hashable {
        let hunk: Int
        let line: Int
    }

    /// The lines before the first hunk: `diff --git`, modes, `---` and `+++`.
    let header: [String]
    let hunks: [Hunk]
    let isBinary: Bool

    var isNewFile: Bool { header.contains { $0.hasPrefix("new file mode") } }
    var isDeletedFile: Bool { header.contains { $0.hasPrefix("deleted file mode") } }
    var isModeChange: Bool { header.contains { $0.hasPrefix("old mode") } }

    /// Whether single lines can be staged, unstaged or discarded. Deleted files only
    /// go as a whole: half a deletion would need the file back first.
    var allowsLineSelection: Bool {
        !isBinary && !isDeletedFile && !hunks.isEmpty
    }

    init(parsing text: String) {
        var header: [String] = []
        var hunks: [Hunk] = []
        var isBinary = false
        var oldNumber = 0
        var newNumber = 0

        // Split by bytes: as Characters, a Windows "\r\n" is one and never equals "\n".
        for rawLine in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            let line = String(decoding: rawLine, as: UTF8.self)
            if let hunk = Hunk(header: line) {
                hunks.append(hunk)
                oldNumber = hunk.oldStart
                newNumber = hunk.newStart
                continue
            }
            guard !hunks.isEmpty else {
                if line.hasPrefix("Binary files ") || line == "GIT binary patch" { isBinary = true }
                if !line.isEmpty { header.append(line) }
                continue
            }

            // The sign is one scalar; a combining mark after it would join it into one Character.
            let text = String(line.unicodeScalars.dropFirst())
            let parsed: Line
            switch line.unicodeScalars.first {
            case " ":
                parsed = Line(kind: .context, text: text, oldNumber: oldNumber, newNumber: newNumber)
                oldNumber += 1
                newNumber += 1
            case "-":
                parsed = Line(kind: .removed, text: text, oldNumber: oldNumber, newNumber: nil)
                oldNumber += 1
            case "+":
                parsed = Line(kind: .added, text: text, oldNumber: nil, newNumber: newNumber)
                newNumber += 1
            case "\\":
                parsed = Line(kind: .noNewline, text: text, oldNumber: nil, newNumber: nil)
            default:
                continue
            }
            hunks[hunks.count - 1].lines.append(parsed)
        }

        self.header = header
        self.hunks = hunks
        self.isBinary = isBinary
    }

    var changedLineIDs: [LineID] {
        hunks.indices.flatMap { hunk in
            hunks[hunk].lines.indices
                .filter { hunks[hunk].lines[$0].isChange }
                .map { LineID(hunk: hunk, line: $0) }
        }
    }

    /// A patch for `git apply` with only the selected lines.
    ///
    /// A forward patch applies to the old side (staging into the index). A reverse one
    /// is applied with `--reverse` to the new side, to unstage or discard. Either way
    /// the unselected changes stay as they are in the file the patch applies to.
    /// Line counts are left for `git apply --recount`.
    func patch(selecting selected: Set<LineID>, reverse: Bool) -> String? {
        var body: [String] = []
        var everythingSelected = true
        // How far the other side's line numbers have moved because of earlier hunks.
        var shift = 0

        for (hunkIndex, hunk) in hunks.enumerated() {
            var lines: [String] = []
            var hasSelection = false
            var oldCount = 0
            var newCount = 0
            // A "\ No newline" marker belongs to the line before it.
            var keptPrevious = false

            for (lineIndex, line) in hunk.lines.enumerated() {
                let isSelected = selected.contains(LineID(hunk: hunkIndex, line: lineIndex))
                if line.isChange {
                    if isSelected { hasSelection = true } else { everythingSelected = false }
                }

                let sign: String?
                switch line.kind {
                case .context:
                    sign = " "
                case .removed:
                    sign = isSelected ? "-" : (reverse ? nil : " ")
                case .added:
                    sign = isSelected ? "+" : (reverse ? " " : nil)
                case .noNewline:
                    if keptPrevious { lines.append("\\" + line.text) }
                    continue
                }

                keptPrevious = sign != nil
                guard let sign else { continue }
                lines.append(sign + line.text)
                if sign != "+" { oldCount += 1 }
                if sign != "-" { newCount += 1 }
            }

            guard hasSelection else { continue }
            // An empty side starts at the line before the hunk, as in `@@ -0,0 +1,3 @@`.
            let oldStart = reverse
                ? hunk.newStart + shift + (newCount == 0 ? 1 : 0) - (oldCount == 0 ? 1 : 0)
                : hunk.oldStart
            let newStart = reverse
                ? hunk.newStart
                : hunk.oldStart + shift + (oldCount == 0 ? 1 : 0) - (newCount == 0 ? 1 : 0)
            shift += reverse ? oldCount - newCount : newCount - oldCount
            body.append("@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@")
            body += lines
        }

        guard !body.isEmpty else { return nil }
        // Taking back only part of a new file leaves the file in place, so the patch
        // must modify it instead of deleting it.
        let header = isNewFile && reverse && !everythingSelected ? modificationHeader : self.header
        return (header + body).joined(separator: "\n") + "\n"
    }

    /// The header of a plain modification of the same file.
    private var modificationHeader: [String] {
        guard let target = header.first(where: { $0.hasPrefix("+++ ") }) else { return header }
        let path = target.dropFirst(4)
        let source: String
        if path.hasPrefix("\"b/") {
            source = "\"a/" + path.dropFirst(3)
        } else if path.hasPrefix("b/") {
            source = "a/" + path.dropFirst(2)
        } else {
            source = String(path)
        }
        return header.filter { $0.hasPrefix("diff --git ") } + ["--- " + source, target]
    }
}
