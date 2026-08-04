import Foundation

/// Persisted sync state tracking the read cursors for foreign event feeds.
///
/// Saved beside the event log (`sync-state.json`) so sync progress moves
/// with the vault data.
public struct SyncState: Codable, Equatable, Sendable {
    /// Keyed by shard identifier (e.g. filename or device UUID).
    public var shardCursors: [String: FeedCursor]

    public init(shardCursors: [String: FeedCursor] = [:]) {
        self.shardCursors = shardCursors
    }

    public func cursor(for shardID: String) -> FeedCursor? {
        shardCursors[shardID]
    }

    public mutating func updateCursor(for shardID: String, to cursor: FeedCursor) {
        shardCursors[shardID] = cursor
    }

    // MARK: - Persistence

    public static func url(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent("sync-state.json")
    }

    public static func load(from url: URL) -> SyncState {
        guard let data = try? Data(contentsOf: url) else { return SyncState() }
        let decoder = JSONDecoder()
        return (try? decoder.decode(SyncState.self, from: data)) ?? SyncState()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
