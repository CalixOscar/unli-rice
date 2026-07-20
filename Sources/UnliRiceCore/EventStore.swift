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

/// How far into the log a reader has already got, in bytes.
///
/// A byte offset is a sound cursor here *only* because the log is append-only:
/// nothing before `offset` can ever change, so a reader that has consumed the
/// first N bytes never has to look at them again. If the log ever gained
/// rewriting of any kind, this type is the first thing that breaks — which is
/// the intended alarm, not an oversight.
public struct EventStoreCursor: Sendable, Equatable {
    public var offset: UInt64

    public init(offset: UInt64 = 0) { self.offset = offset }

    public static let start = EventStoreCursor(offset: 0)
}

/// Events read since a cursor, plus where to resume.
public struct EventBatch: Sendable {
    public let events: [Event]
    public let cursor: EventStoreCursor

    /// The file was *shorter* than the cursor — it was replaced, truncated, or
    /// swapped underneath us. `events` is then the whole log from byte zero, and
    /// the caller must throw away anything it derived from earlier reads rather
    /// than folding this batch onto it. Silently folding would produce a
    /// projection that matches no version of the file that ever existed.
    public let restarted: Bool
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
        try read(from: .start).events
    }

    /// Everything appended since `cursor`, and a cursor to resume from.
    ///
    /// This is what makes an incremental projection possible: `NoteService` used
    /// to decode and fold the entire log on *every* read, which is O(n) per call
    /// over a corpus that ingest can grow by 40 notes in one click. Reading only
    /// the new bytes turns the steady state into "stat the file, find nothing
    /// new, return the cache".
    ///
    /// Two things it is careful about, both because other processes write this
    /// file concurrently:
    ///
    /// - It takes a **shared** `flock`, so it can never observe a line that
    ///   `append` is halfway through writing.
    /// - It still stops at the last newline and reports the cursor *there*, not
    ///   at EOF. A writer that isn't using this class (a shell redirect, an
    ///   editor) can leave a partial trailing line, and a cursor past it would
    ///   skip the rest of that event forever once it landed.
    public func read(from cursor: EventStoreCursor) throws -> EventBatch {
        try queue.sync {
            let fd = open(fileURL.path, O_RDONLY)
            guard fd >= 0 else { throw EventStoreError.fileUnavailable }
            defer { close(fd) }

            guard flock(fd, LOCK_SH) == 0 else { throw EventStoreError.fileUnavailable }
            defer { flock(fd, LOCK_UN) }

            let end = lseek(fd, 0, SEEK_END)
            guard end >= 0 else { throw EventStoreError.fileUnavailable }

            var start = cursor.offset
            var restarted = false
            if UInt64(end) < start {
                start = 0
                restarted = true
            }
            guard UInt64(end) > start else {
                return EventBatch(events: [], cursor: EventStoreCursor(offset: start), restarted: restarted)
            }

            lseek(fd, off_t(start), SEEK_SET)
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            let data = handle.readData(ofLength: Int(UInt64(end) - start))

            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
                // Nothing but a partial line so far. Leave the cursor where it
                // was so the whole line is read once it's terminated.
                return EventBatch(events: [], cursor: EventStoreCursor(offset: start), restarted: restarted)
            }

            let complete = data[data.startIndex...lastNewline]
            let events = complete
                .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
                .compactMap { try? decoder.decode(Event.self, from: Data($0)) }

            return EventBatch(
                events: events,
                cursor: EventStoreCursor(offset: start + UInt64(complete.count)),
                restarted: restarted
            )
        }
    }
}
