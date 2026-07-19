import XCTest
@testable import SecondBrainCore

final class NoteServiceTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("secondbrain-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testCreateAndGetNote() throws {
        let created = try service.createNote(title: "Test", body: "Hello world", source: "claude")
        let fetched = try service.getNote(id: created.id)
        XCTAssertEqual(fetched?.title, "Test")
        XCTAssertEqual(fetched?.body, "Hello world")
        XCTAssertEqual(fetched?.sources, ["claude"])
        XCTAssertFalse(fetched?.archived ?? true)
    }

    func testAppendPreservesHistoryAcrossMultipleAgents() throws {
        let note = try service.createNote(title: "Shared", body: "from claude", source: "claude")
        try service.appendToNote(id: note.id, text: "from gemini", source: "gemini")
        try service.appendToNote(id: note.id, text: "from chatgpt", source: "chatgpt")

        let final = try service.getNote(id: note.id)!
        XCTAssertTrue(final.body.contains("from claude"))
        XCTAssertTrue(final.body.contains("from gemini"))
        XCTAssertTrue(final.body.contains("from chatgpt"))
        XCTAssertEqual(final.sources, ["claude", "gemini", "chatgpt"])
    }

    func testTagAndUntagNote() throws {
        let note = try service.createNote(title: "T", body: "B", source: "claude")
        try service.tagNote(id: note.id, tag: "project-x", source: "claude")
        var updated = try service.getNote(id: note.id)!
        XCTAssertTrue(updated.tags.contains("project-x"))

        try service.untagNote(id: note.id, tag: "project-x", source: "claude")
        updated = try service.getNote(id: note.id)!
        XCTAssertFalse(updated.tags.contains("project-x"))
    }

    func testArchiveIsSoftAndReversible() throws {
        let note = try service.createNote(title: "T", body: "B", source: "claude")
        try service.archiveNote(id: note.id, reason: "superseded", source: "claude")

        var archived = try service.getNote(id: note.id)!
        XCTAssertTrue(archived.archived)
        XCTAssertFalse(try service.listNotes(includeArchived: false).contains { $0.id == note.id })
        XCTAssertTrue(try service.listNotes(includeArchived: true).contains { $0.id == note.id })

        try service.unarchiveNote(id: note.id, source: "claude")
        archived = try service.getNote(id: note.id)!
        XCTAssertFalse(archived.archived)
        XCTAssertTrue(try service.listNotes(includeArchived: false).contains { $0.id == note.id })
    }

    func testArchivingNeverRemovesUnderlyingHistory() throws {
        let note = try service.createNote(title: "T", body: "Important content", source: "claude")
        try service.archiveNote(id: note.id, reason: "test", source: "claude")

        // The raw event log must still contain every event — archiving is a
        // projection flag, not a mutation of history.
        let log = try service.transactionLog(limit: 100)
        XCTAssertTrue(log.contains { $0.kind == .created && $0.noteId == note.id })
        XCTAssertTrue(log.contains { $0.kind == .archived && $0.noteId == note.id })

        let stillFetchable = try service.getNote(id: note.id)!
        XCTAssertEqual(stillFetchable.body, "Important content")
    }

    func testFlagForReviewAndResolve() throws {
        let a = try service.createNote(title: "A", body: "duplicate of B", source: "claude")
        try service.flagForReview(id: a.id, reason: "possible duplicate of note B", source: "gemini")

        var pending = try service.pendingReviews()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.flag.source, "gemini")
        XCTAssertFalse(pending.first?.flag.resolved ?? true)

        try service.resolveReview(id: a.id, flagId: pending.first!.flag.id, source: "human")
        pending = try service.pendingReviews()
        XCTAssertEqual(pending.count, 0)
    }

    func testSearchNotesMatchesTitleBodyAndTags() throws {
        let note = try service.createNote(title: "Roof repair notes", body: "shingles and flashing", source: "claude")
        try service.tagNote(id: note.id, tag: "construction", source: "claude")
        _ = try service.createNote(title: "Unrelated", body: "nothing to see", source: "claude")

        XCTAssertEqual(try service.searchNotes(query: "shingles").count, 1)
        XCTAssertEqual(try service.searchNotes(query: "roof").count, 1)
        XCTAssertEqual(try service.searchNotes(query: "construction").count, 1)
        XCTAssertEqual(try service.searchNotes(query: "nope").count, 0)
    }

    func testNoteNotFoundThrows() throws {
        XCTAssertThrowsError(try service.appendToNote(id: UUID(), text: "x", source: "claude"))
    }

    func testEventLogSurvivesReopenAndReprojectsIdentically() throws {
        let note = try service.createNote(title: "Persisted", body: "v1", source: "claude")
        try service.appendToNote(id: note.id, text: "v2", source: "gemini")
        try service.tagNote(id: note.id, tag: "durable", source: "claude")

        // Simulate a fresh device / restart: reopen the same file, rebuild
        // everything purely by replaying events.
        let reopenedStore = try EventStore(fileURL: tempURL)
        let reopenedService = NoteService(store: reopenedStore)
        let reprojected = try reopenedService.getNote(id: note.id)!

        XCTAssertEqual(reprojected.body, try service.getNote(id: note.id)!.body)
        XCTAssertEqual(reprojected.tags, ["durable"])
        XCTAssertEqual(reprojected.sources, ["claude", "gemini"])
    }
}
