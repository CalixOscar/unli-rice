import XCTest
@testable import UnliRiceCore

final class ProjectionDiagnosticsTests: XCTestCase {
    func testIncompleteNotesAreIsolatedAndClearWhenParentArrives() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        let service = NoteService(store: store)
        let healthy = try service.createNote(title: "Healthy", body: "", source: "human")
        let missing = UUID(), pendingID = UUID(), conflictID = UUID(), a = UUID(), b = UUID()
        let pending = Event(noteId: pendingID, source: "human", kind: .created, title: "Pending", causalParents: [missing])
        let cycleA = Event(id: a, noteId: conflictID, source: "human", kind: .created, title: "Conflict", causalParents: [b])
        let cycleB = Event(id: b, noteId: conflictID, source: "human", kind: .tagged, tag: "x", causalParents: [a])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.appendRawBatch(try [pending, cycleA, cycleB].map { try encoder.encode($0) })
        let snapshot = try service.projectionSnapshot(includeArchived: true)
        XCTAssertEqual(snapshot.diagnostics.pendingNoteIDs, [pendingID])
        XCTAssertEqual(snapshot.diagnostics.conflictedNoteIDs, [conflictID])
        XCTAssertEqual(snapshot.diagnostics.pendingEventIDs, [pending.id])
        XCTAssertEqual(snapshot.diagnostics.incompleteNoteIDs, [pendingID, conflictID])
        XCTAssertEqual(snapshot.diagnostics.summary, "1 note is waiting for earlier changes. 1 note has conflicting history. Other notes are available.")
        XCTAssertTrue(try XCTUnwrap(snapshot.diagnostics.technicalSummary).contains(pendingID.uuidString))
        XCTAssertEqual(snapshot.notes.map(\.id), [healthy.id])
        XCTAssertNotNil(try service.getNote(id: healthy.id))
        XCTAssertEqual(try service.searchNotes(query: "Healthy").map(\.id), [healthy.id])
        XCTAssertTrue(try service.pendingReviews().isEmpty)
        XCTAssertNil(try service.getNote(id: UUID()))
        XCTAssertThrowsError(try service.getNote(id: pendingID)) { error in
            guard case NoteServiceError.orderingPending(let ids) = error else { return XCTFail("\(error)") }; XCTAssertEqual(ids, [pendingID])
        }
        XCTAssertThrowsError(try service.appendToNote(id: pendingID, text: "x", source: "human")) { error in
            guard case NoteServiceError.orderingPending(let ids) = error else { return XCTFail("\(error)") }; XCTAssertEqual(ids, [pendingID])
        }
        XCTAssertThrowsError(try service.getNote(id: conflictID)) { error in
            guard case NoteServiceError.orderingConflict(let ids) = error else { return XCTFail("\(error)") }; XCTAssertEqual(ids, [conflictID])
        }
        XCTAssertThrowsError(try service.tagNote(id: conflictID, tag: "x", source: "human")) { error in
            guard case NoteServiceError.orderingConflict(let ids) = error else { return XCTFail("\(error)") }; XCTAssertEqual(ids, [conflictID])
        }
        _ = try service.tagNote(id: healthy.id, tag: "ok", source: "human")
        _ = try service.createNote(title: "New", body: "", source: "human")
        let second = NoteService(store: try EventStore(fileURL: url))
        XCTAssertEqual(try service.projectionSnapshot().diagnostics, try second.projectionSnapshot().diagnostics)
        let parent = Event(id: missing, noteId: pendingID, source: "human", kind: .tagged, tag: "prior", causalParents: [])
        try store.appendRawBatch([try encoder.encode(parent)])
        XCTAssertNotNil(try service.getNote(id: pendingID))
        XCTAssertEqual(try service.projectionSnapshot().diagnostics, try second.projectionSnapshot().diagnostics)
        service.rebuild()
        XCTAssertEqual(try service.projectionSnapshot().diagnostics, try second.projectionSnapshot().diagnostics)
    }

    func testLinksDoNotResolveToIncompleteNotes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EventStore(fileURL: dir.appendingPathComponent("events.jsonl"))
        let healthy = UUID(), partial = UUID()
        try store.append(Event(noteId: healthy, source: "human", kind: .created, title: "Healthy", text: "[[Incomplete]]", causalParents: []))
        try store.append(Event(noteId: partial, source: "human", kind: .created, title: "Incomplete", text: "[[Healthy]]", causalParents: []))
        try store.append(Event(noteId: partial, source: "human", kind: .appended, text: "pending", causalParents: [UUID()]))
        let result = try XCTUnwrap(NoteService(store: store).getNote(id: healthy))
        XCTAssertTrue(result.outboundLinks.isEmpty)
        XCTAssertTrue(result.backlinks.isEmpty)
        XCTAssertEqual(result.danglingLinks, ["Incomplete"])
    }

    func testTransactionLogFiltersBeforeLimitAndDefaultsToAudit() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try EventStore(fileURL: dir.appendingPathComponent("events.jsonl")), id = UUID()
        let note = Event(noteId: id, timestamp: Date(timeIntervalSince1970: 1), source: "human", kind: .created)
        let metadata = Event(noteId: id, timestamp: Date(timeIntervalSince1970: 2), source: "unlirice", kind: .causalOrder, relatedEventId: note.id, causalParents: [])
        try store.append(note); try store.append(metadata)
        let service = NoteService(store: store)
        XCTAssertEqual(try service.transactionLog(limit: 1).first?.id, metadata.id)
        XCTAssertEqual(try service.transactionLog(limit: 1, includeOrderingMetadata: false).first?.id, note.id)
    }
}
