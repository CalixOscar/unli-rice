import Darwin
import Foundation

/// Local, content-free evidence that an MCP client reached this vault.
///
/// This is intentionally not part of `events.jsonl`: connection activity is
/// operational status, not user memory, and can be discarded without losing a
/// note. No tool arguments or note contents are recorded—only client identity,
/// timestamps, tool name, and success/failure.
public struct MCPConnectionActivity: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public var clientName: String
    public var clientVersion: String?
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var lastToolName: String?
    public var lastToolCallAt: Date?
    public var lastToolSucceeded: Bool?

    public init(
        id: String,
        clientName: String,
        clientVersion: String? = nil,
        firstSeenAt: Date,
        lastSeenAt: Date,
        lastToolName: String? = nil,
        lastToolCallAt: Date? = nil,
        lastToolSucceeded: Bool? = nil
    ) {
        self.id = id
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.lastToolName = lastToolName
        self.lastToolCallAt = lastToolCallAt
        self.lastToolSucceeded = lastToolSucceeded
    }
}

public final class MCPConnectionActivityStore: @unchecked Sendable {
    public enum StoreError: Error, LocalizedError {
        case unavailable
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .unavailable: return "Connection activity could not be saved."
            case .unreadable: return "Connection activity could not be read."
            }
        }
    }

    private struct Envelope: Codable {
        let version: Int
        var clients: [MCPConnectionActivity]
    }

    public static let filename = "connections.json"
    public static let currentVersion = 1

    public let fileURL: URL
    private let lockURL: URL
    private let queue = DispatchQueue(label: "com.unlirice.connection-activity")

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.lockURL = fileURL.deletingLastPathComponent().appendingPathComponent("connections.lock")
    }

    public convenience init(besideEventLog eventLogURL: URL) {
        self.init(fileURL: eventLogURL.deletingLastPathComponent().appendingPathComponent(Self.filename))
    }

    public func list() throws -> [MCPConnectionActivity] {
        try queue.sync {
            try withLock(LOCK_SH) {
                try load().sorted { $0.lastSeenAt > $1.lastSeenAt }
            }
        }
    }

    @discardableResult
    public func recordConnection(
        clientName: String,
        clientVersion: String?,
        at date: Date = Date()
    ) throws -> MCPConnectionActivity {
        try mutate(clientName: clientName, clientVersion: clientVersion, at: date) { activity in
            activity.lastSeenAt = date
        }
    }

    @discardableResult
    public func recordToolCall(
        clientName: String,
        clientVersion: String?,
        toolName: String,
        succeeded: Bool,
        at date: Date = Date()
    ) throws -> MCPConnectionActivity {
        try mutate(clientName: clientName, clientVersion: clientVersion, at: date) { activity in
            activity.lastSeenAt = date
            activity.lastToolName = toolName
            activity.lastToolCallAt = date
            activity.lastToolSucceeded = succeeded
        }
    }

    private func mutate(
        clientName: String,
        clientVersion: String?,
        at date: Date,
        change: (inout MCPConnectionActivity) -> Void
    ) throws -> MCPConnectionActivity {
        try queue.sync {
            try withLock(LOCK_EX) {
                var clients = try load()
                let id = Self.identity(name: clientName, version: clientVersion)
                let index: Int
                if let existing = clients.firstIndex(where: { $0.id == id }) {
                    index = existing
                } else {
                    clients.append(MCPConnectionActivity(
                        id: id,
                        clientName: clientName,
                        clientVersion: clientVersion,
                        firstSeenAt: date,
                        lastSeenAt: date
                    ))
                    index = clients.count - 1
                }
                change(&clients[index])
                let updated = clients[index]
                clients = Array(clients.sorted { $0.lastSeenAt > $1.lastSeenAt }.prefix(50))
                try save(clients)
                return updated
            }
        }
    }

    private func load() throws -> [MCPConnectionActivity] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        guard let data = try? Data(contentsOf: fileURL) else { throw StoreError.unavailable }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.version == Self.currentVersion
        else { throw StoreError.unreadable }
        return envelope.clients
    }

    private func save(_ clients: [MCPConnectionActivity]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Envelope(version: Self.currentVersion, clients: clients)) else {
            throw StoreError.unavailable
        }
        try data.write(to: fileURL, options: .atomic)
    }

    private func withLock<T>(_ operation: Int32, body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0, flock(fd, operation) == 0 else {
            if fd >= 0 { close(fd) }
            throw StoreError.unavailable
        }
        defer {
            flock(fd, LOCK_UN)
            close(fd)
        }
        return try body()
    }

    private static func identity(name: String, version: String?) -> String {
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleanedName.isEmpty ? "Unknown MCP client" : cleanedName
        return version.map { "\(normalized)|\($0)" } ?? normalized
    }
}
