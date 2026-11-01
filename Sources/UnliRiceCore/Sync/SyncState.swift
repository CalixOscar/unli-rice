import Foundation

/// Persisted sync state tracking the read cursors for foreign event feeds.
///
/// Saved beside the event log (`sync-state.json`) so sync progress moves
/// with the vault data.
public struct SyncState: Codable, Equatable, Sendable {
    /// Keyed by shard identifier (e.g. filename or device UUID).
    public var shardCursors: [String: FeedCursor]
    /// Byte offset of local events.jsonl that has been published to own shard log.
    public var publishedCursor: FeedCursor?
    public var scopedImportCursorsVersion: Int?

    public init(shardCursors: [String: FeedCursor] = [:], publishedCursor: FeedCursor? = nil, scopedImportCursorsVersion: Int? = nil) {
        self.shardCursors = shardCursors
        self.publishedCursor = publishedCursor
        self.scopedImportCursorsVersion = scopedImportCursorsVersion
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

    public enum ScopedImportError: Error, LocalizedError, Equatable {
        case unreadableState, unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .unreadableState: return "Sync state could not be read; existing cursors were preserved."
            case .unsupportedVersion(let version): return "Unsupported scoped import version \(version)."
            }
        }
    }

    /// Adopt legacy offsets only for the folder active before switching. Never rewind
    /// an import or change the publication cursor; retain legacy keys for older clients.
    public static func prepareScopedImports(at stateURL: URL, currentNamespace: String?) throws {
        var state: SyncState
        if FileManager.default.fileExists(atPath: stateURL.path) {
            do { state = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: stateURL)) }
            catch { throw ScopedImportError.unreadableState }
        } else { state = SyncState() }
        if let version = state.scopedImportCursorsVersion {
            guard version == 1 else { throw ScopedImportError.unsupportedVersion(version) }
            return
        }
        if let namespace = currentNamespace {
            for (key, cursor) in state.shardCursors where !key.contains("/") && key.hasSuffix(".jsonl") {
                let scoped = "\(namespace)/\(key)"
                if state.shardCursors[scoped] == nil { state.shardCursors[scoped] = cursor }
            }
        }
        state.scopedImportCursorsVersion = 1
        try state.save(to: stateURL)
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
