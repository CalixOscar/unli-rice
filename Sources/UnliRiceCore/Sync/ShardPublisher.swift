import Foundation

/// Mirrors locally originated events into this device's published shard file inside the shared sync folder.
///
/// Implements LOOP PREVENTION: filters out events that were imported from foreign devices so foreign events
/// never bounce back to their source or flood foreign shard feeds.
public enum ShardPublisher {
    @discardableResult
    public static func publishLocalEvents(
        eventLogURL: URL,
        to targetShardFileURL: URL,
        syncStateURL: URL,
        ownDeviceLabel: String? = nil,
        isLocallyOriginated: ((Event) -> Bool)? = nil
    ) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: eventLogURL.path) else {
            return 0
        }

        var syncState = SyncState.load(from: syncStateURL)
        let feed = ShardFeed(fileURL: eventLogURL)

        let lines: [Data]
        let newCursor: FeedCursor

        do {
            let result = try feed.readEvents(after: syncState.publishedCursor)
            lines = result.events
            newCursor = result.newCursor
        } catch ShardFeedError.shardShrunk {
            // FIX 3: Local log is not a foreign shard. When local events.jsonl shrinks (e.g. after Trash.purge),
            // rebuild the published shard from scratch to stop purged events from lingering.
            if fileManager.fileExists(atPath: targetShardFileURL.path) {
                try? fileManager.removeItem(at: targetShardFileURL)
            }
            syncState.publishedCursor = nil
            let result = try feed.readEvents(after: nil)
            lines = result.events
            newCursor = result.newCursor
        }

        guard !lines.isEmpty else {
            return 0
        }

        let targetDir = targetShardFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: targetShardFileURL.path) {
            fileManager.createFile(atPath: targetShardFileURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: targetShardFileURL)
        defer { try? handle.close() }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var publishedCount = 0

        // Ownership predicate logic:
        // Caller supplies explicit isLocallyOriginated predicate.
        // Asymmetry note: Mac passes `device == nil || device == macLabel` (legacy nil-device events originated on Mac).
        // Phone passes `device == phoneLabel` (phone never wrote a nil-device event).
        let predicate: (Event) -> Bool = isLocallyOriginated ?? { event in
            guard let ownLabel = ownDeviceLabel else {
                return event.device == nil
            }
            if ownLabel.lowercased().contains("mac") {
                return event.device == nil || event.device == ownLabel
            } else {
                return event.device == ownLabel
            }
        }

        for lineData in lines {
            guard let event = try? decoder.decode(Event.self, from: lineData) else {
                continue
            }

            // LOOP PREVENTION FILTER:
            // Only publish events that originated locally according to the ownership predicate.
            guard predicate(event) else {
                continue
            }

            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
            try handle.write(contentsOf: Data("\n".utf8))
            publishedCount += 1
        }

        syncState.publishedCursor = newCursor
        try syncState.save(to: syncStateURL)

        return publishedCount
    }
}
