import Darwin
import Foundation

public enum EventStoreError: Error, CustomStringConvertible, LocalizedError {
    case encodingFailed
    case fileUnavailable
    case invalidHistory
    case tooManyParents
    case causalOrderingUnavailable
    case nativeRecordTooLarge

    public var errorDescription: String? { description }
    public var description: String {
        switch self {
        case .nativeRecordTooLarge: return "This note change exceeds the iCloud sync limit."
        case .invalidHistory: return "Event history is malformed or incomplete."
        case .tooManyParents: return "Too many causal predecessors."
        case .causalOrderingUnavailable: return "The note has missing or conflicting causal history."
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
    public static let maxNativeLineBytes = 1024 * 1024
    public let fileURL: URL
    public private(set) var skippedLines: Int = 0
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

    /// Opens an existing event log in read-only mode without creating missing files or directories.
    /// Throws WidgetCorpus.Unreadable.logMissing if the file does not exist.
    public init(readingExisting fileURL: URL) throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw WidgetCorpus.Unreadable.logMissing
        }
        self.fileURL = fileURL
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
    private func locked<T>(_ body: (Int32) throws -> T) throws -> T {
        try queue.sync {
            let fd = open(fileURL.path, O_RDWR | O_APPEND)
            guard fd >= 0 else { throw EventStoreError.fileUnavailable }
            defer { close(fd) }
            guard flock(fd, LOCK_EX) == 0 else { throw EventStoreError.fileUnavailable }
            defer { flock(fd, LOCK_UN) }
            return try body(fd)
        }
    }
    private func strictRead(_ fd: Int32) throws -> [Event] {
        guard lseek(fd, 0, SEEK_SET) >= 0 else { throw EventStoreError.fileUnavailable }
        let data = FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        guard data.isEmpty || data.last == 10 else { throw EventStoreError.invalidHistory }
        let lines = data.split(separator: 10, omittingEmptySubsequences: false).dropLast()
        guard lines.allSatisfy({ !$0.isEmpty }) else { throw EventStoreError.invalidHistory }
        return try lines.map {
            guard $0.count <= Self.maxNativeLineBytes else { throw EventStoreError.nativeRecordTooLarge }
            let event: Event
            do { event = try decoder.decode(Event.self, from: Data($0)) }
            catch { throw EventStoreError.invalidHistory }
            guard Set(event.causalParents ?? []).count <= 1024 else { throw EventStoreError.tooManyParents }
            return event
        }
    }
    private func writeChecked(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(fd, base.advanced(by: offset), raw.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { throw EventStoreError.fileUnavailable }
                offset += written
            }
        }
    }
    private func payload(_ events: [Event], enforceNativeLimit: Bool = false) throws -> Data {
        var bytes = Data()
        for event in events {
            let line = try encoder.encode(event)
            if enforceNativeLimit && line.count > Self.maxNativeLineBytes { throw EventStoreError.nativeRecordTooLarge }
            bytes.append(line); bytes.append(10)
        }
        return bytes
    }
    private func enforceNativeLineLimit(_ bytes: Data) throws {
        guard bytes.split(separator: 10, omittingEmptySubsequences: false).allSatisfy({ $0.count <= Self.maxNativeLineBytes }) else {
            throw EventStoreError.nativeRecordTooLarge
        }
    }
    public func validateNativeHistory() throws {
        try locked { fd in _ = try strictRead(fd) }
    }
    public func validatedNativeRawSnapshot() throws -> Data {
        try locked { fd in
            _ = try strictRead(fd)
            guard lseek(fd, 0, SEEK_SET) >= 0 else { throw EventStoreError.fileUnavailable }
            return FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        }
    }
    private func declarations(_ events: [Event]) throws -> [Event] {
        let boundary = events.firstIndex { $0.causalParents != nil || $0.kind == .causalOrder } ?? events.count
        var declared = Set(events.compactMap { $0.kind == .causalOrder ? $0.relatedEventId : ($0.causalParents != nil ? $0.id : nil) })
        var result: [Event] = []
        let initialPrefix = events.prefix(boundary)
        if initialPrefix.contains(where: { $0.kind != .causalOrder && !declared.contains($0.id) }) {
            var previous: [UUID: UUID] = [:]
            let initial = initialPrefix.enumerated().sorted { a, b in
                a.element.timestamp == b.element.timestamp ? a.offset < b.offset : a.element.timestamp < b.element.timestamp
            }.map(\.element)
            for event in initial where event.kind != .causalOrder {
                if !declared.contains(event.id) {
                    result.append(Event(noteId: event.noteId, timestamp: event.timestamp, source: "unlirice", kind: .causalOrder,
                        relatedEventId: event.id, device: event.device, causalParents: previous[event.noteId].map { [$0] } ?? []))
                    declared.insert(event.id)
                }
                previous[event.noteId] = event.id
            }
        }
        for (index, event) in events.enumerated() where index >= boundary && event.kind != .causalOrder && !declared.contains(event.id) {
            let prefix = Array(events.prefix(index)) + result
            let heads = try causalHeads(noteID: event.noteId, events: prefix)
            result.append(Event(noteId: event.noteId, timestamp: event.timestamp, source: "unlirice", kind: .causalOrder,
                                relatedEventId: event.id, device: event.device, causalParents: heads))
            declared.insert(event.id)
        }
        return result
    }
    private func causalHeads(noteID: UUID, events: [Event]) throws -> [UUID] {
        let semantic = events.filter { $0.noteId == noteID && $0.kind != .causalOrder }
        let ids = Set(semantic.map(\.id))
        let order = EventCausalOrder.order(events)
        guard !order.conflictedNoteIDs.contains(noteID), order.pending.isDisjoint(with: ids) else { throw EventStoreError.causalOrderingUnavailable }
        var referenced = Set(semantic.flatMap { $0.causalParents ?? [] })
        for declaration in events where declaration.kind == .causalOrder && declaration.noteId == noteID && declaration.relatedEventId.map(ids.contains) == true {
            referenced.formUnion(declaration.causalParents ?? [])
        }
        let heads = ids.subtracting(referenced).sorted { $0.uuidString < $1.uuidString }
        guard heads.count <= 1024 else { throw EventStoreError.tooManyParents }
        return heads
    }
    /// Takes the canonical source snapshot after causal migration under one log lock.
    public func nativeCausalSnapshot() throws -> Data {
        try locked { fd in
            let events = try strictRead(fd)
            try writeChecked(payload(try declarations(events), enforceNativeLimit: true), fd: fd)
            guard lseek(fd, 0, SEEK_SET) >= 0 else { throw EventStoreError.fileUnavailable }
            return FileHandle(fileDescriptor: fd, closeOnDealloc: false).readDataToEndOfFile()
        }
    }
    public func prepareNativeCausalHistory() throws {
        try locked { fd in
            let events = try strictRead(fd)
            try writeChecked(payload(try declarations(events), enforceNativeLimit: true), fd: fd)
        }
    }
    public func append(_ event: Event) throws {
        try locked { fd in
            if NativeCloudBinding.exists(besideEventLog: fileURL) {
                let events = try strictRead(fd)
                let migration = try declarations(events)
                var stamped = event
                stamped.causalParents = try causalHeads(noteID: event.noteId, events: events + migration)
                try writeChecked(payload(migration + [stamped], enforceNativeLimit: true), fd: fd)
            } else { try writeChecked(payload([event]), fd: fd) }
        }
    }
    public func appendRaw(_ line: Data) throws {
        try locked { fd in
            if NativeCloudBinding.exists(besideEventLog: fileURL) { _ = try strictRead(fd); try enforceNativeLineLimit(line) }
            var bytes = line
            if bytes.last != 10 { bytes.append(10) }
            try writeChecked(bytes, fd: fd)
        }
    }
    public func appendRawBatch(_ lines: [Data]) throws {
        try locked { fd in
            let bound = NativeCloudBinding.exists(besideEventLog: fileURL)
            let existing = try strictRead(fd)
            var declarations: [Data] = [], semantics: [Data] = [], incoming: [Event] = []
            for line in lines {
                var raw = line
                if raw.last == 10 { raw.removeLast() }
                if bound { try enforceNativeLineLimit(raw) }
                guard !raw.isEmpty, !raw.contains(10), let event = try? decoder.decode(Event.self, from: raw) else { throw EventStoreError.invalidHistory }
                guard Set(event.causalParents ?? []).count <= 1024 else { throw EventStoreError.tooManyParents }
                if event.kind == .causalOrder { declarations.append(raw) } else { semantics.append(raw) }
                incoming.append(event)
            }
            let known = Dictionary((existing + incoming).filter { $0.kind != .causalOrder }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let allDeclarations = (existing + incoming).filter { $0.kind == .causalOrder }
            for event in incoming {
                if event.kind == .causalOrder {
                    guard let target = event.relatedEventId, event.causalParents != nil else { throw EventStoreError.invalidHistory }
                    if let targetEvent = known[target], targetEvent.noteId != event.noteId { throw EventStoreError.invalidHistory }
                } else if event.causalParents == nil {
                    let matching = allDeclarations.filter { $0.relatedEventId == event.id && $0.noteId == event.noteId && $0.causalParents != nil }
                    guard !matching.isEmpty else { throw EventStoreError.invalidHistory }
                    for declaration in matching {
                        for parent in declaration.causalParents ?? [] {
                            if let ancestor = known[parent], ancestor.noteId != event.noteId { throw EventStoreError.invalidHistory }
                        }
                    }
                }
                for parent in event.causalParents ?? [] {
                    if let ancestor = known[parent], ancestor.noteId != event.noteId { throw EventStoreError.invalidHistory }
                }
            }
            var bytes = Data()
            for line in declarations + semantics { bytes.append(line); bytes.append(10) }
            try writeChecked(bytes, fd: fd)
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

            let strict = NativeCloudBinding.exists(besideEventLog: fileURL)
            if strict && data.last != 10 { throw EventStoreError.invalidHistory }
            guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
                // Nothing but a partial line so far. Leave the cursor where it
                // was so the whole line is read once it's terminated.
                return EventBatch(events: [], cursor: EventStoreCursor(offset: start), restarted: restarted)
            }

            let complete = data[data.startIndex...lastNewline]
            if strict && complete.split(separator: 10, omittingEmptySubsequences: false).dropLast().contains(where: { $0.isEmpty }) {
                throw EventStoreError.invalidHistory
            }
            var events: [Event] = []
            for chunk in complete.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                if let event = try? decoder.decode(Event.self, from: Data(chunk)) {
                    events.append(event)
                } else if strict {
                    throw EventStoreError.invalidHistory
                } else {
                    self.skippedLines += 1
                }
            }

            return EventBatch(
                events: events,
                cursor: EventStoreCursor(offset: start + UInt64(complete.count)),
                restarted: restarted
            )
        }
    }
}
