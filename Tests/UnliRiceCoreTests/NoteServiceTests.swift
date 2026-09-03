import XCTest
@testable import UnliRiceCore

final class NoteServiceTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-tests-\(UUID().uuidString)")
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
        // The set says who touched it; only `creator` says who wrote it, which
        // is what the retrospective's contributor list counts.
        XCTAssertEqual(final.creator, "claude")
        XCTAssertEqual(final.editors, ["gemini", "chatgpt"])
    }

    /// The janitor never writes a word — it tags, files, and flags. That work
    /// leaves no mark on the body or on `sources`, so `editors` is the only
    /// place it can be counted.
    func testWorkThatChangesNoTextStillNamesWhoDidIt() throws {
        let note = try service.createNote(title: "T", body: "B", source: "claude")
        try service.tagNote(id: note.id, tag: "memory", source: "janitor")
        try service.archiveNote(id: note.id, reason: "duplicate", source: "human")
        // Its own author is not one of its editors.
        try service.appendToNote(id: note.id, text: "more", source: "claude")

        let final = try service.getNote(id: note.id)!
        XCTAssertEqual(final.editors, ["janitor", "human"])
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

    func testResolveReviewRecordsOutcome() throws {
        let a = try service.createNote(title: "A", body: "duplicate of B", source: "claude")
        try service.flagForReview(id: a.id, reason: "possible duplicate of note B", source: "gemini")
        let flagId = try service.pendingReviews().first!.flag.id

        try service.resolveReview(id: a.id, flagId: flagId, source: "human", outcome: "rejected")

        let resolveEvent = try service.transactionLog().first { $0.kind == .reviewResolved }
        XCTAssertEqual(resolveEvent?.reason, "rejected")
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

    // MARK: - Wiki-links

    func testLinkResolvesToNoteCreatedLaterInTheLog() throws {
        // The forward reference is the whole reason link resolution is a second
        // pass — "Target" does not exist yet when "Source" is written.
        let source = try service.createNote(title: "Source", body: "see [[Target]]", source: "human")
        let target = try service.createNote(title: "Target", body: "the destination", source: "human")

        let resolved = try service.getNote(id: source.id)!
        XCTAssertEqual(resolved.outboundLinks, [target.id])
        XCTAssertTrue(resolved.danglingLinks.isEmpty)
    }

    func testBacklinksAreBidirectional() throws {
        let target = try service.createNote(title: "Hub", body: "central note", source: "human")
        let a = try service.createNote(title: "A", body: "refs [[Hub]]", source: "human")
        let b = try service.createNote(title: "B", body: "also refs [[hub]]", source: "human")

        let hub = try service.getNote(id: target.id)!
        XCTAssertEqual(hub.backlinks, [a.id, b.id])
        XCTAssertTrue(hub.outboundLinks.isEmpty)
    }

    func testLinkResolvesByRawUUID() throws {
        let target = try service.createNote(title: "Target", body: "x", source: "human")
        let source = try service.createNote(title: "Source", body: "see [[\(target.id.uuidString)]]", source: "human")

        XCTAssertEqual(try service.getNote(id: source.id)!.outboundLinks, [target.id])
    }

    func testUnresolvableLinkIsDanglingNotAnError() throws {
        let note = try service.createNote(title: "Orphan", body: "points at [[Nothing At All]]", source: "human")

        let projected = try service.getNote(id: note.id)!
        XCTAssertTrue(projected.outboundLinks.isEmpty)
        XCTAssertEqual(projected.danglingLinks, ["Nothing At All"])
    }

    func testMalformedLinkSyntaxIsIgnored() throws {
        let note = try service.createNote(
            title: "Messy",
            body: "unterminated [[ and empty [[]] and [[Messy]] self-link",
            source: "human"
        )

        let projected = try service.getNote(id: note.id)!
        XCTAssertTrue(projected.outboundLinks.isEmpty, "a note linking to itself is not a relationship")
        XCTAssertTrue(projected.danglingLinks.isEmpty)
    }

    func testLinksSurviveAppendAndTrackNewText() throws {
        let target = try service.createNote(title: "Target", body: "x", source: "human")
        let note = try service.createNote(title: "Grower", body: "nothing yet", source: "human")
        XCTAssertTrue(try service.getNote(id: note.id)!.outboundLinks.isEmpty)

        try service.appendToNote(id: note.id, text: "now it mentions [[Target]]", source: "claude")

        XCTAssertEqual(try service.getNote(id: note.id)!.outboundLinks, [target.id])
        XCTAssertEqual(try service.getNote(id: target.id)!.backlinks, [note.id])
    }

    func testNoteHistoryReturnsOnlyThatNotesEventsOldestFirst() throws {
        let note = try service.createNote(title: "History", body: "first", source: "human")
        _ = try service.createNote(title: "Other", body: "unrelated", source: "claude")
        try service.appendToNote(id: note.id, text: "second", source: "codex")
        try service.tagNote(id: note.id, tag: "audit", source: "human")

        let history = try service.noteHistory(id: note.id)

        XCTAssertEqual(history.map(\.kind), [.created, .appended, .tagged])
        XCTAssertEqual(history.map(\.source), ["human", "codex", "human"])
        XCTAssertEqual(history.compactMap(\.text), ["first", "second"])
    }

    // MARK: - Cross-process write safety

    func testConcurrentAppendsFromMultipleStoresDoNotCorruptTheLog() throws {
        // Simulates what happens once several MCP clients (Claude Code, Codex,
        // Antigravity, ...) each run their own unlirice-mcp process against
        // the same events.jsonl: independent EventStore instances, each with
        // its own in-process queue, writing concurrently. `flock` — not the
        // queue — is what has to keep this safe; this is a regression test for
        // the old seek-then-write race that could interleave/corrupt lines.
        let raceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-race-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        defer { try? FileManager.default.removeItem(at: raceURL.deletingLastPathComponent()) }

        let writers = 8
        let eventsPerWriter = 25
        let noteId = UUID()
        let stores = try (0..<writers).map { _ in try EventStore(fileURL: raceURL) }

        DispatchQueue.concurrentPerform(iterations: writers * eventsPerWriter) { i in
            let store = stores[i % writers]
            let event = Event(noteId: noteId, source: "writer-\(i % writers)", kind: .tagged, tag: "t\(i)")
            try? store.append(event)
        }

        let expectedCount = writers * eventsPerWriter
        let rawLineCount = try String(contentsOf: raceURL, encoding: .utf8)
            .split(separator: "\n")
            .count
        XCTAssertEqual(rawLineCount, expectedCount, "no line should be dropped or merged with another")

        let decoded = try EventStore(fileURL: raceURL).readAll()
        XCTAssertEqual(decoded.count, expectedCount, "every line must still be valid, parseable JSON")
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

    // MARK: - Plan §6 Tests (18, 20)

    func testTransactionLogNegativeLimitThrows() throws {
        XCTAssertThrowsError(try service.transactionLog(limit: -1)) { error in
            guard let serviceError = error as? NoteServiceError,
                  case .invalidLimit(let val) = serviceError else {
                return XCTFail("Expected NoteServiceError.invalidLimit(-1), got \(error)")
            }
            XCTAssertEqual(val, -1)
        }
    }

    func testTransactionLogZeroLimitReturnsEmpty() throws {
        _ = try service.createNote(title: "Note", body: "Body", source: "claude")
        let logs = try service.transactionLog(limit: 0)
        XCTAssertEqual(logs.count, 0)
    }

    /// `appendRaw` reports a failed write instead of swallowing it.
    ///
    /// `CaptureStore` now treats "every event reached `events.jsonl`" as the definition
    /// of a saved note, and throws when it did not — which is only worth anything if
    /// this can actually fail. It used to be called as `try?` in two places, so a note
    /// that never reached the log was reported as saved and then vanished at the next
    /// rebuild. If this test ever starts failing because `appendRaw` became infallible,
    /// that durable-success guarantee is hollow.
    func testAppendRawThrowsWhenTheLogCannotBeOpened() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-append-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let logURL = dir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: logURL)

        // The directory goes away underneath it, so open(O_CREAT) fails with ENOENT.
        try FileManager.default.removeItem(at: dir)

        XCTAssertThrowsError(try store.appendRaw(Data("{}".utf8))) { error in
            XCTAssertEqual(error as? EventStoreError, .fileUnavailable)
        }
    }
}
