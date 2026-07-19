import Foundation

/// The full set of things that can happen to a note. Deliberately, there is no
/// `.deleted` case — see PROJECT_NOTES.md for why permanent deletion is never
/// something an agent can express through this log.
public enum EventKind: String, Codable, Sendable {
    case created
    case appended
    case tagged
    case untagged
    case archived
    case unarchived
    case flagged
    case reviewResolved
}

/// A single immutable fact appended to the event log. Notes are never edited or
/// deleted in place — every change, from any agent, is a new Event. Current note
/// state is always a projection over the full event history (see Projector).
public struct Event: Codable, Sendable, Identifiable {
    public let id: UUID
    public let noteId: UUID
    public let timestamp: Date
    public let source: String
    public let kind: EventKind
    public var title: String?
    public var text: String?
    public var tag: String?
    public var reason: String?
    public var relatedEventId: UUID?

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        timestamp: Date = Date(),
        source: String,
        kind: EventKind,
        title: String? = nil,
        text: String? = nil,
        tag: String? = nil,
        reason: String? = nil,
        relatedEventId: UUID? = nil
    ) {
        self.id = id
        self.noteId = noteId
        self.timestamp = timestamp
        self.source = source
        self.kind = kind
        self.title = title
        self.text = text
        self.tag = tag
        self.reason = reason
        self.relatedEventId = relatedEventId
    }
}
