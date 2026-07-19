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
public struct Note: Codable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var body: String
    public var tags: Set<String>
    public var sources: Set<String>
    public var createdAt: Date
    public var updatedAt: Date
    public var archived: Bool
    public var flags: [ReviewFlag]

    public init(
        id: UUID,
        title: String,
        body: String,
        tags: Set<String> = [],
        sources: Set<String> = [],
        createdAt: Date,
        updatedAt: Date,
        archived: Bool = false,
        flags: [ReviewFlag] = []
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.sources = sources
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archived = archived
        self.flags = flags
    }
}
