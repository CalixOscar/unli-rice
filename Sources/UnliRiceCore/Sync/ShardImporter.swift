import Foundation

/// Receipt for a shard import run.
public struct ImportReceipt: Equatable, Sendable {
    public let eventsAppended: Int
    public let shardsImported: Int

    public init(eventsAppended: Int, shardsImported: Int) {
        self.eventsAppended = eventsAppended
        self.shardsImported = shardsImported
    }
}

/// Importer for foreign device event shards (`events-<deviceUUID>.jsonl`).
///
/// Modeled on `VaultSnapshot.swift:193-216`. Reads foreign shards, deduplicates
/// event IDs against the local log, and appends foreign lines verbatim using
/// `store.appendRaw(_:)`. Persists byte cursors in `sync-state.json` to prevent
/// resurrected purged notes.
public enum ShardImporter {
    /// The naming convention every published shard follows. Required when
    /// importing from a folder that is not a dedicated `shards/` directory —
    /// a user's sync folder or scan root can hold unrelated `.jsonl` files
    /// (Claude session logs, eval fixtures, exports) and appending those to the
    /// event log as if they were events is unrecoverable: the log is immutable.
    public static let shardFilenamePrefix = "events-"

    @discardableResult
    public static func importShards(
        from shardDirectory: URL,
        into store: EventStore,
        syncStateURL: URL,
        ownShardFilename: String? = nil,
        requiringShardNaming: Bool = false,
        cursorNamespace: String? = nil
    ) throws -> ImportReceipt {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: shardDirectory.path) else {
            return ImportReceipt(eventsAppended: 0, shardsImported: 0)
        }

        let shardFiles = try fileManager.contentsOfDirectory(
            at: shardDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.pathExtension == "jsonl" else { return false }
            if let ownShardFilename, url.lastPathComponent == ownShardFilename { return false }
            if requiringShardNaming, !url.lastPathComponent.hasPrefix(shardFilenamePrefix) { return false }
            return true
        }

        guard !shardFiles.isEmpty else {
            return ImportReceipt(eventsAppended: 0, shardsImported: 0)
        }

        var syncState = SyncState.load(from: syncStateURL)
        let existingIDs = Set(try store.readAll().map(\.id))
        var seenIDs = existingIDs

        var totalAppended = 0
        var shardsImportedCount = 0

        for shardURL in shardFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Cursors are keyed by filename, which is unique per device but not
            // per *location*. Once the same log imports from more than one
            // folder, two folders holding a same-named shard would share — and
            // fight over — one byte offset, so those keys get namespaced.
            let shardID = cursorNamespace.map { "\($0)/\(shardURL.lastPathComponent)" }
                ?? shardURL.lastPathComponent
            let feed = ShardFeed(fileURL: shardURL)
            let previousCursor = syncState.cursor(for: shardID)

            let (eventLines, newCursor) = try feed.readEvents(after: previousCursor)
            shardsImportedCount += 1

            for lineData in eventLines {
                guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let idString = json["id"] as? String,
                      let eventID = UUID(uuidString: idString)
                else {
                    continue
                }

                if seenIDs.insert(eventID).inserted {
                    try store.appendRaw(lineData)
                    totalAppended += 1
                }
            }

            syncState.updateCursor(for: shardID, to: newCursor)
        }

        try syncState.save(to: syncStateURL)
        return ImportReceipt(eventsAppended: totalAppended, shardsImported: shardsImportedCount)
    }

    /// Convenience wrapper using default location paths beside event log.
    @discardableResult
    public static func importShards(
        besideEventLog eventLog: URL,
        into store: EventStore,
        ownShardFilename: String? = nil
    ) throws -> ImportReceipt {
        let shardDirectory = DataLocation.shardDirectory(besideEventLog: eventLog)
        let syncStateURL = SyncState.url(besideEventLog: eventLog)
        return try importShards(
            from: shardDirectory,
            into: store,
            syncStateURL: syncStateURL,
            ownShardFilename: ownShardFilename
        )
    }
}
