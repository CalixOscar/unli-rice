import AppKit
import Foundation
import UnliRiceCore

/// Bulk housekeeping: the clipboard prompts, and the one destructive action in
/// the app.
///
/// These two things sit in the same file on purpose — they're the two halves of
/// the same answer to "my store has 200 notes and most of them are junk". The
/// clipboard prompts hand the *judgement* to whichever LLM is already connected
/// (it can read every note; this app can only pattern-match). Trash handles the
/// *irreversible* part, which is the one thing no agent may do. Neither half
/// works alone, and neither half is allowed to become the other.
extension AppStore {
    // MARK: - Prompts to hand to a connected agent

    /// Copies a prompt and says so. Nothing else — deliberately not "copy and
    /// also open the assistant", because the user may be pasting into any of
    /// five tools and we don't know which one is theirs.
    func copyPrompt(_ prompt: CleanupPrompt) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(prompt.body, forType: .string)
        statusMessage = "Copied “\(prompt.title)” — paste it into your assistant."
    }

    // MARK: - Trash

    /// Notes ticked in the Archived pane, resolved back to notes.
    var selectedArchivedNotes: [Note] {
        archivedNotes.filter { archiveSelection.contains($0.id) }
    }

    func toggleArchiveSelection(_ note: Note) {
        if archiveSelection.contains(note.id) {
            archiveSelection.remove(note.id)
        } else {
            archiveSelection.insert(note.id)
        }
    }

    /// Permanently removes the ticked notes from the event log.
    ///
    /// The confirmation is raised here rather than in the view, because this is
    /// the only call in the codebase that can lose data and the alert is part of
    /// the operation, not part of its presentation — a future second caller must
    /// not be able to reach the purge without it. `TrashService` keeps a full
    /// copy of both the note and the pre-purge log, and the alert says so: a
    /// warning that overstates the damage trains people to click through
    /// warnings that don't.
    func moveSelectedToTrash() {
        let victims = selectedArchivedNotes
        guard !victims.isEmpty else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = victims.count == 1
            ? "Move “\(victims[0].title)” to the trash?"
            : "Move \(victims.count) notes to the trash?"
        alert.informativeText = """
        This removes them from the event log — the only operation in Unli Rice that does.

        A full copy of each note, and of the log as it is right now, is written to \
        Trash and Backups next to your data file first, so this is recoverable by hand. \
        It will not be recoverable from inside the app.
        """
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let receipt = try TrashService.purge(
                noteIDs: Set(victims.map(\.id)), logURL: dataURL
            )
            archiveSelection = []
            reload()
            statusMessage = """
            Trashed \(receipt.notesPurged) note\(receipt.notesPurged == 1 ? "" : "s") \
            (\(receipt.eventsRemoved) events). Backup: \(receipt.backupURL.lastPathComponent)
            """
        } catch {
            statusMessage = "Couldn't trash those notes: \(error)"
        }
    }

    /// Reveals the trash folder in Finder — the recovery path the alert promises.
    /// Restoring from inside the app would need a whole pane for something that
    /// should happen roughly never; `TrashService.restore` exists for when it
    /// does, and this is how a person gets to the files meanwhile.
    func revealTrashFolder() {
        let dir = TrashService.trashDirectory(forLog: dataURL)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }

    var trashedNoteCount: Int {
        TrashService.listTrashed(forLog: dataURL).count
    }

    // MARK: - Grouping

    /// `visibleNotes`, cut into dated runs.
    ///
    /// The list is sorted by recency, so the groups fall out of it in order and
    /// no re-sorting happens here. They exist because 144 rows that all begin
    /// "Session:" and all say "1 hour ago" are visually one undifferentiated
    /// block — the date header is the only thing on screen that changes as you
    /// scroll, and without it there's no sense of position at all.
    var visibleSections: [NoteSection] {
        let calendar = Calendar.current
        var sections: [NoteSection] = []
        for note in visibleNotes {
            let title = Self.groupTitle(for: note.updatedAt, calendar: calendar)
            if sections.last?.title == title {
                sections[sections.count - 1].notes.append(note)
            } else {
                sections.append(NoteSection(title: title, notes: [note]))
            }
        }
        return sections
    }

    private static func groupTitle(for date: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let week = calendar.date(byAdding: .day, value: -7, to: Date()), date > week {
            return "Earlier this week"
        }
        let formatter = DateFormatter()
        // Year included only once it's ambiguous — "March" reads better than
        // "March 2026" right up until there are two Marches in the list.
        formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "MMMM" : "MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Archiving from anywhere

    /// Archive straight from a list row. `archive(_:)` already exists and does
    /// the work; this exists so the row can archive without first opening the
    /// note, which was the only route before.
    func archiveFromList(_ note: Note) {
        archive(note, reason: "archived from the note list")
        if selectedNoteID == note.id { selectedNoteID = nil }
    }
}

/// A dated run of notes in the list. `notes` is var so `visibleSections` can
/// accumulate into the last one without building an intermediate dictionary
/// that would lose the recency ordering it depends on.
struct NoteSection: Identifiable {
    let title: String
    var notes: [Note]

    var id: String { title }
}

extension Note {
    /// Substring match over the parts of a note a person would search by.
    /// Body included: with 144 ingested "Session: …" notes, titles alone can't
    /// distinguish them, which is exactly when someone reaches for search.
    func matches(_ lowercasedQuery: String) -> Bool {
        if title.lowercased().contains(lowercasedQuery) { return true }
        if body.lowercased().contains(lowercasedQuery) { return true }
        if tags.contains(where: { $0.lowercased().contains(lowercasedQuery) }) { return true }
        return sources.contains { $0.lowercased().contains(lowercasedQuery) }
    }
}
