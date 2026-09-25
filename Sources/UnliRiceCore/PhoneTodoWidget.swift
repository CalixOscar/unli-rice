import Foundation

/// The iPhone To Do widget's data, shared between Unli Rice Capture and its widget.
///
/// Capture's notes live in its own container and arrive from the Mac through the iCloud
/// folder the user picked. A widget extension can reach neither, so Capture writes what
/// the widget shows into the shared App Group container every time it syncs, and the
/// widget reads only that. A Done tap is queued in the same place and Capture archives
/// the note on its next sync, which is also what carries it back to the Mac.
///
/// Pure file I/O over a given directory, so it is tested without an App Group.
public enum PhoneTodoWidget {
    public static let groupID = "group.com.calmdownoscar.unlirice"
    public static let kind = "UnliRiceCaptureTodo"

    public static let lockedText =
        "Your to-dos are hidden while Unli Rice is locked. Open it to see them."
    public static let notYetText =
        "Open Unli Rice once, and your to-dos will show up here."

    static let snapshotName = "phone-todo-widget.json"
    static let doneQueueName = "phone-todo-done.json"

    /// One open to-do. The subtitle is worked out when the widget draws, so "2 days ago"
    /// stays true between syncs.
    public struct Item: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public let creator: String
        public let createdAt: Date
        public let projects: [String]

        public init(id: UUID, title: String, creator: String, createdAt: Date, projects: [String]) {
            self.id = id
            self.title = title
            self.creator = creator
            self.createdAt = createdAt
            self.projects = projects
        }
    }

    public struct Snapshot: Codable, Equatable, Sendable {
        public let writtenAt: Date
        public let items: [Item]
        /// The app lock is on: the widget must not show titles on the home screen.
        public let locked: Bool

        public init(writtenAt: Date = Date(), items: [Item], locked: Bool) {
            self.writtenAt = writtenAt
            self.items = items
            self.locked = locked
        }

        /// Built from the notes Capture holds: every open `todo` note, oldest first,
        /// exactly as the Mac widget lists them.
        public init(notes: [Note], locked: Bool, writtenAt: Date = Date()) {
            let open = notes.filter { !$0.archived && $0.tags.contains("todo") }
                .sorted { a, b in
                    a.createdAt != b.createdAt ? a.createdAt < b.createdAt
                                               : a.id.uuidString < b.id.uuidString
                }
            self.init(writtenAt: writtenAt, items: open.map {
                Item(id: $0.id,
                     title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines),
                     creator: $0.creator,
                     createdAt: $0.createdAt,
                     projects: TodoWidgetList.projects(of: $0))
            }, locked: locked)
        }

        /// The rows to draw: queued Done taps are already gone.
        public func rows(hiding done: Set<UUID>, now: Date = Date()) -> [TodoWidgetList.Row] {
            items.filter { !done.contains($0.id) }.map {
                TodoWidgetList.Row(id: $0.id, title: $0.title,
                                   subtitle: TodoWording.subtitle(creator: $0.creator,
                                                                  createdAt: $0.createdAt,
                                                                  projects: $0.projects, now: now))
            }
        }
    }

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Snapshot (written by Capture, read by the widget)

    public static func write(_ snapshot: Snapshot, in dir: URL) throws {
        let data = try encoder().encode(snapshot)
        try data.write(to: dir.appendingPathComponent(snapshotName), options: .atomic)
    }

    /// Nil when Capture has never written one (or it can't be read): the widget then says
    /// to open the app once, never "Nothing to do".
    public static func read(in dir: URL) -> Snapshot? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(snapshotName)) else { return nil }
        return try? decoder().decode(Snapshot.self, from: data)
    }

    /// Rewrites only the lock flag, so turning the app lock on hides the widget at once.
    public static func setLocked(_ locked: Bool, in dir: URL) throws {
        let current = read(in: dir) ?? Snapshot(items: [], locked: locked)
        try write(Snapshot(writtenAt: current.writtenAt, items: current.items, locked: locked), in: dir)
    }

    // MARK: - Done queue (written by the widget, applied by Capture)

    public static func pendingDone(in dir: URL) -> Set<UUID> {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(doneQueueName)),
              let ids = try? decoder().decode([UUID].self, from: data) else { return [] }
        return Set(ids)
    }

    public static func queueDone(_ id: UUID, in dir: URL) throws {
        var ids = pendingDone(in: dir)
        ids.insert(id)
        try writeQueue(ids, in: dir)
    }

    /// Removes only the ids Capture applied, so a tap made meanwhile isn't lost.
    public static func clearDone(_ applied: Set<UUID>, in dir: URL) throws {
        let remaining = pendingDone(in: dir).subtracting(applied)
        try writeQueue(remaining, in: dir)
    }

    private static func writeQueue(_ ids: Set<UUID>, in dir: URL) throws {
        let data = try encoder().encode(ids.sorted { $0.uuidString < $1.uuidString })
        try data.write(to: dir.appendingPathComponent(doneQueueName), options: .atomic)
    }

    /// Archives every queued to-do that is still open, and returns the ids handled. A
    /// queued id whose note is missing, already archived, or not a to-do is handled too:
    /// nothing is written for it, and it leaves the queue.
    @discardableResult
    public static func applyPendingDone(in dir: URL, service: NoteService) -> Set<UUID> {
        let queued = pendingDone(in: dir)
        guard !queued.isEmpty else { return [] }
        var handled: Set<UUID> = []
        for id in queued {
            if (try? TodoDone.markDone(noteID: id, service: service)) != nil { handled.insert(id) }
        }
        try? clearDone(handled, in: dir)
        return handled
    }
}
