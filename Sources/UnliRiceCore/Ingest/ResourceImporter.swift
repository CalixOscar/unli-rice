import CryptoKit
import Foundation

/// One thing an importer found that could become a wiki entry.
///
/// Inert by construction, exactly like `JanitorProposal`: discovering a resource
/// touches nothing. `IngestRunner` is the only thing that acts on these.
public struct DiscoveredResource: Sendable, Equatable {
    /// The file to copy into `/raw`.
    public let sourceURL: URL

    /// **Stable identity for the underlying thing**, independent of its title,
    /// its path, and its contents. A session id; a document's absolute path.
    ///
    /// This is separate from `title` because titles drift and identity must not.
    /// A dry run over the real corpus proved why: a Claude session's `ai-title`
    /// is regenerated as the session grows, and the same session living in two
    /// git worktrees has two diverged `.jsonl` copies with different final
    /// titles. Matching on title turned one session into three notes with
    /// permanent, near-identical names — precisely the failure the
    /// permanent-title design exists to prevent. The runner matches on this.
    public let key: String

    /// The note title this resource will own. **Permanent** once written — but
    /// unlike `key` it is only a display name, and a later run finding a drifted
    /// title for the same `key` updates nothing and creates nothing.
    public let title: String

    /// The wiki entry: what this resource is, enough to decide whether it's the
    /// one you want, without reading it. Deliberately not the full content —
    /// that's what `/raw` is for, and a corpus where every note holds a whole
    /// transcript is one nobody can search.
    public let summary: String

    /// Applied by the runner via `tagNote`. Kept short and stable so the corpus
    /// stays filterable (AGENTS.md, "Tags are your namespace").
    public let tags: [String]

    /// When the underlying thing happened, not when it was ingested.
    public let occurredAt: Date

    public init(sourceURL: URL, key: String, title: String, summary: String, tags: [String], occurredAt: Date) {
        self.sourceURL = sourceURL
        self.key = key
        self.title = title
        self.summary = summary
        self.tags = tags
        self.occurredAt = occurredAt
    }
}

/// Carries a resource's stable identity inside the note body, so the link
/// between a note and the thing it indexes survives without a second store to
/// keep in sync with the event log. Same trick as `JanitorMarker` and
/// `RawMarker`.
enum IngestMarker {
    static func stamp(_ key: String) -> String { "[ingest:\(key)]" }

    /// The key a note was built from, or nil if it isn't an ingest index note.
    static func key(in body: String) -> String? {
        guard let start = body.range(of: "[ingest:"),
              let end = body.range(of: "]", range: start.upperBound..<body.endIndex)
        else { return nil }
        let key = String(body[start.upperBound..<end.lowerBound])
        return key.isEmpty ? nil : key
    }
}

/// A source of resources for the data lake.
///
/// Importers read. They are handed no `NoteService` and no `RawStore`, so an
/// importer cannot write a note or copy a file however it's implemented — the
/// same shape as `Janitor.scan` being a pure function, and for the same reason.
/// Adding a new pipeline means conforming to this and nothing else.
public protocol ResourceImporter {
    /// Stable, lowercase, used in run reports and as a tag prefix.
    var identifier: String { get }

    /// Human-readable, for the UI.
    var displayName: String { get }

    func discover() throws -> [DiscoveredResource]
}

/// Shared helpers for turning found text into a title and summary that will
/// still make sense in a flat list of several hundred notes.
public enum ImporterText {
    /// Collapses whitespace and truncates on a word boundary.
    public static func condense(_ text: String, limit: Int) -> String {
        let flat = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        guard let lastSpace = cut.lastIndex(of: " ") else { return String(cut) + "…" }
        return String(cut[cut.startIndex..<lastSpace]) + "…"
    }

    /// Titles are permanent, so anything that would make one ambiguous later is
    /// stripped now. `[[` in particular would turn a title into something that
    /// reads like a wiki-link in every backlink list that ever renders it.
    public static func sanitizeTitle(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned
    }

    /// A short, *deterministic* discriminator for disambiguating two resources
    /// that would otherwise claim the same permanent title.
    ///
    /// Explicitly not `hashValue`: Swift's `Hasher` is seeded randomly per
    /// process, so anything derived from it changes on every launch. A title
    /// that changes between runs is the worst possible outcome here — the runner
    /// matches resources to notes *by title*, so a drifting suffix would create
    /// a fresh permanent note for the same file forever.
    public static func stableSuffix(for input: String, length: Int = 4) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(length))
    }

    public static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        return formatter
    }()
}
