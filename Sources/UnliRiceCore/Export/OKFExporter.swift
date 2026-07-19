import Foundation

/// Writes notes as an Open Knowledge Format v0.1 bundle: index.md + log.md +
/// one Concept file per note. This is a one-way export rendered fresh from the
/// event log every time — the log stays the only source of truth (see
/// PROJECT_NOTES.md); nothing reads these files back in yet.
public enum OKFExporter {
    public static func exportBundle(notes: [Note], events: [Event], to directory: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let ordered = notes.sorted { $0.updatedAt > $1.updatedAt }
        var usedNames: Set<String> = []
        let conceptFiles: [(note: Note, slug: String)] = ordered.map { note in
            (note, Slug.unique(for: note.title, avoiding: &usedNames))
        }

        try writeIndex(conceptFiles, to: directory.appendingPathComponent("index.md"))
        try writeLog(events: events, notes: notes, to: directory.appendingPathComponent("log.md"))

        for (note, slug) in conceptFiles {
            let content = conceptFrontmatter(for: note) + "\n\n" + note.body + "\n"
            try content.write(to: directory.appendingPathComponent("\(slug).md"), atomically: true, encoding: .utf8)
        }
    }

    // MARK: - index.md

    private static func writeIndex(_ conceptFiles: [(note: Note, slug: String)], to url: URL) throws {
        var out = "---\nokf_version: \"0.1\"\n---\n\n# Notes\n\n"
        for (note, slug) in conceptFiles {
            out += "- [\(note.title)](/\(slug).md)\n"
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - log.md

    private static func writeLog(events: [Event], notes: [Note], to url: URL) throws {
        let titles = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.title) })
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.timeZone = TimeZone(identifier: "UTC")

        let grouped = Dictionary(grouping: events) { dayFormatter.string(from: $0.timestamp) }
        var out = ""
        for day in grouped.keys.sorted(by: >) {
            out += "## \(day)\n"
            for event in grouped[day]!.sorted(by: { $0.timestamp > $1.timestamp }) {
                let noteTitle = titles[event.noteId] ?? "(unknown note)"
                out += "* **\(label(for: event.kind))**: \(noteTitle) — \(event.source)\n"
            }
            out += "\n"
        }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func label(for kind: EventKind) -> String {
        switch kind {
        case .created: return "Creation"
        case .appended: return "Update"
        case .tagged: return "Tag"
        case .untagged: return "Untag"
        case .archived: return "Archive"
        case .unarchived: return "Unarchive"
        case .flagged: return "Flag"
        case .reviewResolved: return "Review resolved"
        }
    }

    // MARK: - Concept frontmatter

    private static func conceptFrontmatter(for note: Note) -> String {
        var lines = ["---", "type: note", "title: \"\(escape(note.title))\""]

        let description = firstSentence(of: note.body)
        if !description.isEmpty {
            lines.append("description: \"\(escape(description))\"")
        }
        if !note.tags.isEmpty {
            lines.append("tags: [\(note.tags.sorted().map { "\"\(escape($0))\"" }.joined(separator: ", "))]")
        }
        lines.append("timestamp: \"\(ISO8601DateFormatter().string(from: note.updatedAt))\"")
        lines.append("resource: \"unlirice://note/\(note.id.uuidString)\"")
        lines.append("---")
        return lines.joined(separator: "\n")
    }

    private static func firstSentence(of body: String) -> String {
        guard !body.isEmpty else { return "" }
        let normalized = body.replacingOccurrences(of: "\n", with: " ")
        if let range = normalized.range(of: ". ") {
            return String(normalized[normalized.startIndex..<range.lowerBound]) + "."
        }
        return String(normalized.prefix(140))
    }

    private static func escape(_ string: String) -> String {
        string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
