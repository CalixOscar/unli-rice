import XCTest
@testable import UnliRiceCore

/// Covers `DraftAdvisor.suggestions` — draft-time versions of the janitor's
/// own rules, computed before a note is ever written rather than after.
final class DraftAdvisorTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-draft-advisor-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testEmptyTitleProducesNoSuggestions() throws {
        let result = DraftAdvisor.suggestions(
            forTitle: "   ", body: "anything", existing: [], config: JanitorConfig(autonomy: .balanced)
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFlagsAPossibleDuplicateByTitle() throws {
        let existing = try service.createNote(title: "Weekly retro notes", body: "x", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Weekly retro notes",
            body: "y",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertEqual(result.possibleDuplicate?.id, existing.id)
    }

    func testUnrelatedTitleIsNotFlaggedAsDuplicate() throws {
        _ = try service.createNote(title: "Grocery list", body: "x", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Quarterly planning notes",
            body: "y",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertNil(result.possibleDuplicate)
    }

    func testArchivedNotesAreNeverSuggestedAsDuplicatesOrRelated() throws {
        let note = try service.createNote(title: "Weekly retro notes", body: "x", source: "human")
        try service.archiveNote(id: note.id, reason: "done with this", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Weekly retro notes",
            body: "y",
            existing: try service.listNotes(includeArchived: true),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertNil(result.possibleDuplicate)
        XCTAssertTrue(result.relatedNotes.isEmpty)
    }

    /// The relatedness bar is deliberately lower than the duplicate bar, and
    /// the two lists never overlap — a note can't be both "the same thing" and
    /// "merely related" at once.
    func testRelatedNotesExcludeTheDuplicateItself() throws {
        let existing = try service.createNote(title: "Weekly retro notes", body: "x", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Weekly retro notes",
            body: "y",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertFalse(result.relatedNotes.contains { $0.id == existing.id })
    }

    func testRelatedNotesAreCappedAtThree() throws {
        for i in 0 ..< 6 {
            _ = try service.createNote(title: "Project roadmap discussion \(i)", body: "x", source: "human")
        }

        let result = DraftAdvisor.suggestions(
            forTitle: "Project roadmap discussion",
            body: "y",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertLessThanOrEqual(result.relatedNotes.count, 3)
    }

    /// Same rule as `Janitor.scan`'s cosmetic tag pass: a tag only gets
    /// suggested once it's already established on other notes AND appears
    /// verbatim in the draft's own text. Never invented from nothing.
    func testSuggestsOnlyEstablishedTagsThatAppearInTheDraftText() throws {
        let a = try service.createNote(title: "Note A", body: "about budgets", source: "human")
        try service.tagNote(id: a.id, tag: "finance", source: "human")
        let b = try service.createNote(title: "Note B", body: "more budgets", source: "human")
        try service.tagNote(id: b.id, tag: "finance", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Q3 budgets",
            body: "reviewing the finance numbers",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertEqual(result.suggestedTags, ["finance"])
    }

    func testDoesNotSuggestATagUsedOnlyOnce() throws {
        let a = try service.createNote(title: "Note A", body: "x", source: "human")
        try service.tagNote(id: a.id, tag: "onceonly", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Another note",
            body: "mentions onceonly here",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertTrue(result.suggestedTags.isEmpty)
    }

    func testDoesNotSuggestAnEstablishedTagThatDoesNotAppearInDraftText() throws {
        let a = try service.createNote(title: "Note A", body: "x", source: "human")
        try service.tagNote(id: a.id, tag: "finance", source: "human")
        let b = try service.createNote(title: "Note B", body: "y", source: "human")
        try service.tagNote(id: b.id, tag: "finance", source: "human")

        let result = DraftAdvisor.suggestions(
            forTitle: "Completely unrelated topic",
            body: "nothing about money here",
            existing: try service.listNotes(),
            config: JanitorConfig(autonomy: .balanced)
        )

        XCTAssertTrue(result.suggestedTags.isEmpty)
    }
}
