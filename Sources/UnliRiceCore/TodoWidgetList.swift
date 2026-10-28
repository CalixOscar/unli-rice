import Foundation

/// What the to-do widget shows, and the one thing it does, computed from notes.
///
/// Pure and in Core so it is tested without WidgetKit: the widget extension only lays
/// these rows out. Every string a person reads on the widget lives here, in plain words,
/// because the founder is the reader and is not a developer.
public enum TodoWidgetList {
    public static let kind = "UnliRiceTodo"
    /// Posted (Darwin) by the widget after it archives an item, so an open app reloads.
    public static let changedNotification = "com.calmdownoscar.unlirice.todoChanged"

    public static let emptyText =
        "Nothing to do. When an AI assistant spots something for later, it shows up here."
    public static let unknownText = "Can't read your to-do list right now. Open Unli Rice to fix it."
    public static let someUnreadableText = "Some notes couldn't be read. Open Unli Rice."

    public static func countText(_ n: Int) -> String { "\(n) to do" }
    public static func moreText(_ n: Int) -> String { "+\(n) more, open Unli Rice" }
    public static func markDoneLabel(_ title: String) -> String { "Mark done: \(title)" }

    public struct Row: Equatable, Sendable, Identifiable {
        public let id: UUID
        public let title: String
        public let subtitle: String

        public init(id: UUID, title: String, subtitle: String) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// Every open note tagged `todo`, oldest first (D7), one row per note even when it is
    /// tagged for two projects (P15). The repo snapshot is not consulted (D9): a stale
    /// snapshot must never hide an item.
    public static func rows(from notes: [Note], now: Date = Date()) -> [Row] {
        notes
            .filter { !$0.archived && $0.tags.contains("todo") }
            .sorted { a, b in
                a.createdAt != b.createdAt ? a.createdAt < b.createdAt
                                           : a.id.uuidString < b.id.uuidString
            }
            .map { note in
                Row(id: note.id,
                    title: note.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    subtitle: TodoWording.subtitle(creator: note.creator,
                                                   createdAt: note.createdAt,
                                                   projects: projects(of: note),
                                                   now: now))
            }
    }

    /// A to-do's project tags: every tag except the reserved `todo` and `handoff`.
    public static func projects(of note: Note) -> [String] {
        note.tags.filter { $0 != "todo" && $0 != "handoff" }.sorted()
    }

    /// Why the list couldn't be read, in words a non-developer can act on. Shown under
    /// `unknownText`; never shown as "Nothing to do" (D8).
    public static func reason(for failure: WidgetCorpus.Unreadable) -> String {
        switch failure {
        case .folderFailed:       return "The widget can't open a custom notes folder yet."
        case .settingsUnreadable: return "Unli Rice's settings couldn't be read."
        case .noGroupContainer:   return "The widget can't reach Unli Rice's storage."
        case .logMissing:         return "Unli Rice hasn't saved any notes on this Mac yet."
        case .logUnreadable:      return "Your notes couldn't be read."
        }
    }
}

/// Marking a to-do done from outside the app (the widget's Done button).
public enum TodoDone {
    public enum Outcome: Equatable, Sendable {
        case archived
        /// Already archived, gone, or not a to-do: nothing is written, so a second tap or
        /// a tap on a row rendered before the item changed is harmless (P6).
        case nothingToDo
    }

    public static func markDone(noteID: UUID, service: NoteService) throws -> Outcome {
        guard let note = try service.getNote(id: noteID),
              note.tags.contains("todo"),
              !note.archived else {
            return .nothingToDo
        }
        try service.archiveNote(id: noteID, reason: "done", source: "human")
        return .archived
    }
}
