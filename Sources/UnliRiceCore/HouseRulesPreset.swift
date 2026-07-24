import CryptoKit
import Foundation

/// A reusable starting point for the instructions an MCP-connected assistant reads.
/// Presets are drafts only: choosing one never writes to the note store by itself.
public struct HouseRulesPreset: Identifiable, Codable, Equatable, Sendable {
    public enum Origin: String, Codable, Equatable, Sendable {
        case builtIn
        case imported
    }

    public let id: String
    public var title: String
    public var summary: String
    public var body: String
    public var origin: Origin
    public var sourceFilename: String?
    public var importedAt: Date?

    public init(
        id: String,
        title: String,
        summary: String,
        body: String,
        origin: Origin,
        sourceFilename: String? = nil,
        importedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.origin = origin
        self.sourceFilename = sourceFilename
        self.importedAt = importedAt
    }

    public var characterCount: Int { body.count }

    /// A deliberately labelled estimate. Prompt tokenizers vary by model; four
    /// UTF-8 bytes per token is useful for comparison without shipping one.
    public var approximateTokenCount: Int {
        max(1, (body.utf8.count + 3) / 4)
    }

    public static let builtIn: [HouseRulesPreset] = [
        HouseRulesPreset(
            id: "standard",
            title: "Standard Memory",
            summary: "Balanced conventions for a shared, multi-agent memory.",
            body: Autopilot.noteBody,
            origin: .builtIn
        ),
        HouseRulesPreset(
            id: "codebase-memory",
            title: "Codebase Memory",
            summary: "Architecture decisions, migrations, verification, and handoffs.",
            body: codebaseMemoryBody,
            origin: .builtIn
        ),
        HouseRulesPreset(
            id: "minimalist",
            title: "Minimalist / Low Token",
            summary: "The permanent safety rules in a compact prompt.",
            body: minimalistBody,
            origin: .builtIn
        )
    ]

    private static let codebaseMemoryBody = """
    Instructions for any coding assistant connected to these notes over the `unlirice` MCP server.

    **Start with focused context.** Search for `Wiki: index`; if it exists, read it and follow the relevant project hub. Otherwise search for the task, component, or decision directly. The repository, current Git state, and executable tests are authoritative when an older note disagrees with them.

    **Record durable engineering context, not a transcript.** Preserve architecture decisions and their reasons, schema or API changes, migrations, important failures, verification results, and unfinished handoffs. Update the relevant wiki hub when substantial new material changes what exists or where its authority lives.

    **Prefer continuity.** Search before writing. Append to an existing note when it already covers the topic; create a new note only for a genuinely new concept. Titles are permanent, so choose specific titles and use `[[Exact Title]]` links deliberately.

    **Identify every write.** Pass your own lowercase tool name as `source`. Never write as `janitor` or `ingest`; those identities are reserved for machine pipelines.

    **Do not make structural judgements unilaterally.** If notes duplicate or contradict one another, use `flag_for_review` and explain the evidence. Do not merge, archive, or resolve the conflict yourself. There is no delete tool; archiving is soft and reversible.

    **Exception Guardrail.** If the user asks for something that contradicts these notes, ask whether it's a one-time exception or whether the note should change. One-time → note the exception in the session; change → append the change to the relevant note.
    """

    private static let minimalistBody = """
    Instructions for assistants using the `unlirice` MCP server:

    - Search for relevant context before working; check `Wiki: index` first when it exists.
    - Search before writing. Append to an existing topic; create only when genuinely new.
    - Pass your own lowercase tool name as `source`; never use reserved `janitor` or `ingest`.
    - Titles are permanent. Use specific titles and `[[Exact Title]]` links.
    - Flag suspected duplicates or contradictions for human review; do not resolve them yourself.
    - Exception Guardrail: If user request contradicts notes, ask if one-time exception or note change.
    - Nothing is deleted. Archive is soft and reversible.
    """
}

public enum HouseRulesImportError: Error, Equatable, LocalizedError {
    case empty
    case invalidText
    case tooLarge(maximumBytes: Int)

    public var errorDescription: String? {
        switch self {
        case .empty:
            return "The selected file contains no House Rules text."
        case .invalidText:
            return "The selected file is not valid UTF-8 plain text."
        case .tooLarge(let maximumBytes):
            return "The selected file is too large. House Rules files must be smaller than \(maximumBytes / 1_000) KB."
        }
    }
}

public enum HouseRulesPresetImporter {
    public static let maximumByteCount = 200_000

    public static func makePreset(
        data: Data,
        filename: String,
        existingTitles: [String],
        id: UUID = UUID(),
        importedAt: Date = Date()
    ) throws -> HouseRulesPreset {
        guard data.count <= maximumByteCount else {
            throw HouseRulesImportError.tooLarge(maximumBytes: maximumByteCount)
        }
        guard !data.contains(0), let decoded = String(data: data, encoding: .utf8) else {
            throw HouseRulesImportError.invalidText
        }

        let body = HouseRulesRevision.normalized(decoded)
        guard !body.isEmpty else { throw HouseRulesImportError.empty }

        let sourceURL = URL(fileURLWithPath: filename)
        let proposed = sourceURL.deletingPathExtension().lastPathComponent
        let baseTitle = proposed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Imported Rules"
            : proposed

        return HouseRulesPreset(
            id: id.uuidString.lowercased(),
            title: uniqueTitle(base: baseTitle, existingTitles: existingTitles),
            summary: "Imported from \(sourceURL.lastPathComponent).",
            body: body,
            origin: .imported,
            sourceFilename: sourceURL.lastPathComponent,
            importedAt: importedAt
        )
    }

    public static func uniqueTitle(base: String, existingTitles: [String]) -> String {
        let taken = Set(existingTitles.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }

        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }
}

/// The self-describing envelope appended for every saved House Rules revision.
/// The digest lives in the note — the event log's source of truth — rather than
/// in a sidecar cache that another MCP process could silently make stale.
public enum HouseRulesRevision {
    public static let markerPrefix = "<!-- unlirice-house-rules-revision sha256:"

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

    public static func wrapped(_ body: String, at date: Date = Date()) -> String {
        let normalizedBody = normalized(body)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
        return """
        # House Rules revision — \(stamp)

        This revision supersedes every earlier House Rules revision in this note. Follow only the latest revision.

        \(normalizedBody)

        \(markerPrefix)\(digest(of: normalizedBody)) -->
        """
    }

    public static func latestDigest(in noteBody: String) -> String? {
        guard let marker = noteBody.range(of: markerPrefix, options: .backwards) else { return nil }
        let remainder = noteBody[marker.upperBound...]
        guard let end = remainder.range(of: " -->") else { return nil }
        let candidate = String(remainder[..<end.lowerBound])
        guard candidate.count == 64, candidate.allSatisfy({ $0.isHexDigit }) else { return nil }
        return candidate.lowercased()
    }

    public static func noteContainsCurrentRevision(noteBody: String, draftBody: String) -> Bool {
        let draft = normalized(draftBody)
        guard !draft.isEmpty else { return false }
        if let latest = latestDigest(in: noteBody) {
            return latest == digest(of: draft)
        }

        // Compatibility for House Rules notes saved before revision markers
        // existed. Suffix, rather than substring, means an older rule set cannot
        // appear current merely because a newer append follows it.
        return normalized(noteBody).hasSuffix(draft)
    }
}
