import CryptoKit
import Foundation

/// Revision parser and wrapper for standing profile notes (`Profile: identity`, `Profile: voice`, etc.).
///
/// Prevents revision accumulation on read sites (Home, MirrorExporter, Clipboard) while preserving
/// full append-only event log history.
public enum ProfileRevision {
    public static let markerPrefix = "<!-- unlirice-profile-revision sha256:"

    public static func normalized(_ body: String) -> String {
        body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func digest(of body: String) -> String {
        SHA256.hash(data: Data(normalized(body).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    public static func wrapped(_ body: String, title: String = "Profile", at date: Date = Date()) -> String {
        let normalizedBody = normalized(body)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
        return """
        # \(title) Revision — \(stamp)

        This revision supersedes every earlier revision in this note. Follow only the latest revision.

        \(normalizedBody)

        \(markerPrefix)\(digest(of: normalizedBody)) -->
        """
    }

    /// Extracts ONLY the latest revision's body text from a note's full body string.
    public static func latestBody(in noteBody: String) -> String {
        let normalizedNote = normalized(noteBody)
        guard !normalizedNote.isEmpty else { return "" }

        // 1. If marker exists, find the last marker and extract the text preceding it
        if let lastMarkerRange = normalizedNote.range(of: markerPrefix, options: .backwards) {
            let beforeMarker = String(normalizedNote[..<lastMarkerRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)

            if let headerRange = beforeMarker.range(of: "This revision supersedes every earlier revision in this note. Follow only the latest revision.", options: .backwards) {
                let content = String(beforeMarker[headerRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !content.isEmpty {
                    return content
                }
            } else if let revHeaderRange = beforeMarker.range(of: "# ", options: .backwards) {
                if let lineEnd = beforeMarker[revHeaderRange.upperBound...].range(of: "\n") {
                    let content = String(beforeMarker[lineEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        return content
                    }
                }
            }
            return beforeMarker
        }

        // 2. Compatibility path for notes with plain `\n\n---\n### Revision (` separators
        if normalizedNote.contains("### Revision (") {
            let parts = normalizedNote.components(separatedBy: "\n---\n### Revision (")
            if let lastPart = parts.last {
                if let firstLineEnd = lastPart.range(of: "\n") {
                    let body = String(lastPart[firstLineEnd.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        return body
                    }
                }
            }
        } else if normalizedNote.contains("\n---\n") {
            let parts = normalizedNote.components(separatedBy: "\n---\n")
            if let lastPart = parts.last {
                let trimmed = lastPart.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }

        // 3. Fallback: single revision / unsegmented note body
        return normalizedNote
    }

    public static func noteContainsCurrentRevision(noteBody: String, draftBody: String) -> Bool {
        let draft = normalized(draftBody)
        let latest = latestBody(in: noteBody)
        return normalized(latest) == draft
    }
}
