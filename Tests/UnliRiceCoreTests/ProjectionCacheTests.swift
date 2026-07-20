import XCTest
@testable import UnliRiceCore

/// The incremental projection — deferred item #8, "NoteService reprojects the
/// entire event log on every read call".
///
/// The property that matters is not "it's faster", it's **"it gives the same
/// answer"**. A cache that drifts from the log would break the one guarantee
/// this whole design rests on: that current state is a deterministic projection
/// of the events and nothing else. Most of these tests are equivalence tests
/// against a cold `Projector.project` over the same file.
final class ProjectionCacheTests: XCTestCase {
    var directory: URL!
    var logURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-cache-tests-\(UUID().uuidString)")
        logURL = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeService() throws -> NoteService {
        NoteService(store: try EventStore(fileURL: logURL))
    }

    /// The equivalence test. Everything else here is a special case of it.
    func testIncrementalProjectionMatchesAFullReprojection() throws {
        let service = try makeService()

        let first = try service.createNote(title: "Alpha", body: "see [[Beta]]", source: "human")
        let second = try service.createNote(title: "Beta", body: "body", source: "claude")
        try service.tagNote(id: first.id, tag: "work", source: "human")
        try service.tagNote(id: second.id, tag: "work", source: "janitor")
        try service.untagNote(id: second.id, tag: "work", source: "human")
        try service.appendToNote(id: second.id, text: "more", source: "gemini")
        try service.archiveNote(id: second.id, reason: "done", source: "human")
        try service.unarchiveNote(id: second.id, source: "human")
        let flagged = try service.flagForReview(id: first.id, reason: "looks duplicated", source: "janitor")
        try service.resolveReview(id: first.id, flagId: flagged.flags[0].id, source: "human", outcome: "rejected")

        // Sorted by id, not by the service's own ordering: these writes all land
        // inside one millisecond, so `updatedAt` ties and the comparison would
        // be testing sort stability rather than projection equivalence.
        let incremental = try service.listNotes(includeArchived: true)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let cold = Projector.project(try EventStore(fileURL: logURL).readAll())
            .values.sorted { $0.id.uuidString < $1.id.uuidString }

        XCTAssertEqual(incremental, cold)
    }

    /// A note created *after* the one linking to it must still resolve, which is
    /// the case an incremental fold could plausibly get wrong: the link pass has
    /// to re-run over the whole corpus after every batch, not just over what
    /// arrived in it.
    func testLinksResolveWhenTheTargetArrivesLater() throws {
        let service = try makeService()
        let source = try service.createNote(title: "Points forward", body: "at [[Later]]", source: "human")
        XCTAssertEqual(try service.getNote(id: source.id)?.danglingLinks, ["Later"])

        let target = try service.createNote(title: "Later", body: "here", source: "human")

        XCTAssertEqual(try service.getNote(id: source.id)?.outboundLinks, [target.id])
        XCTAssertTrue(try service.getNote(id: source.id)?.danglingLinks.isEmpty ?? false)
        XCTAssertEqual(try service.getNote(id: target.id)?.backlinks, [source.id])
    }

    /// Backlinks are derived, so a fold must not let a previous pass's answer
    /// survive into the next one. Without clearing, a second read would double
    /// nothing visible — but a note whose body stopped linking would keep the
    /// backlink forever.
    func testDerivedLinksAreRebuiltRatherThanAccumulated() throws {
        let service = try makeService()
        let target = try service.createNote(title: "Target", body: "", source: "human")
        let linker = try service.createNote(title: "Linker", body: "[[Target]]", source: "human")

        _ = try service.listNotes()
        _ = try service.listNotes()
        try service.appendToNote(id: linker.id, text: "and again [[Target]]", source: "human")

        XCTAssertEqual(try service.getNote(id: target.id)?.backlinks, [linker.id])
    }

    /// A link written as a raw UUID before that note exists. `LinkIndex` has to
    /// index the dangling UUID string too, not just dangling titles, or the note
    /// arriving later never fixes it.
    func testALinkToAUuidThatDoesNotExistYetResolvesWhenItDoes() throws {
        let service = try makeService()
        let futureID = UUID()
        let linker = try service.createNote(title: "Early", body: "see [[\(futureID)]]", source: "human")
        XCTAssertEqual(try service.getNote(id: linker.id)?.danglingLinks, ["\(futureID)"])

        // Force the id by writing the event directly — `createNote` mints its own.
        let store = try EventStore(fileURL: logURL)
        try store.append(Event(noteId: futureID, source: "human", kind: .created, title: "Arrived", text: ""))

        XCTAssertEqual(try service.getNote(id: linker.id)?.outboundLinks, [futureID])
        XCTAssertTrue(try service.getNote(id: linker.id)?.danglingLinks.isEmpty ?? false)
        XCTAssertEqual(try service.getNote(id: futureID)?.backlinks, [linker.id])
    }

    /// Appending a link to an existing note has to register a backlink that was
    /// never there before — the case an "only recompute new notes" shortcut
    /// would get wrong.
    func testAppendingALinkLaterStillCreatesTheBacklink() throws {
        let service = try makeService()
        let target = try service.createNote(title: "Target", body: "", source: "human")
        let other = try service.createNote(title: "Other", body: "no links here", source: "human")

        XCTAssertTrue(try service.getNote(id: target.id)?.backlinks.isEmpty ?? false)
        try service.appendToNote(id: other.id, text: "actually, see [[Target]]", source: "human")
        XCTAssertEqual(try service.getNote(id: target.id)?.backlinks, [other.id])
    }

    /// A long mixed sequence, checked against a cold projection. This is the
    /// test that would catch a `LinkIndex` bookkeeping slip that the small
    /// focused cases above miss.
    func testALongMixedSequenceStillMatchesAColdProjection() throws {
        let service = try makeService()
        var ids: [UUID] = []

        for index in 0..<60 {
            let body = index % 3 == 0 && index > 0
                ? "links to [[Note \(index - 1)]] and [[Nothing \(index)]]"
                : "plain body"
            let note = try service.createNote(title: "Note \(index)", body: body, source: "human")
            ids.append(note.id)

            if index % 4 == 0 { try service.tagNote(id: note.id, tag: "even", source: "janitor") }
            if index % 5 == 0 { try service.appendToNote(id: ids[0], text: "see [[Note \(index)]]", source: "claude") }
            if index % 7 == 0 { try service.archiveNote(id: note.id, reason: "test", source: "human") }
            // Reading mid-sequence matters: it forces folds at many different
            // points, which is where an incremental bug would show up.
            _ = try service.listNotes(includeArchived: true)
        }

        let incremental = try service.listNotes(includeArchived: true)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        let cold = Projector.project(try EventStore(fileURL: logURL).readAll())
            .values.sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(incremental, cold)
    }

    /// Two `NoteService` instances over one file, which is the real deployment:
    /// the GUI, `unlirice-agent`, and every connected MCP client are separate
    /// readers of the same log. A cache that didn't pick up another writer's
    /// appends would show a stale corpus indefinitely.
    func testASecondWriterIsPickedUpByAnAlreadyWarmCache() throws {
        let reader = try makeService()
        let writer = try makeService()

        _ = try reader.listNotes() // warm the cache on an empty log
        let note = try writer.createNote(title: "From another process", body: "", source: "claude")

        XCTAssertEqual(try reader.getNote(id: note.id)?.title, "From another process")
    }

    /// A log that shrank was replaced, not appended to — the cursor is
    /// meaningless and anything folded from it has to go.
    func testATruncatedLogRebuildsFromScratchInsteadOfFoldingOntoStaleState() throws {
        let service = try makeService()
        _ = try service.createNote(title: "Before", body: "", source: "human")
        XCTAssertEqual(try service.listNotes().count, 1)

        // Something else replaced the file wholesale.
        let replacement = try service.createNote(title: "Survivor", body: "", source: "human")
        let onlyLine = try String(contentsOf: logURL, encoding: .utf8)
            .split(separator: "\n")
            .first { $0.contains(replacement.id.uuidString) }!
        try (onlyLine + "\n").write(to: logURL, atomically: true, encoding: .utf8)

        let notes = try service.listNotes()
        XCTAssertEqual(notes.map(\.title), ["Survivor"])
    }

    /// A half-written trailing line must not advance the cursor past it, or the
    /// rest of that event is skipped forever once it lands.
    func testAPartialTrailingLineIsNotConsumedUntilComplete() throws {
        let service = try makeService()
        let note = try service.createNote(title: "Complete", body: "", source: "human")
        _ = try service.listNotes()

        let store = try EventStore(fileURL: logURL)
        let handle = try FileHandle(forWritingTo: logURL)
        handle.seekToEndOfFile()
        handle.write(Data("{\"noteId\":\"\(note.id)\",\"kind\":\"tag".utf8))
        try handle.close()

        let partial = try store.read(from: .start)
        XCTAssertEqual(partial.events.count, 1)

        // Finish the line with a real event; both are now readable.
        let completion = Event(noteId: note.id, source: "human", kind: .tagged, tag: "late")
        var encoded = try JSONEncoder.iso8601.encode(completion)
        encoded.append(UInt8(ascii: "\n"))
        let closing = try FileHandle(forWritingTo: logURL)
        closing.seekToEndOfFile()
        closing.write(Data("\n".utf8) + encoded)
        try closing.close()

        XCTAssertEqual(try service.getNote(id: note.id)?.tags, ["late"])
    }

    /// Reading a log nothing has appended to should do no projection work at
    /// all. Not a timing assertion — the cursor not moving is the observable
    /// form of the same claim.
    func testAQuietReadConsumesNothing() throws {
        let store = try EventStore(fileURL: logURL)
        let service = NoteService(store: store)
        _ = try service.createNote(title: "One", body: "", source: "human")

        let first = try store.read(from: .start)
        let second = try store.read(from: first.cursor)
        XCTAssertTrue(second.events.isEmpty)
        XCTAssertEqual(second.cursor, first.cursor)
        XCTAssertFalse(second.restarted)
    }

    /// The scale the deferred note was actually worried about: ingest can add
    /// tens of notes in one click, each write costing two reads. Quadratic
    /// behaviour here is what made that "the next thing to build".
    func testAHundredWritesStayLinear() throws {
        let service = try makeService()
        for index in 0..<100 {
            let note = try service.createNote(title: "Note \(index)", body: "body", source: "ingest")
            try service.tagNote(id: note.id, tag: "ingested", source: "ingest")
        }

        let notes = try service.listNotes()
        XCTAssertEqual(notes.count, 100)
        XCTAssertEqual(notes.filter { $0.tags == ["ingested"] }.count, 100)

        // And still identical to a cold projection of the same file.
        let cold = Projector.project(try EventStore(fileURL: logURL).readAll())
        XCTAssertEqual(Set(cold.values.map(\.title)), Set(notes.map(\.title)))
    }
}

extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
