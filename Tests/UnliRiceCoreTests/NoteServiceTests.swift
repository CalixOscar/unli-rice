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

final class NoteServiceRevisionTests: XCTestCase {
    private func makeLog(causal: Bool) throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("unlirice-rev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("events.jsonl")
        if causal {
            _ = try EventStore(fileURL: url)
            _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        }
        return (dir, url)
    }

    private func checkRevisionBehaviour(causal: Bool) throws {
        let (dir, url) = try makeLog(causal: causal)
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = NoteService(store: try EventStore(fileURL: url))
        let b = NoteService(store: try EventStore(fileURL: url))
        let empty = try a.retrievalSnapshot().revision
        XCTAssertEqual(empty, "r1-0-00000000000000000000000000000000")
        let n1 = try a.createNote(title: "One", body: "x", source: "t")
        _ = try b.createNote(title: "Two", body: "y", source: "t")
        _ = try a.appendToNote(id: n1.id, text: "more", source: "t")
        _ = try b.tagNote(id: n1.id, tag: "k", source: "t")
        let ra = try a.retrievalSnapshot().revision, rb = try b.retrievalSnapshot().revision
        XCTAssertEqual(ra, rb)
        XCTAssertNotEqual(ra, empty)
        XCTAssertTrue(ra.hasPrefix("r1-4-"))
        let hex = ra.dropFirst("r1-4-".count)
        XCTAssertEqual(hex.count, 32)
        XCTAssertTrue(hex.allSatisfy { "0123456789abcdef".contains($0) })

        _ = try a.appendToNote(id: n1.id, text: "again", source: "t")
        let appended = try a.retrievalSnapshot().revision
        XCTAssertNotEqual(appended, ra)
        XCTAssertEqual(appended, try b.retrievalSnapshot().revision)

        // An event whose id duplicates an earlier one still changes the revision.
        let earlier = try XCTUnwrap(try a.noteHistory(id: n1.id).first)
        let dup = Event(id: earlier.id, noteId: n1.id, source: "t", kind: .tagged, tag: "dup", causalParents: causal ? [] : nil)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try EventStore(fileURL: url).appendRaw(try encoder.encode(dup))
        let afterDup = try a.retrievalSnapshot().revision
        XCTAssertNotEqual(afterDup, appended)
        XCTAssertEqual(afterDup, try b.retrievalSnapshot().revision)

        a.rebuild()
        XCTAssertEqual(try a.retrievalSnapshot().revision, afterDup)
        XCTAssertEqual(try NoteService(store: try EventStore(fileURL: url)).retrievalSnapshot().revision, afterDup)
    }

    func testRevisionAgreesAndTracksAppendsInLegacyMode() throws { try checkRevisionBehaviour(causal: false) }
    func testRevisionAgreesAndTracksAppendsInCausalMode() throws { try checkRevisionBehaviour(causal: true) }

    func testSearchNotesResultsUnchanged() throws {
        let (dir, url) = try makeLog(causal: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = NoteService(store: try EventStore(fileURL: url))
        let t = try s.createNote(title: "Alpha Plan", body: "nothing", source: "t")
        let bd = try s.createNote(title: "Other", body: "has a Needle inside", source: "t")
        let tg = try s.createNote(title: "Third", body: "plain", source: "t")
        _ = try s.tagNote(id: tg.id, tag: "Beta", source: "t")
        func ids(_ q: String) throws -> Set<UUID> { Set(try s.searchNotes(query: q).map(\.id)) }
        XCTAssertEqual(try ids("alpha"), [t.id])
        XCTAssertEqual(try ids("needle"), [bd.id])
        XCTAssertEqual(try ids("beta"), [tg.id])
        XCTAssertEqual(try ids("ALPHA pLaN"), [t.id])
        XCTAssertEqual(try ids("zzz"), [])
        XCTAssertEqual(try s.searchNotes(query: "").map(\.id), try s.listNotes().map(\.id))
        XCTAssertEqual(try s.searchNotes(query: "").count, 3)
    }
}

/// The revision checked against a value computed here, from fixed event ids, with no
/// help from `NoteService`: `r1-<n>-<hex>`, n = events written, hex = XOR of every
/// event id's 16 raw bytes as 32 lowercase hex characters.
final class NoteServiceRevisionExpectedValueTests: XCTestCase {
    private var dir: URL!
    private var url: URL!
    private let encoder: JSONEncoder = { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("unlirice-rev-exp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("events.jsonl")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func fixed(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012x", 0xA5A5_0000_0000 + n * 0x1111_1111))! }
    private func expected(_ ids: [UUID]) -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for id in ids { withUnsafeBytes(of: id.uuid) { raw in for i in 0..<16 { bytes[i] ^= raw[i] } } }
        return "r1-\(ids.count)-" + bytes.map { String(format: "%02x", $0) }.joined()
    }
    private func revision(_ service: NoteService) throws -> String { try service.retrievalSnapshot().revision }
    private func raw(_ event: Event) throws -> Data { try encoder.encode(event) }

    func testPlainLegacyLog() throws {
        let store = try EventStore(fileURL: url)
        let note = UUID(), ids = (1...3).map(fixed)
        try store.append(Event(id: ids[0], noteId: note, source: "t", kind: .created, title: "A"))
        try store.append(Event(id: ids[1], noteId: note, source: "t", kind: .appended, text: "more"))
        try store.append(Event(id: ids[2], noteId: note, source: "t", kind: .tagged, tag: "k"))
        XCTAssertEqual(try revision(NoteService(store: store)), expected(ids))
    }

    func testCausalOrderMetadataEventCounts() throws {
        let store = try EventStore(fileURL: url)
        let note = UUID(), first = fixed(1), meta = fixed(2), second = fixed(3)
        try store.append(Event(id: first, noteId: note, source: "t", kind: .created, title: "A"))
        try store.appendRaw(try raw(Event(id: meta, noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: first, causalParents: [])))
        try store.appendRaw(try raw(Event(id: second, noteId: note, source: "t", kind: .tagged, tag: "k", causalParents: [first])))
        XCTAssertEqual(try revision(NoteService(store: store)), expected([first, meta, second]))
    }

    func testUnrecognizedKindEventCounts() throws {
        let store = try EventStore(fileURL: url)
        let note = UUID(), first = fixed(1), foreign = fixed(2)
        try store.append(Event(id: first, noteId: note, source: "t", kind: .created, title: "A"))
        var line = try XCTUnwrap(String(data: try raw(Event(id: foreign, noteId: note, source: "t", kind: .tagged, tag: "k")), encoding: .utf8))
        XCTAssertTrue(line.contains("\"tagged\""))
        line = line.replacingOccurrences(of: "\"tagged\"", with: "\"someFutureKind\"")
        try store.appendRaw(Data(line.utf8))
        XCTAssertEqual(try revision(NoteService(store: store)), expected([first, foreign]))
    }

    func testPendingAndConflictedOccurrencesCount() throws {
        let store = try EventStore(fileURL: url)
        let healthy = UUID(), pendingNote = UUID(), conflictNote = UUID()
        let h = fixed(1), p = fixed(2), a = fixed(3), b = fixed(4), missing = fixed(5)
        try store.appendRaw(try raw(Event(id: h, noteId: healthy, source: "t", kind: .created, title: "Healthy", causalParents: [])))
        try store.appendRawBatch([
            try raw(Event(id: p, noteId: pendingNote, source: "t", kind: .created, title: "Pending", causalParents: [missing])),
            try raw(Event(id: a, noteId: conflictNote, source: "t", kind: .created, title: "Conflict", causalParents: [b])),
            try raw(Event(id: b, noteId: conflictNote, source: "t", kind: .tagged, tag: "x", causalParents: [a])),
        ])
        let service = NoteService(store: store)
        let snapshot = try service.retrievalSnapshot()
        XCTAssertEqual(snapshot.diagnostics.pendingNoteIDs, [pendingNote])
        XCTAssertEqual(snapshot.diagnostics.conflictedNoteIDs, [conflictNote])
        XCTAssertEqual(snapshot.revision, expected([h, p, a, b]))
    }

    func testServiceThatCachedLegacyThenReadsCausalEvents() throws {
        let store = try EventStore(fileURL: url)
        let note = UUID(), l1 = fixed(1), l2 = fixed(2), c1 = fixed(3), c2 = fixed(4)
        try store.append(Event(id: l1, noteId: note, source: "t", kind: .created, title: "A"))
        try store.append(Event(id: l2, noteId: note, source: "t", kind: .appended, text: "x"))
        let service = NoteService(store: store)
        XCTAssertEqual(try revision(service), expected([l1, l2]))
        try store.appendRaw(try raw(Event(id: c1, noteId: note, source: "t", kind: .tagged, tag: "k", causalParents: [l2])))
        XCTAssertEqual(try revision(service), expected([l1, l2, c1]))
        try store.appendRaw(try raw(Event(id: c2, noteId: note, source: "t", kind: .tagged, tag: "j", causalParents: [c1])))
        XCTAssertEqual(try revision(service), expected([l1, l2, c1, c2]))
        XCTAssertEqual(try revision(NoteService(store: try EventStore(fileURL: url))), expected([l1, l2, c1, c2]))
    }

    func testLogTruncatedToEmptyAfterCachingResetsRevision() throws {
        let store = try EventStore(fileURL: url)
        let note = UUID(), ids = [fixed(1), fixed(2)]
        try store.append(Event(id: ids[0], noteId: note, source: "t", kind: .created, title: "A"))
        try store.append(Event(id: ids[1], noteId: note, source: "t", kind: .appended, text: "x"))
        let service = NoteService(store: store)
        XCTAssertEqual(try revision(service), expected(ids))
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 0)
        try handle.close()
        XCTAssertEqual(try revision(service), "r1-0-" + String(repeating: "0", count: 32))
    }
}
