import Foundation

public enum NoteServiceError: Error, CustomStringConvertible {
    case noteNotFound(UUID)
    case projectionFailed

    public var description: String {
        switch self {
        case .noteNotFound(let id): return "No note found with id \(id)"
        case .projectionFailed: return "Failed to project note state after write"
        }
    }
}

/// The only surface anything (an agent over MCP, a future MLX janitor, a future
/// UI) is allowed to use to touch notes. Every method here maps to exactly one
/// kind of Event appended to the log — there is deliberately no method that
/// rewrites or removes history. Archiving is the closest thing to "delete" and
/// it is fully reversible via `unarchiveNote`.
public final class NoteService {
    private let store: EventStore

    /// The projection, kept between calls and brought up to date incrementally.
    ///
    /// Every read used to decode and fold the *entire* event log — O(n) per
    /// call, and every write does two reads (`requireExists` then `require`), so
    /// ingesting 40 notes was quadratic over a corpus that had just acquired a
    /// mechanism for getting large. This was deferred item #8 in
    /// PROJECT_NOTES.md, and the note there said "measure before assuming"; the
    /// measurement is in `ProjectionCacheTests`.
    ///
    /// It stays correct across processes because the cursor is a byte offset
    /// into an append-only file: another MCP client's writes appear as bytes
    /// past the cursor, and `EventStore.read(from:)` reports a shrunken file so
    /// the cache can be thrown away rather than folded onto.
    private var cachedNotes: [UUID: Note] = [:]
    private var cursor: EventStoreCursor = .start
    private let cacheLock = NSLock()

    /// Keeps wiki-links current without rebuilding them for the whole corpus on
    /// every write. See `LinkIndex`.
    private var links = LinkIndex()

    public init(store: EventStore) {
        self.store = store
    }

    @discardableResult
    public func createNote(title: String, body: String, source: String) throws -> Note {
        let noteId = UUID()
        try store.append(Event(noteId: noteId, source: source, kind: .created, title: title, text: body))
        return try require(noteId)
    }

    @discardableResult
    public func appendToNote(id: UUID, text: String, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .appended, text: text))
        return try require(id)
    }

    @discardableResult
    public func tagNote(id: UUID, tag: String, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .tagged, tag: tag))
        return try require(id)
    }

    @discardableResult
    public func untagNote(id: UUID, tag: String, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .untagged, tag: tag))
        return try require(id)
    }

    /// Soft and reversible — hides the note from default listings, nothing more.
    @discardableResult
    public func archiveNote(id: UUID, reason: String, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .archived, reason: reason))
        return try require(id)
    }

    @discardableResult
    public func unarchiveNote(id: UUID, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .unarchived))
        return try require(id)
    }

    /// The only way an agent can propose a structural change (merge, dedupe,
    /// "this contradicts that other note"). It never applies anything itself —
    /// it queues the concern for a human to resolve via `resolveReview`.
    @discardableResult
    public func flagForReview(id: UUID, reason: String, source: String) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .flagged, reason: reason))
        return try require(id)
    }

    @discardableResult
    public func resolveReview(id: UUID, flagId: UUID, source: String, outcome: String? = nil) throws -> Note {
        try requireExists(id)
        try store.append(Event(noteId: id, source: source, kind: .reviewResolved, reason: outcome, relatedEventId: flagId))
        return try require(id)
    }

    /// Consolidates a group of near-duplicate notes into one: each `other`
    /// note's content is appended onto `keepID` (nothing is lost — this is
    /// exactly `appendToNote`, once per other note), each `other` note is
    /// archived (soft and reversible via `unarchiveNote` — decision #2, never a
    /// delete), and every flag in `flags` is marked resolved so the whole
    /// group clears from the review queue together.
    ///
    /// This is the human-decides counterpart PROJECT_NOTES.md's decision #3
    /// named as deferred: "resolving a flag is meant to happen after a human
    /// decides — there's no UI for that yet." It is never called by
    /// `JanitorRunner` or any agent — the janitor can only ever propose a
    /// duplicate via `flagForReview`, and this method doesn't exist on that
    /// path. It only runs from the GUI, once, when a person looks at the
    /// specific notes and presses "Keep this one." Composed entirely from the
    /// same three primitives above; nothing here reaches into `EventStore`
    /// directly, so this file stays the only thing that writes.
    @discardableResult
    public func consolidateDuplicates(
        keeping keepID: UUID,
        archiving otherIDs: [UUID],
        resolving flags: [(noteID: UUID, flagID: UUID)],
        source: String
    ) throws -> Note {
        try requireExists(keepID)
        let keeperTitle = try require(keepID).title

        for otherID in otherIDs where otherID != keepID {
            let other = try require(otherID)
            if !other.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try appendToNote(
                    id: keepID,
                    text: "Merged from \"\(other.title)\":\n\n\(other.body)",
                    source: source
                )
            }
            try archiveNote(id: otherID, reason: "consolidated into \"\(keeperTitle)\"", source: source)
        }

        for flag in flags {
            try resolveReview(id: flag.noteID, flagId: flag.flagID, source: source, outcome: "consolidated")
        }

        return try require(keepID)
    }

    public func getNote(id: UUID) throws -> Note? {
        try currentNotes()[id]
    }

    public func listNotes(includeArchived: Bool = false) throws -> [Note] {
        try currentNotes().values
            .filter { includeArchived || !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func searchNotes(query: String, includeArchived: Bool = false) throws -> [Note] {
        let q = query.lowercased()
        guard !q.isEmpty else { return try listNotes(includeArchived: includeArchived) }
        return try listNotes(includeArchived: includeArchived).filter { note in
            note.title.lowercased().contains(q)
                || note.body.lowercased().contains(q)
                || note.tags.contains { $0.lowercased().contains(q) }
        }
    }

    /// The immutable history for one note, oldest first.
    ///
    /// This intentionally returns events rather than a synthetic diff. The
    /// event log already records exactly what was added, by whom, and when;
    /// presenting that evidence directly keeps provenance auditable in the GUI
    /// and over MCP.
    public func noteHistory(id: UUID) throws -> [Event] {
        try store.readAll()
            .filter { $0.noteId == id }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func pendingReviews() throws -> [(note: Note, flag: ReviewFlag)] {
        try currentNotes().values
            .flatMap { note in note.flags.filter { !$0.resolved }.map { (note, $0) } }
            .sorted { $0.flag.timestamp < $1.flag.timestamp }
    }

    public func transactionLog(limit: Int = 50) throws -> [Event] {
        Array(try store.readAll().sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    // MARK: - Private

    private func currentNotes() throws -> [UUID: Note] {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        let batch = try store.read(from: cursor)
        if batch.restarted {
            cachedNotes = [:]
            links.reset()
        }
        if !batch.events.isEmpty {
            Projector.apply(batch.events, to: &cachedNotes)
            // Only these two kinds can change a link. A run of tags and flags —
            // which is what a whole janitor pass consists of — costs nothing
            // here at all.
            links.update(
                &cachedNotes,
                created: batch.events.filter { $0.kind == .created }.map(\.noteId),
                bodiesChanged: batch.events.filter { $0.kind == .appended }.map(\.noteId)
            )
        }
        cursor = batch.cursor
        return cachedNotes
    }

    private func requireExists(_ id: UUID) throws {
        guard try currentNotes()[id] != nil else { throw NoteServiceError.noteNotFound(id) }
    }

    private func require(_ id: UUID) throws -> Note {
        guard let note = try currentNotes()[id] else { throw NoteServiceError.noteNotFound(id) }
        return note
    }
}
