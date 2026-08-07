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

    /// A kind written by a build newer than this one.
    ///
    /// Without this case, decoding such an event *throws* — and since
    /// `EventStore.read` decodes with `try?`, the line would be silently
    /// dropped while the cursor moved past it. On a single-writer log that could
    /// never happen; once a second device writes the same corpus it becomes a
    /// permanent, unrecoverable data loss the moment the two builds drift.
    ///
    /// Decoding to this case keeps the event readable and skippable. Note the
    /// original spelling is *not* preserved through a re-encode, which is why
    /// importers must carry foreign lines across with `EventStore.appendRaw`
    /// rather than decoding and re-encoding them.
    case unrecognized

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventKind(rawValue: raw) ?? .unrecognized
    }
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

    /// Which device wrote this, when that isn't the machine holding the log.
    ///
    /// Deliberately separate from `source`, which is *agent* identity — "claude",
    /// "ingest", "janitor", "human" — and which fans out into `Note.creator`,
    /// `sources`, `editors`, and the retrospective's contributor stats. A phone
    /// capture is still written by `human`; recording it as `source: "ios"`
    /// would credit a device for what the user dictated and split their own
    /// contribution history across two identities, permanently, because events
    /// are immutable.
    ///
    /// Optional so old lines decode in new builds and new lines decode in old
    /// ones — the only extension shape that is safe in both directions.
    public var device: String?

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
        relatedEventId: UUID? = nil,
        device: String? = nil
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
        self.device = device
    }
}
