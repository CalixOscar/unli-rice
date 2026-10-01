import AppIntents
import Foundation
import UnliRiceCore
import WidgetKit

/// The phone widget's Done circle. The widget can't reach Capture's notes, so it queues
/// the tap; the row disappears at once, and Capture archives the note on its next sync,
/// which is also what carries the "done" back to the Mac.
struct CaptureMarkDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Mark a to-do as done"
    static var isDiscoverable = false

    @Parameter(title: "To-do") var noteID: String

    init() {}

    init(noteID: UUID) {
        self.noteID = noteID.uuidString
    }

    enum Failure: Error { case badID, noSharedStorage }

    func perform() async throws -> some IntentResult {
        defer { WidgetCenter.shared.reloadTimelines(ofKind: PhoneTodoWidget.kind) }
        guard let id = UUID(uuidString: noteID) else { throw Failure.badID }
        guard let dir = PhoneTodoWidget.containerURL() else { throw Failure.noSharedStorage }
        try PhoneTodoWidget.queueDone(id, in: dir)
        return .result()
    }
}
