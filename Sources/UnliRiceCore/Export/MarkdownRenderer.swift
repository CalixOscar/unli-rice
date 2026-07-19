import Foundation

/// Renders a Note (a projection, per PROJECT_NOTES.md) as plain Markdown. This is
/// the base representation the other export formats build on.
public enum MarkdownRenderer {
    public static func render(_ note: Note) -> String {
        var lines: [String] = ["# \(note.title)", ""]

        if !note.tags.isEmpty {
            lines.append(note.tags.sorted().map { "#\($0)" }.joined(separator: " "))
            lines.append("")
        }

        let sources = note.sources.sorted().joined(separator: ", ")
        lines.append("_Sources: \(sources) · Updated \(ISO8601DateFormatter().string(from: note.updatedAt))_")
        lines.append("")
        lines.append(note.body)

        return lines.joined(separator: "\n")
    }

    /// A single combined document — the "just export everything as one .md" option.
    public static func renderCombined(_ notes: [Note]) -> String {
        notes.map(render).joined(separator: "\n\n---\n\n")
    }
}
