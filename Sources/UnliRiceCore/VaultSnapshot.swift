import CryptoKit
import Darwin
import Foundation

/// A verified, local recovery point for one Unli Rice vault.
///
/// Snapshots deliberately live beside `events.jsonl`: changing vaults changes
/// the recovery history too. The event log is captured byte-for-byte under a
/// shared flock, then checksummed together with the raw store and the small
/// corpus-scoped sidecars. Restore never replaces the live log. It appends only
/// event IDs that are missing and copies only raw files that are absent, keeping
/// the append-only source-of-truth rule intact.
public struct VaultSnapshot: Codable, Identifiable, Equatable, Sendable {
    public struct FileRecord: Codable, Equatable, Sendable {
        public let relativePath: String
        public let byteCount: Int
        public let sha256: String

        public init(relativePath: String, byteCount: Int, sha256: String) {
            self.relativePath = relativePath
            self.byteCount = byteCount
            self.sha256 = sha256
        }
    }

    public let id: String
    public let createdAt: Date
    public let eventCount: Int
    public let noteCount: Int
    public let files: [FileRecord]

    public init(
        id: String,
        createdAt: Date,
        eventCount: Int,
        noteCount: Int,
        files: [FileRecord]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.eventCount = eventCount
        self.noteCount = noteCount
        self.files = files
    }

    public var totalByteCount: Int { files.reduce(0) { $0 + $1.byteCount } }
}

public enum VaultSnapshotService {
    public struct RestoreReceipt: Equatable, Sendable {
        public let eventsAppended: Int
        public let rawFilesRestored: Int

        public init(eventsAppended: Int, rawFilesRestored: Int) {
            self.eventsAppended = eventsAppended
            self.rawFilesRestored = rawFilesRestored
        }
    }

    public enum SnapshotError: Error, LocalizedError, Equatable {
        case eventLogUnavailable
        case invalidEventLog
        case snapshotNotFound
        case invalidManifest
        case verificationFailed(String)

        public var errorDescription: String? {
            switch self {
            case .eventLogUnavailable:
                return "The event log could not be opened."
            case .invalidEventLog:
                return "The event log contains an unreadable event, so no recovery point was created."
            case .snapshotNotFound:
                return "That recovery point no longer exists."
            case .invalidManifest:
                return "The recovery point manifest could not be read."
            case .verificationFailed(let path):
                return "Verification failed for \(path). Nothing was restored."
            }
        }
    }

    public static let directoryName = "Snapshots"
    public static let manifestFilename = "manifest.json"
    public static let eventLogFilename = "events.jsonl"

    public static func directory(forLog logURL: URL) -> URL {
        logURL.deletingLastPathComponent().appendingPathComponent(directoryName, isDirectory: true)
    }

    public static func snapshotURL(_ snapshot: VaultSnapshot, forLog logURL: URL) -> URL {
        directory(forLog: logURL).appendingPathComponent(snapshot.id, isDirectory: true)
    }

    @discardableResult
    public static func create(logURL: URL, now: Date = Date()) throws -> VaultSnapshot {
        let fileManager = FileManager.default
        let root = directory(forLog: logURL)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let id = snapshotID(now: now)
        let destination = root.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            let eventData = try readEventLogUnderLock(logURL)
            let events = try decodeEvents(eventData)
            try eventData.write(
                to: destination.appendingPathComponent(eventLogFilename),
                options: .atomic
            )

            let vaultRoot = logURL.deletingLastPathComponent()
            for filename in [HouseRulesStateStore.filename, "routine-state.json", "notices.json"] {
                let source = vaultRoot.appendingPathComponent(filename)
                guard fileManager.fileExists(atPath: source.path) else { continue }
                try fileManager.copyItem(
                    at: source,
                    to: destination.appendingPathComponent(filename)
                )
            }

            let rawSource = vaultRoot.appendingPathComponent("raw", isDirectory: true)
            if fileManager.fileExists(atPath: rawSource.path) {
                try fileManager.copyItem(
                    at: rawSource,
                    to: destination.appendingPathComponent("raw", isDirectory: true)
                )
            }

            let files = try fileRecords(in: destination)
            let snapshot = VaultSnapshot(
                id: id,
                createdAt: now,
                eventCount: events.count,
                noteCount: Set(events.filter { $0.kind == .created }.map(\.noteId)).count,
                files: files
            )
            try encode(snapshot).write(
                to: destination.appendingPathComponent(manifestFilename),
                options: .atomic
            )
            try verify(snapshot, logURL: logURL)
            return snapshot
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    public static func list(logURL: URL) -> [VaultSnapshot] {
        let root = directory(forLog: logURL)
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let manifestURL = url.appendingPathComponent(manifestFilename)
            guard let data = try? Data(contentsOf: manifestURL) else { return nil }
            return try? decodeManifest(data)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public static func verify(_ snapshot: VaultSnapshot, logURL: URL) throws {
        let root = snapshotURL(snapshot, forLog: logURL)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw SnapshotError.snapshotNotFound
        }

        for record in snapshot.files {
            let url = root.appendingPathComponent(record.relativePath)
            guard let data = try? Data(contentsOf: url),
                  data.count == record.byteCount,
                  digest(data) == record.sha256
            else {
                throw SnapshotError.verificationFailed(record.relativePath)
            }
        }
    }

    /// Restores recoverable content without replacing anything live.
    ///
    /// Event identity makes a merge deterministic: an event already present is
    /// skipped, while a missing event is appended in its original snapshot
    /// order. Raw resources are content-addressed and similarly copied only when
    /// the destination does not exist. Sidecars stay in the snapshot for manual
    /// recovery because overwriting current settings or notices would be a
    /// different, surprising operation.
    @discardableResult
    public static func restore(
        _ snapshot: VaultSnapshot,
        logURL: URL,
        into store: EventStore
    ) throws -> RestoreReceipt {
        try verify(snapshot, logURL: logURL)
        let snapshotRoot = snapshotURL(snapshot, forLog: logURL)
        let snapshotEvents = try decodeEvents(
            Data(contentsOf: snapshotRoot.appendingPathComponent(eventLogFilename))
        )
        let existingIDs = Set(try store.readAll().map(\.id))
        var appended = 0
        var seen = existingIDs
        for event in snapshotEvents where seen.insert(event.id).inserted {
            try store.append(event)
            appended += 1
        }

        let restoredRaw = try restoreMissingRawFiles(
            from: snapshotRoot.appendingPathComponent("raw", isDirectory: true),
            to: logURL.deletingLastPathComponent().appendingPathComponent("raw", isDirectory: true)
        )
        return RestoreReceipt(eventsAppended: appended, rawFilesRestored: restoredRaw)
    }

    private static func restoreMissingRawFiles(from source: URL, to destination: URL) throws -> Int {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return 0 }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let normalizedSource = source.resolvingSymlinksInPath()
        let normalizedDestination = destination.resolvingSymlinksInPath()

        guard let enumerator = fileManager.enumerator(
            at: normalizedSource,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var restored = 0
        for case let url as URL in enumerator {
            let relative = relativePath(of: url, under: normalizedSource)
            let target = normalizedDestination.appendingPathComponent(relative)
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            } else if !fileManager.fileExists(atPath: target.path) {
                try fileManager.createDirectory(
                    at: target.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: url, to: target)
                restored += 1
            }
        }
        return restored
    }

    private static func readEventLogUnderLock(_ url: URL) throws -> Data {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw SnapshotError.eventLogUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_SH) == 0 else { throw SnapshotError.eventLogUnavailable }
        defer { flock(fd, LOCK_UN) }
        return try Data(contentsOf: url)
    }

    private static func decodeEvents(_ data: Data) throws -> [Event] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var events: [Event] = []
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            guard let event = try? decoder.decode(Event.self, from: Data(line)) else {
                throw SnapshotError.invalidEventLog
            }
            events.append(event)
        }
        return events
    }

    private static func fileRecords(in root: URL) throws -> [VaultSnapshot.FileRecord] {
        let normalizedRoot = root.resolvingSymlinksInPath()
        guard let enumerator = FileManager.default.enumerator(
            at: normalizedRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [VaultSnapshot.FileRecord] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, url.lastPathComponent != manifestFilename else { continue }
            let data = try Data(contentsOf: url)
            let relative = relativePath(of: url, under: normalizedRoot)
            records.append(.init(relativePath: relative, byteCount: data.count, sha256: digest(data)))
        }
        return records.sorted { $0.relativePath < $1.relativePath }
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootComponents = root.standardizedFileURL.pathComponents
        let components = url.standardizedFileURL.pathComponents
        return components.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func encode(_ snapshot: VaultSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    private static func decodeManifest(_ data: Data) throws -> VaultSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(VaultSnapshot.self, from: data) else {
            throw SnapshotError.invalidManifest
        }
        return snapshot
    }

    private static func snapshotID(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "vault-\(formatter.string(from: now))-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
