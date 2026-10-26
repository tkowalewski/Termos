import Observation
import SwiftUI

/// A line that contains the query, found by the Cmd+E content search.
struct ContentMatch: Sendable, Identifiable {
    /// Path relative to the searched directory.
    let path: String
    /// 1-based line number.
    let line: Int
    /// 1-based UTF-16 column of the first match in the line.
    let column: Int
    /// UTF-16 length of the query match.
    let length: Int
    /// The line, without leading whitespace and shortened around the first match.
    let preview: String
    /// UTF-16 ranges of every match in `preview`, for highlighting.
    let highlights: [NSRange]
    /// On the first match of a file: matching lines of the file left out by the per-file limit.
    var moreInFile = 0

    var id: String { "\(path):\(line)" }
}

/// Literal search through the contents of the files under a directory, like `ag` or `rg`:
/// .gitignore is honoured (through `FileIndex`), binary and very large files are skipped,
/// and the search ignores case unless the query has an uppercase letter.
enum ContentSearcher {
    static let resultLimit = 500
    /// Keeps one file (minified code, a lockfile) from filling the whole list.
    static let perFileLimit = 50
    static let maximumFileSize = 10 * 1024 * 1024
    private static let previewLength = 160
    private static let chunkSize = 256

    /// Searches `files` in order, calling `progress` with everything found so far after
    /// each batch of files. Returns whether the result limit cut the search short.
    static func search(
        _ query: String, in root: URL, files: [String], progress: ([ContentMatch]) async -> Void
    ) async -> Bool {
        let options: NSString.CompareOptions = query.contains(where: \.isUppercase) ? [.literal] : [.literal, .caseInsensitive]
        var found: [ContentMatch] = []
        var start = 0
        while start < files.count {
            if Task.isCancelled { return false }
            let chunk = Array(files[start..<min(start + chunkSize, files.count)])
            start += chunkSize

            let perFile = ChunkResults(count: chunk.count)
            DispatchQueue.concurrentPerform(iterations: chunk.count) { index in
                let url = root.appendingPathComponent(chunk[index])
                perFile.set(index, matches(of: query, options: options, in: url, path: chunk[index]))
            }
            let batch = perFile.all.joined()
            guard !batch.isEmpty else { continue }

            found.append(contentsOf: batch.prefix(resultLimit - found.count))
            if Task.isCancelled { return false }
            await progress(found)
            if found.count >= resultLimit { return true }
        }
        return false
    }

    private static func matches(
        of query: String, options: NSString.CompareOptions, in url: URL, path: String
    ) -> [ContentMatch] {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumFileSize,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              !data.prefix(8000).contains(0) else { return [] }
        let text = String(decoding: data, as: UTF8.self) as NSString

        var results: [ContentMatch] = []
        var lineNumber = 1
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        var searchFrom = 0
        var omitted = 0
        text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))

        while searchFrom < text.length {
            let found = text.range(of: query, options: options, range: NSRange(location: searchFrom, length: text.length - searchFrom))
            guard found.location != NSNotFound else { break }

            // Advance line by line to the one holding the match, counting as we go.
            while found.location >= lineEnd, lineEnd < text.length {
                lineStart = lineEnd
                text.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStart, length: 0))
                lineNumber += 1
            }

            // Every further match in this line is highlighted in the same result.
            let line = NSRange(location: lineStart, length: contentsEnd - lineStart)
            var inLine: [NSRange] = []
            var next = found
            while next.location != NSNotFound, NSMaxRange(next) <= contentsEnd {
                inLine.append(next)
                next = text.range(of: query, options: options, range: NSRange(location: NSMaxRange(next), length: contentsEnd - NSMaxRange(next)))
            }
            if inLine.isEmpty { inLine = [found] }

            if results.count < perFileLimit {
                results.append(result(path: path, lineNumber: lineNumber, line: line, matches: inLine, in: text))
            } else {
                omitted += 1
            }
            searchFrom = max(lineEnd, NSMaxRange(found))
        }
        if omitted > 0 { results[0].moreInFile = omitted }
        return results
    }

    private static func result(path: String, lineNumber: Int, line: NSRange, matches: [NSRange], in text: NSString) -> ContentMatch {
        let first = matches[0]
        // Skip indentation, and start shortly before the match when the line is long.
        var start = line.location
        while start < first.location, let scalar = UnicodeScalar(text.character(at: start)), scalar == " " || scalar == "\t" {
            start += 1
        }
        let lineEnd = NSMaxRange(line)
        if lineEnd - start > previewLength, first.location - start > previewLength / 3 {
            start = first.location - previewLength / 3
        }
        var preview = NSRange(location: start, length: min(lineEnd - start, previewLength))
        preview = text.rangeOfComposedCharacterSequences(for: preview)
        let previewEnd = NSMaxRange(preview)

        let highlights = matches.compactMap { match -> NSRange? in
            guard match.location >= preview.location, match.location < previewEnd else { return nil }
            return NSRange(location: match.location - preview.location, length: min(NSMaxRange(match), previewEnd) - match.location)
        }
        return ContentMatch(
            path: path,
            line: lineNumber,
            column: first.location - line.location + 1,
            length: first.length,
            preview: text.substring(with: preview),
            highlights: highlights
        )
    }
}

/// Matches of each file in a batch, filled from several threads.
private final class ChunkResults: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [[ContentMatch]]

    init(count: Int) {
        results = Array(repeating: [], count: count)
    }

    func set(_ index: Int, _ matches: [ContentMatch]) {
        lock.lock()
        results[index] = matches
        lock.unlock()
    }

    var all: [[ContentMatch]] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

/// State of the Cmd+E content search: the files of a directory and the lines that match.
@MainActor
@Observable
final class ContentSearchModel {
    let root: URL
    var query = "" {
        didSet { if query != oldValue { search() } }
    }
    private(set) var results: [ContentMatch] = []
    var selectedIndex = 0
    private(set) var isIndexing = true
    private(set) var isSearching = false
    /// The result limit stopped the search before every file was read.
    private(set) var isTruncated = false

    @ObservationIgnored private var files: [String] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Shown again the next time the search opens without a selection to search for.
    private static var lastQuery = ""

    init(root: URL, query: String?) {
        self.root = root
        self.query = query ?? Self.lastQuery

        Task.detached(priority: .userInitiated) { [weak self] in
            let files = FileIndex.files(in: root).sorted()
            await self?.indexFinished(files)
        }
    }

    var selectedMatch: ContentMatch? {
        results.indices.contains(selectedIndex) ? results[selectedIndex] : nil
    }

    func url(of match: ContentMatch) -> URL {
        root.appendingPathComponent(match.path)
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private func indexFinished(_ files: [String]) {
        self.files = files
        isIndexing = false
        search()
    }

    /// Searches off the main thread, shortly after typing stops; a newer query cancels it.
    private func search() {
        Self.lastQuery = query
        searchTask?.cancel()
        guard !isIndexing else { return }
        let query = query
        guard !query.isEmpty else {
            results = []
            isSearching = false
            isTruncated = false
            return
        }

        let root = root
        let files = files
        isSearching = true
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            var isFirstBatch = true
            let truncated = await ContentSearcher.search(query, in: root, files: files) { found in
                let replace = isFirstBatch
                isFirstBatch = false
                await self?.show(found, replacingSelection: replace)
            }
            guard !Task.isCancelled else { return }
            await self?.finish(truncated: truncated, isEmpty: isFirstBatch)
        }
    }

    private func show(_ found: [ContentMatch], replacingSelection: Bool) {
        results = found
        if replacingSelection { selectedIndex = 0 }
    }

    private func finish(truncated: Bool, isEmpty: Bool) {
        if isEmpty { results = [] }
        isTruncated = truncated
        isSearching = false
    }
}

/// The Cmd+E overlay: a search field and the matching lines, grouped by file.
struct ContentSearchView: View {
    @Bindable var model: ContentSearchModel
    let onOpen: (ContentMatch) -> Void
    let onDismiss: () -> Void
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search in files…", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($isFieldFocused)
                    .onSubmit(open)
                    .onKeyPress(.upArrow) {
                        model.moveSelection(by: -1)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        model.moveSelection(by: 1)
                        return .handled
                    }
                    .onExitCommand(perform: onDismiss)
                if model.isIndexing || model.isSearching {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(12)

            Divider()

            if model.results.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                resultList
                Divider()
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720)
        // Opaque, so code behind the overlay does not bleed through the results.
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { isFieldFocused = true }
    }

    private var placeholder: String {
        if model.isIndexing { return "Indexing files…" }
        if model.query.isEmpty { return "Type to search the contents of files" }
        return model.isSearching ? "Searching…" : "No matches"
    }

    private var summary: String {
        let files = Set(model.results.map(\.path)).count
        let lines = model.results.count == 1 ? "1 line" : "\(model.results.count) lines"
        let inFiles = files == 1 ? "1 file" : "\(files) files"
        return model.isTruncated ? "First \(lines) in \(inFiles)" : "\(lines) in \(inFiles)"
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, match in
                        if index == 0 || model.results[index - 1].path != match.path {
                            ContentSearchFileHeader(path: match.path, moreLines: match.moreInFile)
                                .padding(.top, index == 0 ? 0 : 6)
                        }
                        ContentSearchRow(match: match, isSelected: index == model.selectedIndex)
                            .id(match.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedIndex = index
                                open()
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 440)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.selectedIndex) {
                guard let match = model.selectedMatch else { return }
                proxy.scrollTo(match.id)
            }
        }
    }

    private func open() {
        guard let match = model.selectedMatch else { return }
        onOpen(match)
    }
}

private struct ContentSearchFileHeader: View {
    let path: String
    let moreLines: Int

    var body: some View {
        let path = path as NSString
        let directory = path.deletingLastPathComponent

        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: path.pathExtension) ?? .data))
                .resizable()
                .frame(width: 16, height: 16)
            Text(path.lastPathComponent)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .layoutPriority(1)
            Text(directory)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            if moreLines > 0 {
                Text("+\(moreLines) more")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .help("Only the first \(ContentSearcher.perFileLimit) matching lines of this file are listed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

private struct ContentSearchRow: View {
    let match: ContentMatch
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(String(match.line))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                .frame(minWidth: 36, alignment: .trailing)
            Text(highlighted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    /// The line with its matches emphasized: bold accent on a normal row, bold white on
    /// the selected row (accent background).
    private var highlighted: AttributedString {
        let text = match.preview as NSString
        let font = Font.system(size: 12, design: .monospaced)
        let baseColor: Color = isSelected ? .white.opacity(0.85) : .primary
        let matchColor: Color = isSelected ? .white : .accentColor

        var result = AttributedString()
        func append(_ range: NSRange, isMatch: Bool) {
            guard range.length > 0 else { return }
            var part = AttributedString(text.substring(with: range))
            part.font = isMatch ? font.bold() : font
            part.foregroundColor = isMatch ? matchColor : baseColor
            if isMatch, !isSelected { part.backgroundColor = Color.accentColor.opacity(0.15) }
            result += part
        }
        var position = 0
        for highlight in match.highlights where highlight.location >= position {
            append(NSRange(location: position, length: highlight.location - position), isMatch: false)
            append(highlight, isMatch: true)
            position = NSMaxRange(highlight)
        }
        append(NSRange(location: position, length: text.length - position), isMatch: false)
        return result
    }
}
