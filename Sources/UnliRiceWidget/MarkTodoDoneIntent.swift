import AppIntents
import Foundation
import UnliRiceCore
import WidgetKit

/// The widget's Done button (B4).
///
/// Both parameters are captured when the row is drawn. The corpus is re-resolved and the
/// note re-checked at tap time, so a repeated tap, a stale row, or a row drawn from a
/// different notes folder writes nothing (P6).
struct MarkTodoDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a to-do as done"
    static var isDiscoverable = false

    @Parameter(title: "To-do") var noteID: String
    @Parameter(title: "Notes folder") var corpusID: String

    init() {}

    init(noteID: UUID, corpusID: String) {
        self.noteID = noteID.uuidString
        self.corpusID = corpusID
    }

    enum Failure: Error { case rowFromAnotherFolder, badID }

    func perform() async throws -> some IntentResult {
        defer { WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetList.kind) }

        guard let id = UUID(uuidString: noteID) else { throw Failure.badID }
        guard case .success(let corpus) = WidgetCorpus.resolve(), corpus.corpusID == corpusID else {
            throw Failure.rowFromAnotherFolder
        }
        let service = NoteService(store: try EventStore(readingExisting: corpus.log))
        if try TodoDone.markDone(noteID: id, service: service) == .archived {
            // An open app doesn't re-read the log by itself (P4). If the sandbox drops
            // this, the app's reload on becoming active is the fallback.
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(TodoWidgetList.changedNotification as CFString),
                nil, nil, true)
        }
        return .result()
    }
}
