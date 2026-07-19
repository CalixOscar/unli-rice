import Foundation

/// Rebuilds current Note state from the full event log, in timestamp order.
/// Pure and deterministic: given the same events, always produces the same
/// notes. This is what a fresh device (or a rebuilt local vector index) is
/// meant to replay after sync.
public enum Projector {
    public static func project(_ events: [Event]) -> [UUID: Note] {
        var notes: [UUID: Note] = [:]

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.kind {
            case .created:
                notes[event.noteId] = Note(
                    id: event.noteId,
                    title: event.title?.isEmpty == false ? event.title! : "Untitled",
                    body: event.text ?? "",
                    sources: [event.source],
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

        return notes
    }
}
