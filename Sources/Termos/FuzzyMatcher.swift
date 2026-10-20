import Foundation

struct FuzzyMatch: Sendable {
    /// Path relative to the searched directory.
    let path: String
    let score: Int
    /// UTF-16 offsets of the matched characters in `path`, for highlighting.
    let positions: [Int]
}

/// Subsequence matching with fzf/VS Code-like scoring: matched characters count
/// more at word starts, in runs, and in the file name rather than the directories.
enum FuzzyMatcher {
    static func match(_ query: String, in path: String) -> FuzzyMatch? {
        let needle = query.utf16.filter { $0 != 0x20 }.map(lowercased)
        guard !needle.isEmpty else { return FuzzyMatch(path: path, score: 0, positions: []) }

        let original = Array(path.utf16)
        let haystack = original.map(lowercased)
        let nameStart = (original.lastIndex(of: 0x2F)).map { $0 + 1 } ?? 0 // after the last "/"

        // Prefer a match inside the file name; fall back to the whole path.
        if let positions = bestPositions(needle, haystack, from: nameStart) {
            let score = score(positions, original) + 40 + (positions.first == nameStart ? 20 : 0)
            return FuzzyMatch(path: path, score: score - original.count / 8, positions: positions)
        }
        if let positions = bestPositions(needle, haystack, from: 0) {
            return FuzzyMatch(path: path, score: score(positions, original) - original.count / 8, positions: positions)
        }
        return nil
    }

    /// Finds the shortest window containing the query as a subsequence (fzf v1), then
    /// matches greedily inside it.
    private static func bestPositions(_ needle: [UInt16], _ haystack: [UInt16], from start: Int) -> [Int]? {
        // Forward: first place where the whole query fits.
        var queryIndex = 0
        var end = -1
        var index = start
        while index < haystack.count {
            if haystack[index] == needle[queryIndex] {
                queryIndex += 1
                if queryIndex == needle.count {
                    end = index
                    break
                }
            }
            index += 1
        }
        guard end >= 0 else { return nil }

        // Backward from that end: tightest start.
        queryIndex = needle.count - 1
        var windowStart = end
        while windowStart >= start {
            if haystack[windowStart] == needle[queryIndex] {
                if queryIndex == 0 { break }
                queryIndex -= 1
            }
            windowStart -= 1
        }

        var positions: [Int] = []
        queryIndex = 0
        for position in windowStart...end where queryIndex < needle.count && haystack[position] == needle[queryIndex] {
            positions.append(position)
            queryIndex += 1
        }
        return positions
    }

    private static func score(_ positions: [Int], _ text: [UInt16]) -> Int {
        var score = 0
        var previous: Int?
        for position in positions {
            score += 16
            if position == 0 {
                score += 10
            } else if text[position - 1] == 0x2F {
                score += 12 // start of a path component
            } else if isSeparator(text[position - 1]) {
                score += 10
            } else if isLower(text[position - 1]) && isUpper(text[position]) {
                score += 8 // camelCase boundary
            }
            if let previous {
                let gap = position - previous - 1
                score += gap == 0 ? 8 : -min(gap, 5)
            }
            previous = position
        }
        return score
    }

    private static func lowercased(_ unit: UInt16) -> UInt16 {
        (0x41...0x5A).contains(unit) ? unit + 0x20 : unit
    }

    private static func isUpper(_ unit: UInt16) -> Bool { (0x41...0x5A).contains(unit) }
    private static func isLower(_ unit: UInt16) -> Bool { (0x61...0x7A).contains(unit) }

    private static func isSeparator(_ unit: UInt16) -> Bool {
        // / _ - . and space
        unit == 0x2F || unit == 0x5F || unit == 0x2D || unit == 0x2E || unit == 0x20
    }
}
