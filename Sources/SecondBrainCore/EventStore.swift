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
    private let queue = DispatchQueue(label: "com.secondbrain.eventstore")
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

    public func append(_ event: Event) throws {
        try queue.sync {
            let data = try encoder.encode(event)
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write("\n".data(using: .utf8)!)
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
