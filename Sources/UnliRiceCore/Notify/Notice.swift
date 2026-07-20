import Foundation

/// Where a notice sends you when you act on it.
///
/// Deliberately a small closed enum rather than a free-form action: a notice is
/// allowed to *point at* something, never to do it. That keeps the notification
/// centre on the safe side of decision #3 — nothing in this file can consolidate
/// a duplicate or resolve a flag, it can only offer to show you the screen where
/// you'd do that yourself.
public enum NoticeDestination: Codable, Equatable, Sendable {
    case none
    case reviewQueue
    /// A `RetrospectivePeriod.id` — `2026-06` for a month, `2026` for a year.
    case retrospective(period: String)
}

/// One thing worth mentioning next time the user looks.
public struct Notice: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The janitor queued something a human has to decide.
        case review
        /// A routine ran unattended and did something.
        case routine
        /// A month (or a year) is ready to look back on.
        case retrospective
        /// Something went wrong while nobody was watching. These matter more
        /// than the rest: a pipeline that quietly stops is the failure mode this
        /// whole design is most afraid of.
        case problem
    }

    public let id: UUID
    public let timestamp: Date
    public let kind: Kind
    public let title: String
    public let detail: String
    public let destination: NoticeDestination

    /// Identity for *the situation*, not for this particular telling of it.
    ///
    /// "Three notes look like duplicates" is one fact; an agent that ticks every
    /// five minutes would otherwise report it 288 times a day and the centre
    /// would become the thing you scroll past. Posting a notice whose key
    /// matches an existing **unread** one replaces it in place — the count stays
    /// current, the pile doesn't grow. Once read, the key is free again, so the
    /// situation recurring after you've dealt with it does surface.
    public let key: String

    public var readAt: Date?

    public var isRead: Bool { readAt != nil }

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        kind: Kind,
        key: String,
        title: String,
        detail: String,
        destination: NoticeDestination = .none,
        readAt: Date? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.key = key
        self.title = title
        self.detail = detail
        self.destination = destination
        self.readAt = readAt
    }
}
