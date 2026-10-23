import Observation
import SwiftUI

/// State of the Cmd+P file finder: the file list of a directory and the ranked results.
@MainActor
@Observable
final class QuickOpenModel {
    nonisolated static let resultLimit = 50

    let root: URL
    var query = "" {
        didSet { search() }
    }
    private(set) var results: [FuzzyMatch] = []
    var selectedIndex = 0
    private(set) var isIndexing = true

    @ObservationIgnored private var files: [String] = []
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    /// Last file list of the few most recent directories, shown instantly while a fresh
    /// one is built. Bounded, since a big list takes megabytes.
    private static var cache: [String: [String]] = [:]
    /// Cached directories, least recently used first.
    private static var cacheOrder: [String] = []
    private static let cacheLimit = 4

    init(root: URL) {
        self.root = root
        if let cached = Self.cache[root.path] {
            files = cached
            isIndexing = false
        }
        search()

        Task.detached(priority: .userInitiated) { [weak self] in
            let files = FileIndex.files(in: root)
            await self?.indexFinished(files)
        }
    }

    var selectedURL: URL? {
        results.indices.contains(selectedIndex) ? root.appendingPathComponent(results[selectedIndex].path) : nil
    }

    func moveSelection(by offset: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + offset, 0), results.count - 1)
    }

    private func indexFinished(_ files: [String]) {
        Self.store(files, for: root.path)
        self.files = files
        isIndexing = false
        search()
    }

    private static func store(_ files: [String], for path: String) {
        cache[path] = files
        cacheOrder.removeAll { $0 == path }
        cacheOrder.append(path)
        while cacheOrder.count > cacheLimit {
            cache[cacheOrder.removeFirst()] = nil
        }
    }

    /// Ranks off the main thread; a newer query cancels the running one.
    private func search() {
        searchTask?.cancel()
        let query = query
        let files = files
        searchTask = Task.detached(priority: .userInitiated) { [weak self] in
            let ranked = Self.rank(query, in: files)
            guard !Task.isCancelled else { return }
            await self?.show(ranked)
        }
    }

    private func show(_ ranked: [FuzzyMatch]) {
        results = ranked
        selectedIndex = 0
    }

    private nonisolated static func rank(_ query: String, in files: [String]) -> [FuzzyMatch] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            // No query: shallow, short paths first.
            return files
                .sorted { ($0.count, $0) < ($1.count, $1) }
                .prefix(resultLimit)
                .map { FuzzyMatch(path: $0, score: 0, positions: []) }
        }

        var matches: [FuzzyMatch] = []
        for (index, file) in files.enumerated() {
            if index % 4096 == 0, Task.isCancelled { return [] }
            if let match = FuzzyMatcher.match(query, in: file) {
                matches.append(match)
            }
        }
        return Array(matches
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.path.count < $1.path.count }
            .prefix(resultLimit))
    }
}

/// The Cmd+P overlay: a search field and the matching files.
struct QuickOpenView: View {
    @Bindable var model: QuickOpenModel
    let onOpen: (URL) -> Void
    let onDismiss: () -> Void
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("Go to file…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(12)
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

            Divider()

            if model.results.isEmpty {
                Text(model.isIndexing ? "Indexing files…" : "No matching files")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                resultList
            }
        }
        .frame(width: 600)
        // Opaque, so code behind the overlay does not bleed through the results.
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
        .onAppear { isFieldFocused = true }
    }

    private var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.path) { index, match in
                        QuickOpenRow(match: match, isSelected: index == model.selectedIndex)
                            .id(match.path)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedIndex = index
                                open()
                            }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 380)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: model.selectedIndex) {
                guard model.results.indices.contains(model.selectedIndex) else { return }
                proxy.scrollTo(model.results[model.selectedIndex].path)
            }
        }
    }

    private func open() {
        guard let url = model.selectedURL else { return }
        onOpen(url)
    }
}

private struct QuickOpenRow: View {
    let match: FuzzyMatch
    let isSelected: Bool

    var body: some View {
        let path = match.path as NSString
        let name = path.lastPathComponent
        let nameOffset = path.length - (name as NSString).length
        let directory = nameOffset > 0 ? path.substring(to: nameOffset - 1) : ""
        let positions = Set(match.positions)

        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: path.pathExtension) ?? .data))
                .resizable()
                .frame(width: 16, height: 16)
            Text(Self.highlighted(name, from: nameOffset, positions, style: .name, isSelected: isSelected))
                .lineLimit(1)
                .layoutPriority(1)
            Text(Self.highlighted(directory, from: 0, positions, style: .directory, isSelected: isSelected))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }

    private enum Style { case name, directory }

    /// Colors the text and emphasizes matched characters.
    ///
    /// On a normal row matches are bold and in the accent color. On the selected row
    /// (accent background) everything is white, with matches bold and the rest dimmed.
    /// `offset` is where `text` starts in the full path (UTF-16).
    private static func highlighted(
        _ text: String, from offset: Int, _ positions: Set<Int>, style: Style, isSelected: Bool
    ) -> AttributedString {
        let size: CGFloat = style == .name ? 13 : 11.5
        let baseColor: Color = switch (style, isSelected) {
        case (.name, false): .primary
        case (.directory, false): .secondary
        case (.name, true): .white.opacity(0.9)
        case (.directory, true): .white.opacity(0.75)
        }
        let matchColor: Color = isSelected ? .white : .accentColor

        var result = AttributedString()
        var utf16Offset = offset
        for character in text {
            let length = String(character).utf16.count
            let isMatch = (utf16Offset..<utf16Offset + length).contains(where: positions.contains)
            var part = AttributedString(String(character))
            part.font = .system(size: size, weight: isMatch ? .bold : (style == .name ? .medium : .regular))
            part.foregroundColor = isMatch ? matchColor : baseColor
            result += part
            utf16Offset += length
        }
        return result
    }
}
