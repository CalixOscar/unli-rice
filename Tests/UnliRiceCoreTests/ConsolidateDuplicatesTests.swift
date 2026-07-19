import XCTest
@testable import UnliRiceCore

/// Covers `NoteService.consolidateDuplicates` — the human-triggered "keep this
/// one" action a person takes on a duplicate cluster in the review queue. Never
/// called by `JanitorRunner`; only ever composes `appendToNote`, `archiveNote`,
/// and `resolveReview`, same primitives any other caller has.
final class ConsolidateDuplicatesTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-consolidate-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testOthersAreArchivedNotDeleted() throws {
        let keep = try service.createNote(title: "Keeper", body: "main content", source: "human")
        let other = try service.createNote(title: "Duplicate", body: "extra content", source: "human")

        try service.consolidateDuplicates(
            keeping: keep.id, archiving: [other.id], resolving: [], source: "human"
        )

        let archived = try service.getNote(id: other.id)
        XCTAssertEqual(archived?.archived, true)
        // Still fully readable — archiving is soft, never a delete (decision #2).
        XCTAssertEqual(archived?.body, "extra content")
    }

    func testOtherNotesContentIsAppendedOntoTheKeeper() throws {
        let keep = try service.createNote(title: "Keeper", body: "main content", source: "human")
        let other = try service.createNote(title: "Duplicate", body: "important detail", source: "human")

        let result = try service.consolidateDuplicates(
            keeping: keep.id, archiving: [other.id], resolving: [], source: "human"
        )

        XCTAssertTrue(result.body.contains("main content"))
        XCTAssertTrue(result.body.contains("important detail"))
        XCTAssertTrue(result.body.contains("Duplicate"), "should credit which note the content came from")
    }

    /// An empty-bodied duplicate (e.g. a title-only note created by mistake)
    /// shouldn't leave a hollow "Merged from ... :" section with nothing after
    /// it on the keeper.
    func testEmptyOtherBodyIsNotAppended() throws {
        let keep = try service.createNote(title: "Keeper", body: "main content", source: "human")
        let empty = try service.createNote(title: "Empty duplicate", body: "", source: "human")

        let result = try service.consolidateDuplicates(
            keeping: keep.id, archiving: [empty.id], resolving: [], source: "human"
        )

        XCTAssertEqual(result.body, "main content")
    }

    func testConsolidatingThreeNotesArchivesAllOthersAndKeepsAllContent() throws {
        let keep = try service.createNote(title: "Keeper", body: "A", source: "human")
        let b = try service.createNote(title: "B", body: "B content", source: "human")
        let c = try service.createNote(title: "C", body: "C content", source: "human")

        let result = try service.consolidateDuplicates(
            keeping: keep.id, archiving: [b.id, c.id], resolving: [], source: "human"
        )

        XCTAssertTrue(result.body.contains("B content"))
        XCTAssertTrue(result.body.contains("C content"))
        XCTAssertEqual(try service.getNote(id: b.id)?.archived, true)
        XCTAssertEqual(try service.getNote(id: c.id)?.archived, true)
    }

    /// The keeper itself must never end up archived or merged into, even if a
    /// caller accidentally includes it in the "others" list.
    func testKeeperIsNeverArchivedEvenIfListedAmongOthers() throws {
        let keep = try service.createNote(title: "Keeper", body: "main", source: "human")

        let result = try service.consolidateDuplicates(
            keeping: keep.id, archiving: [keep.id], resolving: [], source: "human"
        )

        XCTAssertEqual(result.archived, false)
        XCTAssertEqual(result.body, "main", "must not merge a note's own content onto itself")
    }

    func testResolvesEveryFlagPassedIn() throws {
        let keep = try service.createNote(title: "Keeper", body: "A", source: "human")
        let other = try service.createNote(title: "Duplicate", body: "B", source: "human")
        try service.flagForReview(id: other.id, reason: "possible duplicate", source: "janitor")
        let flagID = try service.pendingReviews().first { $0.note.id == other.id }!.flag.id

        try service.consolidateDuplicates(
            keeping: keep.id, archiving: [other.id],
            resolving: [(noteID: other.id, flagID: flagID)], source: "human"
        )

        XCTAssertTrue(try service.pendingReviews().allSatisfy { $0.flag.id != flagID })
    }

    /// The whole point of the feature request: this is a human action, not
    /// something the janitor can trigger — `JanitorRunner` only ever calls
    /// `tagNote` and `flagForReview`. Consolidation existing as a capability on
    /// `NoteService` does not change that; this test guards the assumption.
    func testJanitorRunnerNeverCallsConsolidate() throws {
        let a = try service.createNote(title: "Session log", body: "x", source: "claude")
        let b = try service.createNote(title: "Session log copy", body: "y", source: "claude")
        let runner = JanitorRunner(service: service)

        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        // Neither note should have been archived or merged by the run — only
        // flagged, which a human then resolves via consolidateDuplicates.
        XCTAssertEqual(try service.getNote(id: a.id)?.archived, false)
        XCTAssertEqual(try service.getNote(id: b.id)?.archived, false)
    }
}
