import XCTest
@testable import UnliRiceCore

/// Phase 0: the log has only ever had one writer, appending in real time. A
/// second device changes that — an iPhone capture made offline at 09:00 and
/// imported at 17:00 lands *after* events that happened *before* it.
///
/// These tests pin the three things that breaks, all of which are silent.
final class ShardImportTests: XCTestCase {
    private var root: URL!
    private var store: EventStore!
    private var service: NoteService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-shard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = try EventStore(fileURL: root.appendingPathComponent("events.jsonl"))
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// The invariant `ProjectionCacheTests` already asserts — incremental equals
    /// cold — but with a backdated arrival, which is what an import is.
    ///
    /// `LinkIndex` claims a title for the first note to *arrive*;
    /// `Projector.resolveLinks` gives it to the note with the oldest
    /// `createdAt`. For a log written in real time those are the same sentence.
    /// For an imported capture they are not, and the two projections disagree
    /// about where a `[[Standup]]` link points.
    func testImportingABackdatedCreatedStillMatchesAColdProjection() throws {
        let onMac = try service.createNote(title: "Standup", body: "notes from today", source: "human")
        _ = try service.createNote(title: "Daily", body: "see [[Standup]]", source: "human")

        // Fold both before the import, so the incremental index has already
        // made its title decision. Without this the import arrives in the same
        // batch, gets sorted, and the bug hides.
        _ = try service.listNotes()

        // The import: a capture made *earlier* than everything above, arriving now.
        let fromPhone = Event(
            noteId: UUID(),
            timestamp: onMac.createdAt.addingTimeInterval(-3600),
            source: "human",
            kind: .created,
            title: "Standup",
            text: "dictated on the walk in"
        )
        try store.append(fromPhone)

        let incremental = try service.listNotes()
        let cold = Projector.project(try store.readAll())

        for note in incremental {
            let coldNote = try XCTUnwrap(cold[note.id], "note \(note.title) missing from cold projection")
            XCTAssertEqual(
                note.outboundLinks, coldNote.outboundLinks,
                "outbound links for \(note.title) diverged from a cold projection"
            )
            XCTAssertEqual(
                note.backlinks, coldNote.backlinks,
                "backlinks for \(note.title) diverged from a cold projection"
            )
        }

        // And state the specific consequence, so a future refactor that keeps
        // the two projections equal but both wrong still fails here.
        let daily = try XCTUnwrap(incremental.first { $0.title == "Daily" })
        XCTAssertEqual(
            daily.outboundLinks, [fromPhone.noteId],
            "[[Standup]] should resolve to the older note once it is imported"
        )
    }

    /// An older Mac must not destroy an event it cannot parse. `EventStore.read`
    /// drops undecodable lines via `try?`, so a decode-then-re-encode importer
    /// would silently erase any event kind a newer build introduced. `appendRaw`
    /// exists so foreign bytes are carried across verbatim.
    func testAppendRawPreservesUnknownEventKinds() throws {
        _ = try service.createNote(title: "Known", body: "already here", source: "human")

        let fromNewerBuild = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T10:00:00Z","source":"ios","kind":"drawingAttached",\
        "text":"a kind this build has never heard of"}
        """
        try store.appendRaw(Data(fromNewerBuild.utf8))

        let raw = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(
            raw.contains("drawingAttached"),
            "an unrecognized kind must survive on disk, not be dropped or rewritten"
        )

        // It must also not take the rest of the log down with it.
        XCTAssertEqual(try service.listNotes().map(\.title), ["Known"])
    }

    /// Why dedup is load-bearing rather than an optimisation: `Projector`
    /// assigns `.created` unconditionally, so replaying one wipes every tag and
    /// append that landed after it.
    func testDuplicateCreatedWipesTheNote() throws {
        let note = try service.createNote(title: "Standup", body: "original", source: "human")
        _ = try service.appendToNote(id: note.id, text: "a second thought", source: "human")
        _ = try service.tagNote(id: note.id, tag: "daily", source: "human")

        let before = try XCTUnwrap(try service.listNotes().first)
        XCTAssertTrue(before.body.contains("a second thought"))
        XCTAssertEqual(before.tags, ["daily"])

        // Re-import the same creation with a fresh event id — exactly what an
        // importer that dedups on the wrong key would do.
        try store.append(Event(
            noteId: note.id,
            timestamp: note.createdAt,
            source: "human",
            kind: .created,
            title: "Standup",
            text: "original"
        ))

        let after = try XCTUnwrap(Projector.project(try store.readAll())[note.id])
        XCTAssertFalse(
            after.body.contains("a second thought"),
            "a replayed .created overwrites the note — this is the damage dedup prevents"
        )
        XCTAssertTrue(after.tags.isEmpty)
    }
}
