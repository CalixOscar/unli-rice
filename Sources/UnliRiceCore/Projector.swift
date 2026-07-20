import Foundation

/// Rebuilds current Note state from the full event log, in timestamp order.
/// Pure and deterministic: given the same events, always produces the same
/// notes. This is what a fresh device (or a rebuilt local vector index) is
/// meant to replay after sync.
public enum Projector {
    public static func project(_ events: [Event]) -> [UUID: Note] {
        var notes: [UUID: Note] = [:]
        apply(events, to: &notes)
        resolveLinks(&notes)
        return notes
    }

    /// Folds `events` onto an existing projection, without the link pass.
    ///
    /// Split out of `project` so a reader that has already consumed most of the
    /// log can apply only what arrived since (see `EventStore.read(from:)`).
    /// Folding is associative over the log *as long as batches arrive in
    /// timestamp order*, which for an append-only file written in real time they
    /// do — each batch is sorted here, but a batch cannot reorder itself against
    /// one already folded. An event written with a backdated timestamp would
    /// therefore land in a different order than a whole-log `project` would put
    /// it, so nothing in this codebase backdates one; `Event.timestamp` defaults
    /// to now and no method overrides it.
    public static func apply(_ events: [Event], to notes: inout [UUID: Note]) {
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            // Anyone who changed a note they didn't write, whatever the change
            // was. Kept apart from `sources` — which only ever meant "wrote
            // text into this" — because the janitor's whole job is tagging and
            // filing, work that leaves no trace in the body and so used to be
            // invisible to anything reading the projection.
            if event.kind != .created, var note = notes[event.noteId], event.source != note.creator {
                note.editors.insert(event.source)
                notes[event.noteId] = note
            }

            switch event.kind {
            case .created:
                notes[event.noteId] = Note(
                    id: event.noteId,
                    title: event.title?.isEmpty == false ? event.title! : "Untitled",
                    body: event.text ?? "",
                    sources: [event.source],
                    creator: event.source,
                    createdAt: event.timestamp,
                    updatedAt: event.timestamp
                )

            case .appended:
                guard var note = notes[event.noteId] else { continue }
                if let text = event.text, !text.isEmpty {
                    note.body += note.body.isEmpty ? text : "\n\n---\n\(text)"
                }
                note.sources.insert(event.source)
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .tagged:
                guard var note = notes[event.noteId], let tag = event.tag else { continue }
                note.tags.insert(tag)
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .untagged:
                guard var note = notes[event.noteId], let tag = event.tag else { continue }
                note.tags.remove(tag)
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .archived:
                guard var note = notes[event.noteId] else { continue }
                note.archived = true
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .unarchived:
                guard var note = notes[event.noteId] else { continue }
                note.archived = false
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .flagged:
                guard var note = notes[event.noteId] else { continue }
                note.flags.append(
                    ReviewFlag(
                        id: event.id,
                        source: event.source,
                        reason: event.reason ?? "",
                        timestamp: event.timestamp
                    )
                )
                note.updatedAt = event.timestamp
                notes[event.noteId] = note

            case .reviewResolved:
                guard var note = notes[event.noteId], let target = event.relatedEventId else { continue }
                note.flags = note.flags.map { flag in
                    var updated = flag
                    if updated.id == target { updated.resolved = true }
                    return updated
                }
                note.updatedAt = event.timestamp
                notes[event.noteId] = note
            }
        }
    }

    /// Second pass, run only once every note exists: a note can link to one
    /// created later in the log, so `[[...]]` targets cannot be resolved inline
    /// in the loop above.
    ///
    /// Targets match either a note's title (case-insensitively) or a bare UUID.
    /// Title matching is sound here specifically because there is no `retitled`
    /// event kind — a title is fixed at creation, so a link can't silently
    /// re-point later. If that ever changes, this needs to change with it.
    ///
    /// Whole-corpus by necessity — a note created now can be the target of a
    /// link written a year ago — so an incremental caller must re-run it after
    /// every fold, and clear what the previous pass derived. That clearing is
    /// done here rather than left to the caller: `outboundLinks`/`backlinks`/
    /// `danglingLinks` are pure functions of the bodies, and a stale backlink
    /// surviving a fold would be a relationship the corpus no longer contains.
    /// This is the *cold* pass, and it stays deliberately simple: it is the
    /// definition of what links mean, and the thing `LinkIndex`'s incremental
    /// answer is tested against. Don't optimise it — optimise the incremental
    /// path, and keep this as the arbiter.
    public static func resolveLinks(_ notes: inout [UUID: Note]) {
        // Deterministic on duplicate titles: oldest note wins, ties broken by id,
        // so projection never depends on dictionary ordering.
        var idsByTitle: [String: UUID] = [:]
        for note in notes.values.sorted(by: { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }) {
            let key = note.title.lowercased()
            if idsByTitle[key] == nil { idsByTitle[key] = note.id }
        }

        for (id, note) in notes {
            var outbound: Set<UUID> = []
            var dangling: Set<String> = []

            for target in WikiLink.targets(in: note.body) {
                if let uuid = UUID(uuidString: target), notes[uuid] != nil {
                    outbound.insert(uuid)
                } else if let match = idsByTitle[target.lowercased()] {
                    outbound.insert(match)
                } else {
                    dangling.insert(target)
                }
            }

            outbound.remove(id) // a note citing itself isn't a relationship
            notes[id]?.outboundLinks = outbound
            notes[id]?.danglingLinks = dangling
            // Cleared here, not left over from a previous pass — see above.
            notes[id]?.backlinks = []
        }

        for (id, note) in notes {
            for target in note.outboundLinks {
                notes[target]?.backlinks.insert(id)
            }
        }
    }
}
