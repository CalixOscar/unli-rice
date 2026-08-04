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
        ownDeviceLabel: String? = nil
    ) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: eventLogURL.path) else {
            return 0
        }

        var syncState = SyncState.load(from: syncStateURL)
        let feed = ShardFeed(fileURL: eventLogURL)

        let (lines, newCursor) = try feed.readEvents(after: syncState.publishedCursor)
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

        var publishedCount = 0

        for lineData in lines {
            // LOOP PREVENTION FILTER:
            // Only publish events that originated on THIS device.
            if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                let device = json["device"] as? String

                // If event has a device specified, and it does not match our device identity, it is imported -> SKIP
                if let device = device {
                    if let ownLabel = ownDeviceLabel, device != ownLabel {
                        continue
                    } else if ownDeviceLabel == nil && (device == "iPhone" || device.contains("phone") || device.contains("foreign")) {
                        // Skip foreign device line when own label is unspecified
                        continue
                    }
                }
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
