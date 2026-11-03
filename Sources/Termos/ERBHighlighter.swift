import AppKit
import CodeEditLanguages
import CodeEditSourceEditor
import CodeEditTextView
import SwiftTreeSitter

/// Highlights ERB tags (`<% %>`, `<%= %>`, `<%# %>`) and the Ruby inside them, on top
/// of the highlighting of the template's own language (HTML for `.html.erb`).
///
/// CodeEditLanguages has no ERB grammar, so the tags are found here and the Ruby is
/// parsed with the Ruby grammar from a copy of the text in which everything outside
/// the tags is blanked out. Offsets stay the same, so the Ruby highlights land in
/// place. Every tag ends with a `;` in that copy, so `<% if x %>…<% end %>` reads as
/// `if x; end;`.
///
/// It goes first in the editor's highlight providers, so inside a tag its colors win.
@MainActor
final class ERBHighlighter: HighlightProviding {
    /// Whether the document is an ERB template; checked whenever the language is set,
    /// so a new file saved as `.erb` picks it up.
    var isEnabled: () -> Bool = { false }
    private var isActive = false
    /// All highlights in the document, ordered by position.
    private var highlights: [HighlightRange] = []

    func setUp(textView: TextView, codeLanguage: CodeLanguage) {
        isActive = isEnabled()
        update(textView)
    }

    func applyEdit(
        textView: TextView,
        range: NSRange,
        delta: Int,
        completion: @escaping @MainActor (Result<IndexSet, Error>) -> Void
    ) {
        guard isActive else {
            completion(.success(IndexSet()))
            return
        }
        // An edit can open or close a tag and change the Ruby after it, so everything is
        // re-highlighted; the editor only queries what is on screen.
        update(textView)
        completion(.success(IndexSet(integersIn: 0..<textView.length)))
    }

    func queryHighlightsFor(
        textView: TextView,
        range: NSRange,
        completion: @escaping @MainActor (Result<[HighlightRange], Error>) -> Void
    ) {
        let result = highlights.compactMap { highlight -> HighlightRange? in
            guard let clipped = highlight.range.intersection(range), clipped.length > 0 else { return nil }
            return HighlightRange(range: clipped, capture: highlight.capture)
        }
        completion(.success(result))
    }

    private func update(_ textView: TextView) {
        highlights = isActive ? Self.highlights(in: textView.string) : []
    }

    // MARK: Parsing

    private struct Tag {
        /// `<%`, `<%=`, `<%-`, … up to the code.
        var open: NSRange
        var code: NSRange
        /// `%>` or `-%>`; empty when the tag is not closed.
        var close: NSRange
        var isComment: Bool
    }

    private static let percent: unichar = 0x25  // %
    private static let lessThan: unichar = 0x3C  // <
    private static let greaterThan: unichar = 0x3E  // >
    private static let hash: unichar = 0x23  // #
    private static let equals: unichar = 0x3D  // =
    private static let minus: unichar = 0x2D  // -
    private static let space: unichar = 0x20
    private static let semicolon: unichar = 0x3B

    private static func tags(in units: [unichar]) -> [Tag] {
        var tags: [Tag] = []
        var index = 0
        let count = units.count
        while index + 1 < count {
            guard units[index] == lessThan, units[index + 1] == percent else {
                index += 1
                continue
            }
            // `<%%` is a literal `<%`, not a tag.
            if index + 2 < count, units[index + 2] == percent {
                index += 3
                continue
            }
            let start = index
            var codeStart = index + 2
            var isComment = false
            if codeStart < count {
                switch units[codeStart] {
                case hash:
                    isComment = true
                    codeStart += 1
                case equals:
                    codeStart += 1
                    if codeStart < count, units[codeStart] == equals { codeStart += 1 }  // <%==
                case minus:
                    codeStart += 1
                default:
                    break
                }
            }

            // The first `%>` ends the tag, as in ERB itself.
            var end = codeStart
            while end + 1 < count, !(units[end] == percent && units[end + 1] == greaterThan) {
                end += 1
            }
            let closed = end + 1 < count
            let codeEnd: Int
            let close: NSRange
            if closed {
                codeEnd = end > codeStart && units[end - 1] == minus ? end - 1 : end
                close = NSRange(location: codeEnd, length: end + 2 - codeEnd)
            } else {
                codeEnd = count
                close = NSRange(location: count, length: 0)
            }
            tags.append(Tag(
                open: NSRange(location: start, length: codeStart - start),
                code: NSRange(location: codeStart, length: max(0, codeEnd - codeStart)),
                close: close,
                isComment: isComment
            ))
            index = closed ? end + 2 : count
        }
        return tags
    }

    private static func highlights(in text: String) -> [HighlightRange] {
        let units = Array(text.utf16)
        let tags = tags(in: units)
        guard !tags.isEmpty else { return [] }

        var result: [HighlightRange] = []
        let rubyHighlights = rubyHighlights(units: units, tags: tags)
        var rubyIndex = 0

        for tag in tags {
            if tag.isComment {
                let whole = NSRange(location: tag.open.location, length: NSMaxRange(tag.close) - tag.open.location)
                result.append(HighlightRange(range: whole, capture: .comment))
                continue
            }
            result.append(HighlightRange(range: tag.open, capture: .tag))
            // Ruby highlights are sorted too; take the ones inside this tag's code.
            while rubyIndex < rubyHighlights.count, rubyHighlights[rubyIndex].range.location < NSMaxRange(tag.code) {
                let highlight = rubyHighlights[rubyIndex]
                if let clipped = highlight.range.intersection(tag.code), clipped.length > 0 {
                    result.append(HighlightRange(range: clipped, capture: highlight.capture))
                }
                rubyIndex += 1
            }
            if tag.close.length > 0 {
                result.append(HighlightRange(range: tag.close, capture: .tag))
            }
        }
        return result
    }

    /// Highlights of the Ruby code in the tags, ordered by position and not overlapping.
    private static func rubyHighlights(units: [unichar], tags: [Tag]) -> [HighlightRange] {
        // Blank out everything but the code, keeping line breaks so the Ruby parser
        // sees the same lines, and end each tag's code with `;`.
        var ruby = units.map { $0 == 0x0A || $0 == 0x0D ? $0 : space }
        for tag in tags where !tag.isComment {
            for offset in tag.code.location..<NSMaxRange(tag.code) {
                ruby[offset] = units[offset]
            }
            if tag.close.length > 0 {
                ruby[tag.close.location] = semicolon
            }
        }
        let source = String(utf16CodeUnits: ruby, count: ruby.count)

        guard let language = CodeLanguage.ruby.language,
              let query = TreeSitterModel.shared.query(for: .ruby) else { return [] }
        let parser = Parser()
        guard (try? parser.setLanguage(language)) != nil,
              let tree = parser.parse(source), let root = tree.rootNode else { return [] }

        // Like CodeEditSourceEditor's own highlighter: where captures share a range, the
        // one from the earlier pattern in the query wins.
        var best: [NSRange: (index: Int, capture: CaptureName)] = [:]
        let captures = query.execute(node: root, in: tree)
            .resolve(with: .init(string: source))
            .flatMap(\.captures)
        for capture in captures {
            guard let name = CaptureName.fromString(capture.name), capture.range.length > 0 else { continue }
            if let existing = best[capture.range], existing.index <= capture.index { continue }
            best[capture.range] = (capture.index, name)
        }

        // Nested captures (a string inside an interpolation, …): the innermost one wins.
        // Paint the ranges from the outermost to the innermost into one style per unit.
        var styles = [CaptureName?](repeating: nil, count: units.count)
        let ordered = best.sorted { $0.key.length > $1.key.length }
        for (range, value) in ordered where NSMaxRange(range) <= units.count {
            for offset in range.location..<NSMaxRange(range) {
                styles[offset] = value.capture
            }
        }

        var result: [HighlightRange] = []
        var offset = 0
        while offset < styles.count {
            guard let capture = styles[offset] else {
                offset += 1
                continue
            }
            let start = offset
            while offset < styles.count, styles[offset] == capture { offset += 1 }
            result.append(HighlightRange(range: NSRange(location: start, length: offset - start), capture: capture))
        }
        return result
    }
}
