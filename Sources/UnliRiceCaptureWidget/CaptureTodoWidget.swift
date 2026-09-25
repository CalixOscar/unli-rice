import SwiftUI
import UnliRiceCore
import WidgetKit

/// The iPhone "To do" widget. Same layout as the Mac widget; the data is the list Capture
/// last wrote into the shared App Group container (see `PhoneTodoWidget`).
@main
struct UnliRiceCaptureTodoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: PhoneTodoWidget.kind, provider: CaptureTodoProvider()) { entry in
            TodoWidgetView(entry: entry,
                           done: { id, _ in CaptureMarkDoneIntent(noteID: id) },
                           listURL: nil,
                           rowURL: nil)
        }
        .configurationDisplayName("To do")
        .description("Things your AI assistants suggested doing later.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CaptureTodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(context.isPreview ? .sample : Self.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        // Capture reloads this whenever it syncs; the half-hour refresh only keeps
        // "2 hours ago" honest in between.
        let next = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [Self.load()], policy: .after(next)))
    }

    static func load(now: Date = Date()) -> TodoEntry {
        guard let dir = PhoneTodoWidget.containerURL() else {
            return TodoEntry(date: now, content: .unknown(reason: TodoWidgetList.reason(for: .noGroupContainer)))
        }
        guard let snapshot = PhoneTodoWidget.read(in: dir) else {
            return TodoEntry(date: now, content: .unknown(reason: ""),
                             unknownHeadline: PhoneTodoWidget.notYetText)
        }
        if snapshot.locked {
            return TodoEntry(date: now, content: .unknown(reason: ""),
                             unknownHeadline: PhoneTodoWidget.lockedText)
        }
        let rows = snapshot.rows(hiding: PhoneTodoWidget.pendingDone(in: dir), now: now)
        return TodoEntry(date: now, content: .list(rows: rows, someUnreadable: false, corpusID: "phone"))
    }
}
