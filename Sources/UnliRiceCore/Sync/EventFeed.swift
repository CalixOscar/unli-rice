import Foundation

/// Opaque position marker for an event feed.
public struct FeedCursor: Codable, Equatable, Hashable, Sendable {
    public let opaque: String

    public init(opaque: String) {
        self.opaque = opaque
    }

    public init(offset: UInt64) {
        self.opaque = String(offset)
    }

    public var offset: UInt64? {
        UInt64(opaque)
    }
}

/// Abstract feed of raw event lines.
public protocol EventFeed: Sendable {
    /// Reads new raw event line data after the given cursor.
    ///
    /// Returns the raw byte arrays for each complete event line and an updated
    /// cursor pointing to the position after the last complete, valid line.
    func readEvents(after cursor: FeedCursor?) throws -> (events: [Data], newCursor: FeedCursor)
}
