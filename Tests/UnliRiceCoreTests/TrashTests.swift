import XCTest
@testable import UnliRiceCore

/// The only operation in this codebase that can lose a note, so it gets the
/// most direct tests: not "does it return the right receipt" but "is the note
/// gone, is everything else untouched, and can I get it back".
final class TrashTests: XCTestCase {
    var tempURL: URL!
    var store: EventStore!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-trash-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testPurgeRemovesOnlyTheTargetedNote() throws {
        let doomed = try service.createNote(title: "Doomed", body: "junk", source: "human")
        let keeper = try service.createNote(title: "Keeper", body: "important", source: "human")
        try service.tagNote(id: doomed.id, tag: "noise", source: "human")

        let receipt = try TrashService.purge(noteIDs: [doomed.id], logURL: tempURL)

        XCTAssertEqual(receipt.notesPurged, 1)
        // created + tagged.
        XCTAssertEqual(receipt.eventsRemoved, 2)

        let remaining = try service.listNotes(includeArchived: true)
        XCTAssertEqual(remaining.map(\.id), [keeper.id])
        XCTAssertEqual(try service.getNote(id: doomed.id)?.title, nil)
    }

    func testPurgeBacksUpTheWholeLogBeforeRewritingIt() throws {
        let doomed = try service.createNote(title: "Doomed", body: "junk", source: "human")
        _ = try service.createNote(title: "Keeper", body: "important", source: "human")
        let before = try Data(contentsOf: tempURL)

        let receipt = try TrashService.purge(noteIDs: [doomed.id], logURL: tempURL)

        // Byte-identical: the promise the confirmation dialog makes is that the
        // log as it stood is recoverable, not that an equivalent one is.
        XCTAssertEqual(try Data(contentsOf: receipt.backupURL), before)
        XCTAssertNotEqual(try Data(contentsOf: tempURL), before)
    }

    func testTrashedNoteKeepsItsFullHistoryAndCanBeRestored() throws {
        let note = try service.createNote(title: "Second thoughts", body: "first", source: "human")
        try service.appendToNote(id: note.id, text: "second", source: "claude")
        try service.tagNote(id: note.id, tag: "keep", source: "claude")
        let beforePurge = try XCTUnwrap(service.getNote(id: note.id))

        try TrashService.purge(noteIDs: [note.id], logURL: tempURL)
        XCTAssertNil(try service.getNote(id: note.id))

        let trashed = TrashService.listTrashed(forLog: tempURL)
        XCTAssertEqual(trashed.count, 1)
        XCTAssertEqual(trashed[0].title, "Second thoughts")
        XCTAssertEqual(trashed[0].events.count, 3)

        try TrashService.restore(noteID: note.id, logURL: tempURL, into: store)

        // The projection has to come back *identical*, not merely present —
        // that's what makes this recoverable rather than approximately
        // recoverable. Body, tags, and both contributing sources included.
        let restored = try XCTUnwrap(service.getNote(id: note.id))
        XCTAssertEqual(restored.title, beforePurge.title)
        XCTAssertEqual(restored.body, beforePurge.body)
        XCTAssertEqual(restored.tags, beforePurge.tags)
        XCTAssertEqual(restored.sources, beforePurge.sources)
        XCTAssertTrue(TrashService.listTrashed(forLog: tempURL).isEmpty)
    }

    func testPurgingSeveralNotesAtOnce() throws {
        let a = try service.createNote(title: "A", body: "", source: "human")
        let b = try service.createNote(title: "B", body: "", source: "human")
        let c = try service.createNote(title: "C", body: "", source: "human")

        let receipt = try TrashService.purge(noteIDs: [a.id, c.id], logURL: tempURL)

        XCTAssertEqual(receipt.notesPurged, 2)
        XCTAssertEqual(try service.listNotes(includeArchived: true).map(\.title), ["B"])
        XCTAssertEqual(receipt.trashURLs.count, 2)
        _ = b
    }

    func testPurgingUnknownIDsChangesNothing() throws {
        _ = try service.createNote(title: "Keeper", body: "", source: "human")
        let before = try Data(contentsOf: tempURL)

        XCTAssertThrowsError(try TrashService.purge(noteIDs: [UUID()], logURL: tempURL))

        // Not just "it threw": a no-op purge must not have written a backup or
        // truncated anything on its way to failing.
        XCTAssertEqual(try Data(contentsOf: tempURL), before)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: TrashService.backupDirectory(forLog: tempURL).path
            )
        )
    }

    func testPurgeIsRefusedWithNoIDs() {
        XCTAssertThrowsError(try TrashService.purge(noteIDs: [], logURL: tempURL))
    }

    func testSurvivingLinesAreNotReformatted() throws {
        let doomed = try service.createNote(title: "Doomed", body: "", source: "human")
        _ = try service.createNote(title: "Keeper", body: "has \"quotes\" and ünïcode", source: "human")

        let keptLineBefore = try String(contentsOf: tempURL, encoding: .utf8)
            .split(separator: "\n")
            .first { $0.contains("Keeper") }

        try TrashService.purge(noteIDs: [doomed.id], logURL: tempURL)

        let keptLineAfter = try String(contentsOf: tempURL, encoding: .utf8)
            .split(separator: "\n")
            .first { $0.contains("Keeper") }
        XCTAssertEqual(keptLineBefore, keptLineAfter)
    }
}
