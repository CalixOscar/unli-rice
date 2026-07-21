import Darwin
import Foundation

public struct HouseRulesLocalState: Codable, Equatable, Sendable {
    public var draftText: String?
    public var customPresets: [HouseRulesPreset]
    public var houseRulesNoteID: UUID?

    public init(
        draftText: String? = nil,
        customPresets: [HouseRulesPreset] = [],
        houseRulesNoteID: UUID? = nil
    ) {
        self.draftText = draftText
        self.customPresets = customPresets
        self.houseRulesNoteID = houseRulesNoteID
    }
}

public enum HouseRulesStateError: Error, LocalizedError {
    case unreadable
    case unsupportedVersion(Int)
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unreadable:
            return "The saved House Rules drafts could not be read. The file was left untouched."
        case .unsupportedVersion(let version):
            return "The saved House Rules drafts use unsupported format version \(version). The file was left untouched."
        case .unavailable:
            return "The House Rules state file is unavailable."
        }
    }
}

/// Small corpus-scoped state beside `events.jsonl`.
///
/// Unlike notices, drafts and imported presets are user-created, so decode
/// failures are surfaced and an unreadable file is never replaced with an
/// empty one. A separate lock file keeps the lock stable across atomic renames.
public final class HouseRulesStateStore: @unchecked Sendable {
    public static let filename = "house-rules.json"
    public static let currentVersion = 1

    private struct Envelope: Codable {
        var version: Int
        var state: HouseRulesLocalState
    }

    public let fileURL: URL
    private let lockURL: URL
    private let queue = DispatchQueue(label: "com.unlirice.house-rules-state")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        lockURL = fileURL.deletingLastPathComponent().appendingPathComponent("house-rules.lock")
    }

    public static func url(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent(filename)
    }

    public convenience init(besideEventLog eventLog: URL) {
        self.init(fileURL: Self.url(besideEventLog: eventLog))
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    public func load() throws -> HouseRulesLocalState {
        try queue.sync {
            try withLock(LOCK_SH) {
                guard FileManager.default.fileExists(atPath: fileURL.path) else {
                    return HouseRulesLocalState()
                }
                return try decodeExisting()
            }
        }
    }

    public func save(_ state: HouseRulesLocalState) throws {
        try queue.sync {
            try withLock(LOCK_EX) {
                // Never turn a corrupt or newer-version file into an empty one.
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    _ = try decodeExisting()
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(Envelope(version: Self.currentVersion, state: state))
                try data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func decodeExisting() throws -> HouseRulesLocalState {
        guard let data = try? Data(contentsOf: fileURL) else {
            throw HouseRulesStateError.unavailable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else {
            throw HouseRulesStateError.unreadable
        }
        guard envelope.version == Self.currentVersion else {
            throw HouseRulesStateError.unsupportedVersion(envelope.version)
        }
        return envelope.state
    }

    private func withLock<T>(_ operation: Int32, body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0, flock(fd, operation) == 0 else {
            if fd >= 0 { close(fd) }
            throw HouseRulesStateError.unavailable
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try body()
    }
}
