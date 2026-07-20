import Foundation

/// The single place in this codebase where note history actually leaves the
/// event log — and the reason it is a separate type from `EventStore` rather
/// than a method on it.
///
/// Decision #2 in PROJECT_NOTES.md says no destructive delete exists, with one
/// carve-out written into it: *"If a future feature needs real deletion, it must
/// be a human-triggered action, never something an agent or the janitor can
/// invoke autonomously."* This is that feature, and the carve-out is enforced
/// structurally rather than by convention:
///
/// - It lives outside `NoteService`, so nothing that reaches notes through the
///   safety boundary can reach this. `unlirice-mcp` builds its tool catalog
///   from `NoteService` methods, which means no MCP tool can be wired to this
///   even by accident — an agent cannot express the operation at all.
/// - It never runs on a schedule. `RoutineDriver` has no path here.
/// - It is not really a delete. Every purged event is written out verbatim
///   first, and `restore` appends them back — the log is still append-only, so
///   a restore is just more history, and the projection comes back identical.
///
/// What it genuinely destroys is the *contiguity* of the log: after a purge the
/// live file no longer contains those lines. That is why the whole file is
/// copied to `Backups/` before it is rewritten, and why both the backup and the
/// per-note trash record are written and `fsync`'d before the log is touched.
public enum TrashService {
    /// One purged note, complete enough to rebuild it from nothing.
    public struct TrashedNote: Codable, Identifiable, Sendable {
        public let noteID: UUID
        public let title: String
        public let trashedAt: Date
        /// Every event that ever mentioned this note, in original log order.
        public let events: [Event]

        public var id: UUID { noteID }
    }

    /// What a purge did, for the status line and for tests.
    public struct Receipt: Equatable, Sendable {
        public let notesPurged: Int
        public let eventsRemoved: Int
        public let eventsRemaining: Int
        /// The pre-purge copy of the whole log.
        public let backupURL: URL
        /// One file per purged note.
        public let trashURLs: [URL]
    }

    public enum TrashError: Error, CustomStringConvertible {
        case fileUnavailable
        case nothingToPurge
        case notInTrash(UUID)

        public var description: String {
            switch self {
            case .fileUnavailable: return "Couldn't open the event log."
            case .nothingToPurge: return "Those notes aren't in the event log."
            case .notInTrash(let id): return "No trashed note with id \(id)."
            }
        }
    }

    // MARK: - Locations

    /// Siblings of the log, not children of a temp dir: a user who goes looking
    /// for what they deleted should find it next to the thing they deleted it
    /// from, and it should survive reboots and app deletion.
    public static func trashDirectory(forLog logURL: URL) -> URL {
        logURL.deletingLastPathComponent().appendingPathComponent("Trash", isDirectory: true)
    }

    public static func backupDirectory(forLog logURL: URL) -> URL {
        logURL.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
    }

    // MARK: - Purge

    /// Removes every event belonging to `noteIDs` from the log, after copying
    /// the log aside and writing each note's history to `Trash/`.
    ///
    /// Ordering is deliberate and not rearrangeable: backup, then trash records,
    /// then rewrite. A crash between any two steps leaves the log either
    /// untouched or fully rewritten with the recovery data already on disk. The
    /// reverse order would have a window where the log is short and nothing
    /// remembers what it used to say.
    @discardableResult
    public static func purge(noteIDs: Set<UUID>, logURL: URL) throws -> Receipt {
        guard !noteIDs.isEmpty else { throw TrashError.nothingToPurge }

        let fm = FileManager.default
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        // Take the exclusive lock for the whole read-modify-write. Another
        // process appending between our read and our replace would otherwise
        // have its event silently dropped by the rewrite.
        let fd = open(logURL.path, O_RDONLY)
        guard fd >= 0 else { throw TrashError.fileUnavailable }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw TrashError.fileUnavailable }
        defer { flock(fd, LOCK_UN) }

        let original = try Data(contentsOf: logURL)
        let lines = original.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)

        // Keep the raw line alongside the decoded event: the surviving lines are
        // written back byte-for-byte rather than re-encoded, so a log written by
        // an older or newer version of this app can't be silently reformatted —
        // or worse, have a field this build doesn't know about dropped.
        var keptLines: [Data] = []
        var purgedEvents: [UUID: [Event]] = [:]
        var titles: [UUID: String] = [:]

        for line in lines {
            let data = Data(line)
            guard let event = try? decoder.decode(Event.self, from: data) else {
                // Undecodable lines are somebody else's data. Keep them.
                keptLines.append(data)
                continue
            }
            if noteIDs.contains(event.noteId) {
                purgedEvents[event.noteId, default: []].append(event)
                if event.kind == .created, let title = event.title {
                    titles[event.noteId] = title
                }
            } else {
                keptLines.append(data)
            }
        }

        guard !purgedEvents.isEmpty else { throw TrashError.nothingToPurge }

        let stamp = Self.stamp()

        let backupDir = backupDirectory(forLog: logURL)
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupURL = backupDir.appendingPathComponent("events-\(stamp).jsonl")
        try original.write(to: backupURL, options: .atomic)

        let trashDir = trashDirectory(forLog: logURL)
        try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
        var trashURLs: [URL] = []
        for (noteID, events) in purgedEvents {
            let record = TrashedNote(
                noteID: noteID,
                title: titles[noteID] ?? "(untitled)",
                trashedAt: Date(),
                events: events
            )
            let url = trashDir.appendingPathComponent("\(noteID.uuidString).json")
            try encoder.encode(record).write(to: url, options: .atomic)
            trashURLs.append(url)
        }

        var rebuilt = Data()
        for line in keptLines {
            rebuilt.append(line)
            rebuilt.append(UInt8(ascii: "\n"))
        }
        try rebuilt.write(to: logURL, options: .atomic)

        return Receipt(
            notesPurged: purgedEvents.count,
            eventsRemoved: purgedEvents.values.reduce(0) { $0 + $1.count },
            eventsRemaining: keptLines.count,
            backupURL: backupURL,
            trashURLs: trashURLs
        )
    }

    // MARK: - Reading and restoring the trash

    public static func listTrashed(forLog logURL: URL) -> [TrashedNote] {
        let dir = trashDirectory(forLog: logURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(TrashedNote.self, from: Data(contentsOf: $0)) }
            .sorted { $0.trashedAt > $1.trashedAt }
    }

    /// Appends a trashed note's events back onto the log and removes the trash
    /// record. Not a rewrite — the events go back on the end, and the projector
    /// rebuilds the same note from them regardless of where they sit in the file
    /// (every event carries its own timestamp). This is why purging can afford
    /// to be a rewrite while everything else in the system stays append-only.
    public static func restore(noteID: UUID, logURL: URL, into store: EventStore) throws {
        let url = trashDirectory(forLog: logURL).appendingPathComponent("\(noteID.uuidString).json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let record = try? decoder.decode(TrashedNote.self, from: data) else {
            throw TrashError.notInTrash(noteID)
        }
        for event in record.events {
            try store.append(event)
        }
        try? FileManager.default.removeItem(at: url)
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
