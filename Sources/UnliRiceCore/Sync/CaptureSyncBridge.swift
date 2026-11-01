import Foundation
import CryptoKit
import Darwin

public enum CaptureSyncBridge {
    public struct Result: Equatable, Sendable {
        public let eventsImported: Int
        public let eventsPublished: Int
    }
    public enum BridgeError: Error, LocalizedError {
        case lockUnavailable, corruptState, corruptShard
        public var errorDescription: String? {
            switch self {
            case .lockUnavailable: return "Capture sync lock is unavailable."
            case .corruptState: return "Capture sync state is unreadable; cursors were preserved."
            case .corruptShard: return "A capture event feed is malformed; it was left untouched."
            }
        }
    }
    /// Non-reentrant: callers must never nest this lock. A busy sync fails after two seconds and may be retried.
    public static func withLock<T>(eventLogURL: URL, _ body: () throws -> T) throws -> T {
        let lockURL = eventLogURL.deletingLastPathComponent().appendingPathComponent(".capture-sync.lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw BridgeError.lockUnavailable }
        defer { close(descriptor) }
        let deadline = ContinuousClock.now + .seconds(2)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN, ContinuousClock.now < deadline else {
                throw BridgeError.lockUnavailable
            }
            usleep(10_000)
        }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
    private static func validateFeeds(in folder: URL, ownShardFilename: String?, requiringShardNaming: Bool) throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "jsonl" && $0.lastPathComponent != ownShardFilename && (!requiringShardNaming || $0.lastPathComponent.hasPrefix("events-")) }
        for file in files {
            let data = try Data(contentsOf: file)
            guard let last = data.lastIndex(of: 10) else { continue }
            for line in data[...last].split(separator: 10) where !line.isEmpty {
                guard (try? decoder.decode(Event.self, from: Data(line))) != nil else { throw BridgeError.corruptShard }
            }
        }
    }
    public static func importOnly(eventLogURL: URL, from folder: URL, ownShardFilename: String?,
                                  cursorNamespace: String?, requiringShardNaming: Bool = true) throws -> ImportReceipt {
        try withLock(eventLogURL: eventLogURL) {
            let stateURL = SyncState.url(besideEventLog: eventLogURL)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                guard let data = try? Data(contentsOf: stateURL), (try? JSONDecoder().decode(SyncState.self, from: data)) != nil else { throw BridgeError.corruptState }
            }
            try validateFeeds(in: folder, ownShardFilename: ownShardFilename, requiringShardNaming: requiringShardNaming)
            return try ShardImporter.importShards(from: folder, into: EventStore(fileURL: eventLogURL), syncStateURL: stateURL,
                ownShardFilename: ownShardFilename, requiringShardNaming: requiringShardNaming, cursorNamespace: cursorNamespace)
        }
    }
    public static func synchronize(eventLogURL: URL, sharedFolder: URL, identity: DeviceIdentity) throws -> Result {
        try withLock(eventLogURL: eventLogURL) {
        let directory = eventLogURL.deletingLastPathComponent()
        let fm = FileManager.default
        let stateURL = SyncState.url(besideEventLog: eventLogURL)
        let hash = SHA256.hash(data: Data(sharedFolder.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let exportStateURL = directory.appendingPathComponent("sync-export-\(hash).json")
        func checkedState(_ url: URL) throws -> SyncState {
            guard fm.fileExists(atPath: url.path) else { return SyncState() }
            guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(SyncState.self, from: data) else { throw BridgeError.corruptState }
            return state
        }
        _ = try checkedState(stateURL)
        var exportState = try checkedState(exportStateURL)
        let ownName = "events-mac-\(identity.id).jsonl"
        let target = sharedFolder.appendingPathComponent(ownName)
        // Validate complete records before the importer can advance any cursor.
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let files = try fm.contentsOfDirectory(at: sharedFolder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" && $0.lastPathComponent != ownName }
        for file in files + (fm.fileExists(atPath: eventLogURL.path) ? [eventLogURL] : []) {
            let data = try Data(contentsOf: file)
            guard let last = data.lastIndex(of: 10) else { continue }
            for line in data[...last].split(separator: 10) where !line.isEmpty {
                guard (try? decoder.decode(Event.self, from: Data(line))) != nil else { throw BridgeError.corruptShard }
            }
        }
        // ShardPublisher otherwise rebuilds the destination when the local source shrinks.
        if let cursor = exportState.publishedCursor {
            _ = try ShardFeed(fileURL: eventLogURL).readEvents(after: cursor)
        }
        let store = try EventStore(fileURL: eventLogURL)
        let receipt = try ShardImporter.importShards(from: sharedFolder, into: store, syncStateURL: stateURL,
            ownShardFilename: ownName, requiringShardNaming: true, cursorNamespace: sharedFolder.path)
        if !fm.fileExists(atPath: target.path), exportState.publishedCursor != nil {
            exportState.publishedCursor = nil
            try exportState.save(to: exportStateURL)
        }
        let published = try ShardPublisher.publishLocalEvents(eventLogURL: eventLogURL, to: target,
            syncStateURL: exportStateURL, ownDeviceLabel: identity.label,
            isLocallyOriginated: { $0.device == nil || $0.device == identity.label })
        let service = NoteService(store: store, deviceLabel: identity.label)
        let ids = try service.listNotes(includeArchived: true).filter(CaptureContext.isCapture)
            .sorted { $0.updatedAt > $1.updatedAt }.prefix(2000).map(\.id)
        try CaptureReceiptFile(deviceLabel: identity.label, receivedNoteIDs: ids).write(toFolder: sharedFolder, deviceID: identity.id)
        return Result(eventsImported: receipt.eventsAppended, eventsPublished: published)
        }
    }
}
