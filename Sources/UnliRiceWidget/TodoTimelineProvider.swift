import Foundation
import UnliRiceCore
import WidgetKit

struct TodoEntry: TimelineEntry {
    enum Content {
        /// Read on purpose from the corpus the app uses. `corpusID` travels into every
        /// Done button so a row can never archive in a different corpus (P6).
        case list(rows: [TodoWidgetList.Row], someUnreadable: Bool, corpusID: String)
        /// Could not read the list. Never shown as "Nothing to do" (D8).
        case unknown(reason: String)
    }

    let date: Date
    let content: Content

    /// The widget gallery's preview. Illustrative only; never real notes.
    static let sample = TodoEntry(date: Date(), content: .list(rows: [
        .init(id: UUID(), title: "Update the website link on the ClearSpace App Store page",
              subtitle: "Suggested by Claude · 3 days ago · clearspace"),
        .init(id: UUID(), title: "Delete old copies of the website so its hosting space stops being full",
              subtitle: "Suggested by Codex · yesterday · calmdownoscar"),
        .init(id: UUID(), title: "Add a rate-this-app prompt to Shuttle Vision",
              subtitle: "Suggested by Claude · today · badminton"),
    ], someUnreadable: false, corpusID: ""))
}

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) {
        completion(context.isPreview ? .sample : Self.load())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        // A request, not a promise (P17). The app also reloads the widget whenever its
        // list of open to-dos changes, which is what actually keeps it current.
        let next = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [Self.load()], policy: .after(next)))
    }

    static func load(now: Date = Date()) -> TodoEntry {
        switch WidgetCorpus.resolve() {
        case .failure(let why):
            return TodoEntry(date: now, content: .unknown(reason: TodoWidgetList.reason(for: why)))
        case .success(let corpus):
            do {
                let store = try EventStore(readingExisting: corpus.log)
                let notes = try NoteService(store: store).listNotes(includeArchived: false)
                return TodoEntry(date: now, content: .list(
                    rows: TodoWidgetList.rows(from: notes, now: now),
                    someUnreadable: store.skippedLines > 0,
                    corpusID: corpus.corpusID))
            } catch let why as WidgetCorpus.Unreadable {
                return TodoEntry(date: now, content: .unknown(reason: TodoWidgetList.reason(for: why)))
            } catch {
                return TodoEntry(date: now, content: .unknown(
                    reason: TodoWidgetList.reason(for: .logUnreadable)))
            }
        }
    }
}
