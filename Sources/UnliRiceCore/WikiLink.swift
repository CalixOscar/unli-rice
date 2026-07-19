import Foundation

/// Parses `[[wiki-link]]` spans out of note bodies.
///
/// Links are never stored. The log keeps note text exactly as it was written and
/// `Projector` re-derives every link on each projection, which keeps linking
/// consistent with the append-only rule: making, breaking, or re-pointing a link
/// is a property of the text itself, never a separate mutation of the graph.
public enum WikiLink {
    private static let opening = "[["
    private static let closing = "]]"

    /// Link targets in order of appearance. An unterminated `[[` yields nothing —
    /// a half-typed link is simply not a link yet — and `[[]]` is skipped rather
    /// than treated as a link to nowhere.
    public static func targets(in text: String) -> [String] {
        var found: [String] = []
        var cursor = text.startIndex

        while let open = text.range(of: opening, range: cursor..<text.endIndex) {
            guard let close = text.range(of: closing, range: open.upperBound..<text.endIndex) else { break }

            // A nearer `[[` means this opener was never a link. Restart from the
            // inner one so a stray bracket can't swallow the rest of the note and
            // surface it as a bogus dangling link.
            if let nextOpen = text.range(of: opening, range: open.upperBound..<text.endIndex),
               nextOpen.lowerBound < close.lowerBound {
                cursor = nextOpen.lowerBound
                continue
            }

            let target = text[open.upperBound..<close.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !target.isEmpty { found.append(target) }
            cursor = close.upperBound
        }

        return found
    }
}
