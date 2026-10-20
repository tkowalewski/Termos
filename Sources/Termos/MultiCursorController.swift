import AppKit
import CodeEditTextView

/// VS Code style multiple cursors on top of CodeEditTextView's selection model.
///
/// CodeEditTextView already types, deletes and moves on every selection; this adds
/// the commands around it (Cmd+D and friends), remembering the order in which
/// cursors were added so "undo last cursor" and "skip" know which one is last.
@MainActor
final class MultiCursorController {
    private weak var textView: TextView?

    /// Ranges added by occurrence/cursor commands, oldest first.
    private var history: [NSRange] = []
    /// Cmd+D started from a bare cursor matches whole words only, like VS Code.
    private var matchWholeWords = false

    init(textView: TextView) {
        self.textView = textView
    }

    private var selections: [NSRange] {
        textView?.selectionManager.textSelections.map(\.range) ?? []
    }

    private var text: NSString {
        (textView?.textStorage.string ?? "") as NSString
    }

    // MARK: Occurrences

    /// Cmd+D: selects the word under a bare cursor, then adds the next occurrence of the selection.
    func addNextOccurrence() {
        guard let textView else { return }
        if selectWordUnderSingleCursor() { return }

        guard let last = lastAddedSelection(),
              let match = nextOccurrence(of: needle(), after: last) else { return }
        textView.selectionManager.addSelectedRange(match)
        history.append(match)
        textView.scrollToRange(match, center: false)
    }

    /// Cmd+K Cmd+D: drops the most recently added occurrence and moves on to the next one.
    func skipOccurrence() {
        guard let textView, let last = lastAddedSelection(), selections.count > 1 else {
            addNextOccurrence()
            return
        }
        let needle = needle()
        remove(last)
        guard let match = nextOccurrence(of: needle, after: last) else { return }
        textView.selectionManager.addSelectedRange(match)
        history.append(match)
        textView.scrollToRange(match, center: false)
    }

    /// Cmd+Shift+L: selects every occurrence of the selection (or of the word under the cursor).
    func selectAllOccurrences() {
        guard let textView else { return }
        _ = selectWordUnderSingleCursor()
        let needle = needle()
        guard !needle.isEmpty else { return }

        let matches = occurrences(of: needle)
        guard !matches.isEmpty else { return }
        textView.selectionManager.setSelectedRanges(matches)
        history = matches
    }

    /// Cmd+U: removes the most recently added cursor.
    func undoLastCursor() {
        guard selections.count > 1, let last = lastAddedSelection() else { return }
        remove(last)
        if let previous = lastAddedSelection() {
            textView?.scrollToRange(previous, center: false)
        }
    }

    // MARK: Cursors

    /// Option+Cmd+Up/Down: adds a cursor on the line above the topmost / below the bottommost cursor.
    func addCursor(above: Bool) {
        guard let textView, let layout = textView.layoutManager else { return }
        let ranges = selections
        guard let anchor = above ? ranges.min(by: { $0.location < $1.location }) : ranges.max(by: { $0.max < $1.max }) else { return }

        let offset = above ? anchor.location : anchor.max
        guard let line = layout.textLineForOffset(offset),
              let target = layout.textLineForIndex(line.index + (above ? -1 : 1)),
              let x = layout.rectForOffset(offset)?.minX,
              let newOffset = layout.textOffsetAtPoint(CGPoint(x: x, y: target.yPos + target.height / 2)) else { return }

        let range = NSRange(location: newOffset, length: 0)
        textView.selectionManager.addSelectedRange(range)
        history.append(range)
        textView.scrollToRange(range, center: false)
    }

    /// Option+click: adds a cursor at the given text offset.
    func addCursor(at offset: Int) {
        let range = NSRange(location: offset, length: 0)
        if history.isEmpty, let first = selections.first { history = [first] }
        textView?.selectionManager.addSelectedRange(range)
        history.append(range)
    }

    /// Esc with several cursors: keeps only the first one. Returns false when there was only one.
    func collapseToSingleCursor() -> Bool {
        guard selections.count > 1, let primary = history.first(where: selections.contains) ?? selections.first else {
            return false
        }
        textView?.selectionManager.setSelectedRange(primary)
        history = []
        return true
    }

    // MARK: Clipboard

    /// Copies several selections as lines, like VS Code. Returns false when there is a single selection.
    func copy() -> Bool {
        let ranges = selections
        guard ranges.count > 1 else { return false }
        let joined = ranges.map { text.substring(with: $0) }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(joined, forType: .string)
        return true
    }

    func cut() -> Bool {
        guard copy(), let textView else { return false }
        textView.replaceCharacters(in: selections.filter { $0.length > 0 }, with: "")
        return true
    }

    /// Pastes one clipboard line per cursor when the counts match. Returns false otherwise.
    func paste() -> Bool {
        guard let textView, let string = NSPasteboard.general.string(forType: .string) else { return false }
        let ranges = selections
        var lines = string.components(separatedBy: "\n")
        if lines.count == ranges.count + 1, lines.last == "" { lines.removeLast() }
        guard ranges.count > 1, lines.count == ranges.count else { return false }

        // One undo step for the whole paste. Edits go bottom-up so earlier ranges stay valid.
        textView.undoManager?.beginUndoGrouping()
        for (range, line) in zip(ranges, lines).sorted(by: { $0.0.location > $1.0.location }) {
            textView.replaceCharacters(in: range, with: line)
        }
        textView.undoManager?.endUndoGrouping()
        return true
    }

    // MARK: Helpers

    /// With one empty selection, selects the word around it and returns true.
    private func selectWordUnderSingleCursor() -> Bool {
        guard let textView, selections.count == 1, let cursor = selections.first, cursor.length == 0,
              let word = wordRange(at: cursor.location) else { return false }
        textView.selectionManager.setSelectedRange(word)
        history = [word]
        matchWholeWords = true
        return true
    }

    /// Text that occurrences are searched for: the oldest added selection, as VS Code does.
    private func needle() -> String {
        let ranges = selections
        guard let base = history.first(where: ranges.contains) ?? ranges.first else { return "" }
        if !history.contains(base) { matchWholeWords = false }
        return text.substring(with: base)
    }

    /// The most recently added selection that still exists; falls back to the last one in the text.
    private func lastAddedSelection() -> NSRange? {
        let ranges = selections
        history.removeAll { !ranges.contains($0) }
        return history.last ?? ranges.max(by: { $0.location < $1.location })
    }

    private func remove(_ range: NSRange) {
        history.removeAll { $0 == range }
        textView?.selectionManager.setSelectedRanges(selections.filter { $0 != range })
    }

    /// Next match after `range` that is not already selected, wrapping around the end of the file.
    private func nextOccurrence(of needle: String, after range: NSRange) -> NSRange? {
        guard !needle.isEmpty else { return nil }
        let selected = Set(selections.map { "\($0.location):\($0.length)" })
        let all = occurrences(of: needle).filter { !selected.contains("\($0.location):\($0.length)") }
        return all.first { $0.location >= range.max } ?? all.first
    }

    private func occurrences(of needle: String) -> [NSRange] {
        let text = self.text
        var result: [NSRange] = []
        var searchRange = NSRange(location: 0, length: text.length)
        while searchRange.length > 0 {
            let found = text.range(of: needle, options: [.literal], range: searchRange)
            guard found.location != NSNotFound else { break }
            if !matchWholeWords || isWholeWord(found) {
                result.append(found)
            }
            let next = found.max
            searchRange = NSRange(location: next, length: text.length - next)
        }
        return result
    }

    private func isWholeWord(_ range: NSRange) -> Bool {
        let text = self.text
        let before = range.location > 0 && isWordCharacter(text.character(at: range.location - 1))
        let after = range.max < text.length && isWordCharacter(text.character(at: range.max))
        return !before && !after
    }

    private func wordRange(at location: Int) -> NSRange? {
        let text = self.text
        var start = location
        var end = location
        while start > 0, isWordCharacter(text.character(at: start - 1)) { start -= 1 }
        while end < text.length, isWordCharacter(text.character(at: end)) { end += 1 }
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    private func isWordCharacter(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return false }
        return scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
    }
}
