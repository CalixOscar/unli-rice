import Darwin
import Foundation

public enum EventStoreError: Error, CustomStringConvertible {
    case encodingFailed
    case fileUnavailable

    public var description: String {
        switch self {
        case .encodingFailed: return "Failed to encode event"
        case .fileUnavailable: return "Event log file is unavailable"
        }
    }
}

/// Append-only JSON-Lines store. This is the source of truth for the whole app:
/// one line per Event, never rewritten, never truncated. `append` is the only
/// write primitive it exposes — there is no update or delete on the log itself,
/// which is what makes every derived action (tags, archiving, projections)
/// reversible by construction. See PROJECT_NOTES.md.
public final class EventStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.unlirice.eventstore")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Appends one line, holding an exclusive `flock` for the duration.
    ///
    /// This file is meant to be written by several independent MCP client
    /// *processes* at once — Claude Code, Codex, Antigravity, or anything
    /// else, each running its own copy of unlirice-mcp against the same
    /// events.jsonl. The `queue` above only serializes writers within this
    /// one process; it does nothing for a second process racing the same
    /// file. `flock` is what actually stops two processes from both seeking
    /// to the same end-of-file offset and interleaving their writes — a real
    /// bug this method used to have (seekToEndOfFile + a bare FileHandle,
    /// with no OS-level lock at all).
    public func append(_ event: Event) throws {
        try queue.sync {
            var payload = try encoder.encode(event)
            payload.append(UInt8(ascii: "\n"))

            let fd = open(fileURL.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
            guard fd >= 0 else { throw EventStoreError.fileUnavailable }
            defer { close(fd) }

            guard flock(fd, LOCK_EX) == 0 else { throw EventStoreError.fileUnavailable }
            defer { flock(fd, LOCK_UN) }

            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            handle.write(payload)
        }
    }

    public func readAll() throws -> [Event] {
        try queue.sync {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            return content
                .split(separator: "\n")
                .compactMap { line -> Event? in
                    guard let data = line.data(using: .utf8) else { return nil }
                    return try? decoder.decode(Event.self, from: data)
                }
        }
    }
}
