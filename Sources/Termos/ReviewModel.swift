import AppKit
import Observation

/// A changed file in the review list: either its staged or its unstaged changes.
struct GitChange: Identifiable, Hashable {
    enum Area: Hashable { case staged, unstaged }

    struct ID: Hashable {
        let area: Area
        let path: String
    }

    let area: Area
    /// Relative to the repository root.
    let path: String
    /// The old path of a staged rename or copy.
    let originalPath: String?
    /// The letter from `git status`: M, A, D, R, C, T, ? (untracked) or U (merge conflict).
    let status: Character

    var id: ID { ID(area: area, path: path) }
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var isUntracked: Bool { status == "?" }
    var isConflict: Bool { status == "U" }
    var isDeleted: Bool { status == "D" }
}

/// The selected file's diff, or why it can't be shown.
struct ShownDiff {
    let change: GitChange
    /// The output of `git diff`; a changed text means the table must reload.
    let text: String
    let file: FileDiff?
    let notice: String?
}

/// Review mode (Cmd+R): the git changes of the active terminal's repository, with
/// staging, unstaging and discarding of whole files or selected lines.
@MainActor
@Observable
final class ReviewModel {
    enum LineAction { case stage, unstage, discard }

    /// The terminal's working directory the review was opened in.
    let directory: URL
    private(set) var root: URL?
    /// Set when there is nothing to review, e.g. outside a repository.
    private(set) var problem: String?
    private(set) var isLoaded = false
    private(set) var staged: [GitChange] = []
    private(set) var unstaged: [GitChange] = []
    private(set) var diff: ShownDiff?

    var selectionID: GitChange.ID? {
        didSet {
            if selectionID != oldValue { loadDiff() }
        }
    }

    var selectedChange: GitChange? {
        guard let selectionID else { return nil }
        return changes.first { $0.id == selectionID }
    }

    var changes: [GitChange] { staged + unstaged }

    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var diffGeneration = 0
    /// Selected once the first status is in, if the file is still changed.
    @ObservationIgnored private let initialSelection: GitChange.ID?

    init(directory: URL, initialSelection: GitChange.ID? = nil) {
        self.directory = directory
        self.initialSelection = initialSelection
        Task { await start() }
    }

    func url(of change: GitChange) -> URL? {
        root?.appendingPathComponent(change.path)
    }

    private func start() async {
        do {
            let output = try await Git.output(["rev-parse", "--show-toplevel"], in: directory)
            let path = String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let root = URL(fileURLWithPath: path, isDirectory: true)
            self.root = root
            // The index and HEAD live in .git, so staging from the terminal shows up as well.
            watcher = DirectoryWatcher(url: root) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            refresh()
        } catch {
            problem = error is Git.Failure && FileManager.default.isExecutableFile(atPath: Git.executable.path)
                ? "Not a git repository"
                : error.localizedDescription
            isLoaded = true
        }
    }

    // MARK: Status

    /// Reloads the list of changes and the shown diff. Calls while a refresh runs are
    /// folded into one more refresh after it.
    func refresh() {
        guard let root else { return }
        guard !isRefreshing else {
            needsRefresh = true
            return
        }
        isRefreshing = true
        Task {
            do {
                let output = try await Git.output(
                    ["status", "--porcelain=v1", "-z", "--untracked-files=all"], in: root
                )
                update(with: Self.parseStatus(output))
            } catch {
                problem = error.localizedDescription
            }
            isLoaded = true
            isRefreshing = false
            if needsRefresh {
                needsRefresh = false
                refresh()
            }
        }
    }

    private func update(with changes: [GitChange]) {
        let previous = self.changes.map(\.id)
        let previousSelection = selectionID
        staged = changes.filter { $0.area == .staged }
        unstaged = changes.filter { $0.area == .unstaged }
        problem = nil

        let current = self.changes
        if let id = selectionID, !current.contains(where: { $0.id == id }) {
            // Staged or unstaged as a whole: follow the file to the other list.
            if let moved = current.first(where: { $0.path == id.path }) {
                selectionID = moved.id
            } else if let index = previous.firstIndex(of: id), !current.isEmpty {
                selectionID = current[min(index, current.count - 1)].id
            } else {
                selectionID = nil
            }
        } else if selectionID == nil, !isLoaded {
            let initial = current.first { $0.id == initialSelection }
                ?? current.first { $0.path == initialSelection?.path }
            selectionID = (initial ?? current.first)?.id
        }
        // The file may have changed even when the selection did not.
        if selectionID == previousSelection { loadDiff() }
    }

    /// Parses `git status --porcelain=v1 -z`: "XY path", followed by the old path for
    /// renames and copies. X is the index, Y the working tree.
    private nonisolated static func parseStatus(_ output: Data) -> [GitChange] {
        let fields = output.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
        var changes: [GitChange] = []
        var index = 0
        while index < fields.count {
            let field = fields[index]
            index += 1
            guard field.count > 3 else { continue }
            let x = field[field.startIndex]
            let y = field[field.index(after: field.startIndex)]
            let path = String(field.dropFirst(3))
            var originalPath: String?
            if x == "R" || x == "C", index < fields.count {
                originalPath = fields[index]
                index += 1
            }

            switch (x, y) {
            case ("?", "?"):
                changes.append(GitChange(area: .unstaged, path: path, originalPath: nil, status: "?"))
            case ("!", "!"):
                continue
            case ("U", _), (_, "U"), ("A", "A"), ("D", "D"):
                changes.append(GitChange(area: .unstaged, path: path, originalPath: nil, status: "U"))
            default:
                if x != " " {
                    changes.append(GitChange(area: .staged, path: path, originalPath: originalPath, status: x))
                }
                if y != " " {
                    changes.append(GitChange(area: .unstaged, path: path, originalPath: nil, status: y))
                }
            }
        }
        return changes.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    // MARK: Diff

    private func loadDiff() {
        diffGeneration += 1
        let generation = diffGeneration
        guard let root, let change = selectedChange else {
            diff = nil
            return
        }
        Task {
            let shown = await Self.diff(of: change, in: root)
            guard generation == diffGeneration else { return }
            diff = shown
        }
    }

    private nonisolated static func diff(of change: GitChange, in root: URL) async -> ShownDiff {
        if change.isConflict {
            return ShownDiff(
                change: change, text: "", file: nil,
                notice: "This file has merge conflicts. Resolve them in the editor, then stage the file."
            )
        }

        // Fixed prefixes and no external tools, whatever the user's git config says,
        // so that partial patches built from the output apply.
        var arguments = [
            "-c", "core.quotePath=false", "diff", "--no-color", "--no-ext-diff", "--no-textconv",
            "--src-prefix=a/", "--dst-prefix=b/", "--unified=3",
        ]
        var successCodes: Set<Int32> = [0]
        switch change.area {
        case .staged:
            arguments += ["--cached", "--", change.path]
        case .unstaged where change.isUntracked:
            // Exits with 1 when the files differ, which they always do.
            arguments += ["--no-index", "--", "/dev/null", change.path]
            successCodes = [0, 1]
        case .unstaged:
            arguments += ["--", change.path]
        }

        let data: Data
        do {
            data = try await Git.output(arguments, in: root, successCodes: successCodes)
        } catch {
            return ShownDiff(change: change, text: "", file: nil, notice: error.localizedDescription)
        }
        // Lines staged from a lossy decoding would write the replacement characters into the index.
        guard let text = String(data: data, encoding: .utf8) else {
            return ShownDiff(change: change, text: "", file: nil,
                             notice: "This file is not UTF-8 text, so its changes can’t be shown.")
        }

        let file = FileDiff(parsing: text)
        let notice: String? = if file.isBinary {
            "Binary file"
        } else if file.hunks.isEmpty {
            file.isModeChange ? "Only the file mode changed." : "No changes to show."
        } else {
            nil
        }
        return ShownDiff(change: change, text: text, file: file, notice: notice)
    }

    // MARK: Lines

    func apply(_ action: LineAction, to lines: Set<FileDiff.LineID>) {
        guard let root, let shown = diff, let file = shown.file, file.allowsLineSelection,
              let patch = file.patch(selecting: lines, reverse: action != .stage) else { return }
        if action == .discard {
            guard confirmDiscard(
                "Discard the selected changes in “\(shown.change.name)”?",
                info: "This can’t be undone."
            ) else { return }
        }

        var arguments = ["apply", "--recount", "--whitespace=nowarn"]
        if action != .discard { arguments.append("--cached") }
        if action != .stage { arguments.append("--reverse") }
        arguments.append("-")
        perform { try await Git.output(arguments, in: root, input: Data(patch.utf8)) }
    }

    // MARK: Files

    func stage(_ change: GitChange) {
        guard let root else { return }
        perform { try await Git.output(["add", "-A", "--", change.path], in: root) }
    }

    func unstage(_ change: GitChange) {
        guard let root else { return }
        let paths = [change.path] + (change.originalPath.map { [$0] } ?? [])
        perform {
            if try await Self.hasCommits(in: root) {
                try await Git.output(["restore", "--staged", "--"] + paths, in: root)
            } else {
                try await Git.output(["rm", "--cached", "-r", "-q", "--"] + paths, in: root)
            }
        }
    }

    /// Takes the working copy back to the staged version, or moves an untracked file to the Trash.
    func discard(_ change: GitChange) {
        guard let root, change.area == .unstaged, !change.isConflict else { return }
        let info = change.isUntracked ? "The file will be moved to the Trash." : "This can’t be undone."
        guard confirmDiscard("Discard the changes in “\(change.name)”?", info: info) else { return }

        if change.isUntracked {
            perform { try FileManager.default.trashItem(at: root.appendingPathComponent(change.path), resultingItemURL: nil) }
        } else {
            perform { try await Git.output(["restore", "--", change.path], in: root) }
        }
    }

    func stageAll() {
        guard let root else { return }
        perform { try await Git.output(["add", "-A"], in: root) }
    }

    func unstageAll() {
        guard let root else { return }
        perform {
            if try await Self.hasCommits(in: root) {
                try await Git.output(["reset", "-q"], in: root)
            } else {
                try await Git.output(["rm", "--cached", "-r", "-q", "."], in: root)
            }
        }
    }

    // MARK: Helpers

    /// A new repository has no HEAD to restore the index from.
    private nonisolated static func hasCommits(in root: URL) async throws -> Bool {
        do {
            _ = try await Git.output(["rev-parse", "--verify", "-q", "HEAD"], in: root)
            return true
        } catch is Git.Failure {
            return false
        }
    }

    private func confirmDiscard(_ message: String, info: String) -> Bool {
        Alerts.ask(message, info: info, buttons: ["Cancel", "Discard"]) == 1
    }

    /// Runs a git change, shows its error if it fails and refreshes either way.
    private func perform(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                Alerts.show(error)
            }
            refresh()
        }
    }
}
