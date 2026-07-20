import Foundation

/// A flag raised by an agent (or a future MLX janitor) noting a possible structural
/// issue — a duplicate, a conflict between two agents' notes, a stale section.
/// Raising a flag never changes the note itself; it only queues something for a
/// human to look at and resolve.
public struct ReviewFlag: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let source: String
    public let reason: String
    public let timestamp: Date
    public var resolved: Bool

    public init(id: UUID, source: String, reason: String, timestamp: Date, resolved: Bool = false) {
        self.id = id
        self.source = source
        self.reason = reason
        self.timestamp = timestamp
        self.resolved = resolved
    }
}

/// The current, human/agent-facing view of a note. This is a *projection* — derived
/// entirely from the event log at read time and safe to throw away and rebuild.
public struct Note: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var body: String
    public var tags: Set<String>
    public var sources: Set<String>
    /// The source that wrote the `.created` event — who started this note, as
    /// opposed to `sources`, which is everyone who has since touched it.
    ///
    /// Kept separately because a set cannot answer "who wrote it": once the
    /// janitor tags a note or a second agent appends to it, the author is
    /// indistinguishable from the editors. Empty only for a note built by hand
    /// in a test.
    public var creator: String
    /// Everyone who changed this note without having written it — appends,
    /// tags, archiving, review flags. Disjoint from `creator` by construction.
    public var editors: Set<String>
    public var createdAt: Date
    public var updatedAt: Date
    public var archived: Bool
    public var flags: [ReviewFlag]

    /// Notes this one points at via `[[...]]`, and notes pointing back at it.
    /// Both are derived by `Projector` from body text on every projection — see
    /// `WikiLink`. Nothing here is ever written to the event log.
    public var outboundLinks: Set<UUID>
    public var backlinks: Set<UUID>

    /// `[[targets]]` in this note's body that match no existing note. Kept so the
    /// UI can show a link as unresolved instead of silently dropping it.
    public var danglingLinks: Set<String>

    public init(
        id: UUID,
        title: String,
        body: String,
        tags: Set<String> = [],
        sources: Set<String> = [],
        creator: String = "",
        editors: Set<String> = [],
        createdAt: Date,
        updatedAt: Date,
        archived: Bool = false,
        flags: [ReviewFlag] = [],
        outboundLinks: Set<UUID> = [],
        backlinks: Set<UUID> = [],
        danglingLinks: Set<String> = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.sources = sources
        self.creator = creator
        self.editors = editors
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
        self.flags = flags
        self.outboundLinks = outboundLinks
        self.backlinks = backlinks
        self.danglingLinks = danglingLinks
    }
}
