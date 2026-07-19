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
        Projector.project(try store.readAll())
    }

    private func requireExists(_ id: UUID) throws {
        guard try currentNotes()[id] != nil else { throw NoteServiceError.noteNotFound(id) }
    }

    private func require(_ id: UUID) throws -> Note {
        guard let note = try currentNotes()[id] else { throw NoteServiceError.noteNotFound(id) }
        return note
    }
}
