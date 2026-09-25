import AppKit
import Foundation
import UnliRiceCore
import WidgetKit

/// The app's side of the to-do widget (B5, B6): opening what the widget links to,
/// noticing what the widget changed, and keeping the widget current.
extension AppStore {
    /// Handles `unlirice://` links. Parses only through `TodoLink.parse`, and anything it
    /// rejects is ignored: a URL scheme can be called by any app (P7), so no link copies,
    /// archives or writes anything — it only navigates (D10).
    func handleTodoURL(_ url: URL) {
        guard let link = TodoLink.parse(url) else { return }
        switch link {
        case .todo:
            showTodo()
        case .handoff(let id):
            // The widget may have drawn an item the app hasn't loaded yet.
            if note(id: id) == nil { reload() }
            guard let item = note(id: id) else {
                showTodo()
                statusMessage = "That to-do item no longer exists."
                return
            }
            let target = TodoHandoff.target(for: item, lookup: { self.note(id: $0) })
            todoOpenedFromItemID = item.id
            closeAllPanes()
            selectNote(target.id)
        }
    }

    /// Something outside this window may have changed the to-do list.
    func refreshAfterTodoChange() {
        reload()
        todoRefreshToken &+= 1
    }

    /// Asks WidgetKit to redraw only when the set of open to-dos actually changed, so the
    /// five-minute routine tick doesn't spend the widget's daily refresh budget.
    func reloadWidgetIfTodosChanged() {
        let open = Set(notes.lazy.filter { $0.tags.contains("todo") }.map(\.id))
        guard open != widgetTodoIDs else { return }
        widgetTodoIDs = open
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetList.kind)
    }

    /// The open to-do a note is about, for "Fix with AI…" on the note view: the note
    /// itself if it is one; for a handoff, the item the widget opened it from, else the
    /// oldest open to-do pointing at it. Nil for any other note.
    func todoItemNote(for note: Note) -> Note? {
        if !note.archived, note.tags.contains("todo") { return note }
        guard note.tags.contains("handoff") else { return nil }
        let pointing = notes.filter {
            $0.tags.contains("todo") && TodoHandoff.handoffID(inBody: $0.body) == note.id
        }
        if let from = todoOpenedFromItemID, let hit = pointing.first(where: { $0.id == from }) {
            return hit
        }
        return pointing.min { $0.createdAt < $1.createdAt }
    }

    /// Copies a prompt for one AI-filed to-do. The copy happens only on a click inside the
    /// app (D10), and resolves the handoff through `TodoHandoff.target`, the same function
    /// navigation uses, so the two cannot disagree (P9, P10).
    func copyTodoPrompt(for target: MCPTarget, itemNote: Note) {
        let projects = TodoWidgetList.projects(of: itemNote)
        let project = projects.isEmpty ? "no project" : projects.joined(separator: ", ")
        let item = StudioTodo.Item(
            id: "\(project)/ai-todo/\(itemNote.id.uuidString)",
            project: project,
            kind: .aiFlagged,
            title: itemNote.title,
            evidence: TodoWording.subtitle(creator: itemNote.creator,
                                           createdAt: itemNote.createdAt,
                                           projects: projects),
            noteID: itemNote.id)
        let resolved = TodoHandoff.target(for: itemNote, lookup: { self.note(id: $0) })
        let body = TodoPrompt.build(
            target: target,
            item: item,
            itemNote: itemNote,
            handoff: resolved.id == itemNote.id ? nil : resolved)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
        statusMessage = "Copied instructions for \(target.displayName) — paste them into your assistant."
    }
}

/// Listens for the widget's "a to-do changed" Darwin notification. One per process: the
/// app can have several windows but needs only one listener.
final class TodoChangeObserver {
    static let shared = TodoChangeObserver()
    private var handler: (() -> Void)?
    private var started = false

    func start(_ handler: @escaping () -> Void) {
        self.handler = handler
        guard !started else { return }
        started = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<TodoChangeObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler?() }
            },
            TodoWidgetList.changedNotification as CFString,
            nil,
            .deliverImmediately)
    }
}
