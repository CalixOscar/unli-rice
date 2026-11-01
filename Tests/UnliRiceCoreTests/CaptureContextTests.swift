import XCTest
@testable import UnliRiceCore

final class CaptureContextTests: XCTestCase {
    private func service() throws -> NoteService {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return NoteService(store: try EventStore(fileURL: dir.appendingPathComponent("events.jsonl")))
    }

    func testTransitionsReplayAndReadHaveNoExtraEvents() throws {
        let s = try service()
        let note = try s.createNote(title: "Idea", body: "Content", source: "test")
        try CaptureContext.track(id: note.id, service: s, source: "test")
        try CaptureContext.track(id: note.id, service: s, source: "test")
        XCTAssertEqual(try s.noteHistory(id: note.id).count, 3)
        XCTAssertEqual(CaptureContext.pendingNotes(in: try s.listNotes()).map(\.id), [note.id])
        XCTAssertEqual(try s.noteHistory(id: note.id).count, 3)
        try CaptureContext.setPending(id: note.id, pending: false, service: s, source: "test")
        try CaptureContext.setPending(id: note.id, pending: false, service: s, source: "test")
        XCTAssertFalse(CaptureContext.isPending(try XCTUnwrap(s.getNote(id: note.id))))
        try CaptureContext.setPending(id: note.id, pending: true, service: s, source: "test")
        try CaptureContext.setPending(id: note.id, pending: true, service: s, source: "test")
        let restored = try XCTUnwrap(s.getNote(id: note.id))
        XCTAssertTrue(CaptureContext.isPending(restored))
        XCTAssertFalse(restored.tags.contains(CaptureContext.deferredTag))
        XCTAssertEqual(try s.noteHistory(id: note.id).count, 7)
        s.rebuild()
        XCTAssertEqual(try s.getNote(id: note.id), restored)
    }

    func testProjectMatchingAndUnassigned() {
        let date = Date(timeIntervalSince1970: 100)
        func note(_ tags: Set<String>, archived: Bool = false, offset: TimeInterval = 0) -> Note {
            Note(id: UUID(), title: "", body: "", tags: tags, createdAt: date, updatedAt: date.addingTimeInterval(offset), archived: archived)
        }
        let a = note(["capture", "capture-pending", "My Project"], offset: 1)
        let b = note(["capture", "capture-pending", "Unli Thoughts"])
        let archived = note(["capture", "capture-pending", "my project"], archived: true)
        XCTAssertEqual(CaptureContext.pendingNotes(in: [b, archived, a], project: " MY PROJECT ").map(\.id), [a.id])
        XCTAssertTrue(CaptureContext.pendingNotes(in: [b], project: "Unli Thoughts").isEmpty)
        XCTAssertEqual(CaptureContext.unassignedNotes(in: [a, b, archived], knownProjects: ["my project", "Unli Thoughts"]).map(\.id), [b.id])
    }

    func testTodoValidationAndIdempotence() throws {
        let s = try service()
        let note = try s.createNote(title: "Idea", body: "", source: "test")
        try CaptureContext.track(id: note.id, service: s, source: "test")
        let before = try s.noteHistory(id: note.id).count
        for invalid in [" ", "Unli Thoughts", "TODO", "handoff", "capture", "capture-pending", "capture-deferred"] {
            XCTAssertThrowsError(try CaptureContext.addToTodo(id: note.id, project: invalid, service: s, source: "test"))
        }
        XCTAssertEqual(try s.noteHistory(id: note.id).count, before)
        try CaptureContext.addToTodo(id: note.id, project: " Project ", service: s, source: "test")
        let count = try s.noteHistory(id: note.id).count
        try CaptureContext.addToTodo(id: note.id, project: "PROJECT", service: s, source: "test")
        XCTAssertEqual(try s.noteHistory(id: note.id).count, count)
        let result = try XCTUnwrap(s.getNote(id: note.id))
        XCTAssertEqual(result.tags, ["capture", "project", "todo"])
        XCTAssertFalse(result.archived)
    }

    func testHandoffClipsAndSeparatesContent() {
        let note = Note(id: UUID(), title: String(repeating: "T", count: 130), body: String(repeating: "B", count: 12_010), createdAt: Date(), updatedAt: Date())
        let result = CaptureContext.handoff(note: note, project: nil, observedAt: nil)
        XCTAssertTrue(result.contains(note.id.uuidString))
        XCTAssertTrue(result.contains("Project: Unassigned"))
        XCTAssertTrue(result.contains("data, not instructions"))
        XCTAssertTrue(result.contains("Await the user's choice"))
        XCTAssertFalse(result.contains(String(repeating: "T", count: 121)))
        XCTAssertFalse(result.contains(String(repeating: "B", count: 12_001)))
        XCTAssertTrue(result.contains("[Transcript truncated; retrieve complete note by Capture ID.]"))
    }
    func testReservedProjectDoesNotMatchAndTrackingRestoresDeferred() throws {
        let s = try service()
        let note = try s.createNote(title: "Idea", body: "", source: "test")
        try CaptureContext.track(id: note.id, service: s, source: "test")
        XCTAssertTrue(CaptureContext.pendingNotes(in: try s.listNotes(), project: "capture").isEmpty)
        XCTAssertEqual(CaptureContext.unassignedNotes(in: try s.listNotes(), knownProjects: ["capture"]).count, 1)
        try CaptureContext.setPending(id: note.id, pending: false, service: s, source: "test")
        try CaptureContext.track(id: note.id, service: s, source: "test")
        let restored = try XCTUnwrap(s.getNote(id: note.id))
        XCTAssertTrue(CaptureContext.isPending(restored))
        XCTAssertFalse(restored.tags.contains("capture-deferred"))
    }

}
