import XCTest
@testable import UnliRiceCore

/// The load-bearing tests for the bring-your-own-LLM feature.
///
/// The authority ladder in §4 of docs/BYO_LLM.md is enforced by a type, not by
/// an instruction in the prompt. These tests are what that claim means: whatever
/// a model emits, the only event kinds it can ever cause are `flagged`,
/// `created`, `appended`, `tagged` and `untagged` — and the last four only under
/// the ownership rule.
final class ReasoningDispatcherTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var dispatcher: RestrictedReasoningDispatcher!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-reasoning-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
        dispatcher = RestrictedReasoningDispatcher(service: service, model: "gpt-5")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    private func dispatch(_ json: String) throws -> ReasoningDispatchReport {
        try dispatcher.apply(ReasoningActionParser.parse(json))
    }

    // MARK: - The permission boundary

    /// Every MCP tool that is not on the ladder, asked for by name, is refused.
    ///
    /// The MCP `ToolDispatcher` exposes 14 tools; a reasoning provider gets a
    /// subset of five. An over-eager model cannot express the other nine even if
    /// it tries — and "tries" is exactly what this simulates.
    func testRefusesEveryActionThatIsNotOnTheLadder() throws {
        let note = try service.createNote(title: "A note", body: "body", source: "human")
        let forbidden = [
            "archive_note", "unarchive_note", "resolve_review", "consolidate_duplicates",
            "delete_note", "trash_note", "rename_note", "retitle_note", "merge_notes",
            "list_notes", "get_note", "search_notes", "note_history", "pending_reviews",
            "transaction_log"
        ]

        for name in forbidden {
            let report = try dispatch("""
            {"actions": [{"action": "\(name)", "note_id": "\(note.id.uuidString)", "reason": "x", "tag": "x", "title": "x", "body": "x", "text": "x"}]}
            """)
            XCTAssertTrue(report.applied.isEmpty, "\(name) was applied")
            XCTAssertEqual(report.allRefusals.count, 1, "\(name) produced no refusal")
            XCTAssertEqual(report.allRefusals.first?.reason, .notOnTheLadder, "\(name)")
        }

        // Nothing above touched the log beyond the one note created by hand.
        let events = try service.transactionLog(limit: .max)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.kind, .created)
        XCTAssertEqual(events.first?.source, "human")
    }

    /// Whatever it decides, the dispatcher's hands only reach five event kinds.
    func testOnlyEverWritesTheFiveEventKindsOnTheLadder() throws {
        let user = try service.createNote(title: "User's own note", body: "mine", source: "human")
        let owned = try service.createNote(title: "Memory: capsule", body: "derived", source: "janitor:gpt-5")
        try service.tagNote(id: user.id, tag: "existing", source: "human")

        _ = try dispatch("""
        {"actions": [
          {"action": "flag_for_review", "note_id": "\(user.id.uuidString)", "reason": "looks like a duplicate of something"},
          {"action": "tag_note", "note_id": "\(user.id.uuidString)", "tag": "fresh"},
          {"action": "untag_note", "note_id": "\(user.id.uuidString)", "tag": "existing"},
          {"action": "create_note", "title": "Summary: this week", "body": "text"},
          {"action": "append_to_note", "note_id": "\(owned.id.uuidString)", "text": "more"},
          {"action": "archive_note", "note_id": "\(user.id.uuidString)", "reason": "tidy"}
        ]}
        """)

        let byModel = try service.transactionLog(limit: .max).filter { $0.source.hasPrefix("janitor:") && $0.source != "janitor:gpt-5-seed" }
        let kinds = Set(byModel.map(\.kind))
        XCTAssertTrue(kinds.isSubset(of: [.flagged, .created, .appended, .tagged, .untagged]), "\(kinds)")
        XCTAssertFalse(kinds.contains(.archived))
        XCTAssertFalse(kinds.contains(.unarchived))
        XCTAssertFalse(kinds.contains(.reviewResolved))
    }

    // MARK: - Locked-in decision #3: structural is always a proposal

    /// A merge request cannot be applied by any route. The only shape it can
    /// take is a flag that waits for a human — there is no case in
    /// `ReasoningAction` that consolidates, and no branch here that could.
    func testStructuralJudgementCanOnlyEverBecomeAPendingFlag() throws {
        let older = try service.createNote(title: "MCP server registration", body: "one", source: "human")
        let newer = try service.createNote(title: "MCP Server Registration", body: "two", source: "claude")

        let report = try dispatch("""
        {"actions": [
          {"action": "consolidate_duplicates", "note_id": "\(newer.id.uuidString)", "keep": "\(older.id.uuidString)"},
          {"action": "flag_for_review", "note_id": "\(newer.id.uuidString)", "reason": "Same idea as \\"MCP server registration\\"; the older one is the keeper."}
        ]}
        """)

        XCTAssertEqual(report.applied.count, 1)
        XCTAssertEqual(report.allRefusals.count, 1)
        XCTAssertFalse(try service.getNote(id: newer.id)!.archived)
        XCTAssertFalse(try service.getNote(id: older.id)!.archived)

        let pending = try service.pendingReviews()
        XCTAssertEqual(pending.count, 1)
        XCTAssertFalse(pending[0].flag.resolved, "a model must never resolve its own flag")
    }

    // MARK: - The Own tier's ownership rule

    func testRefusesToCreateANoteOutsideItsOwnTitlePrefixes() throws {
        let report = try dispatch("""
        {"actions": [{"action": "create_note", "title": "Paywall pricing decision", "body": "the model's own idea"}]}
        """)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertEqual(report.allRefusals.first?.reason, .notOwned)
        XCTAssertTrue(try service.listNotes().isEmpty)
    }

    func testRefusesToAppendToANoteItDoesNotOwn() throws {
        let user = try service.createNote(title: "Paywall pricing decision", body: "mine", source: "human")
        let report = try dispatch("""
        {"actions": [{"action": "append_to_note", "note_id": "\(user.id.uuidString)", "text": "and another thing"}]}
        """)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertEqual(report.allRefusals.first?.reason, .notOwned)
        XCTAssertEqual(try service.getNote(id: user.id)?.body, "mine")
    }

    func testWritesTheNotesItDoesOwn() throws {
        let owned = try service.createNote(title: "Memory: capsule", body: "start", source: "janitor:gpt-5")
        let report = try dispatch("""
        {"actions": [
          {"action": "create_note", "title": "Summary: August", "body": "what happened"},
          {"action": "append_to_note", "note_id": "\(owned.id.uuidString)", "text": "more"}
        ]}
        """)
        XCTAssertEqual(report.applied.count, 2)
        XCTAssertTrue(try service.getNote(id: owned.id)!.body.contains("more"))
        XCTAssertTrue(try service.listNotes().contains { $0.title == "Summary: August" })
    }

    // MARK: - Locked-in decision #4: attribution

    /// A user looking at a tag six months later must be able to see that a model
    /// added it and which one — and that is also what makes a bad model's output
    /// revocable in bulk.
    func testEveryWriteRecordsWhichModelMadeIt() throws {
        let note = try service.createNote(title: "A note", body: "body", source: "human")
        _ = try dispatch("""
        {"actions": [
          {"action": "tag_note", "note_id": "\(note.id.uuidString)", "tag": "mcp"},
          {"action": "flag_for_review", "note_id": "\(note.id.uuidString)", "reason": "worth a look"}
        ]}
        """)

        let written = try service.transactionLog(limit: .max).filter { $0.source != "human" }
        XCTAssertEqual(written.count, 2)
        for event in written {
            XCTAssertEqual(event.source, "janitor:gpt-5")
        }
    }

    /// `janitor` is reserved for the local rule-based janitor (AGENTS.md). A
    /// model's writes must be distinguishable from it, or the audit trail lies.
    func testModelSourceIsDistinctFromTheLocalJanitor() {
        XCTAssertNotEqual(RestrictedReasoningDispatcher.sourceIdentity(model: "gpt-5"), JanitorRunner.sourceIdentity)
        XCTAssertTrue(RestrictedReasoningDispatcher.sourceIdentity(model: "gpt-5").hasPrefix("janitor:"))
        XCTAssertEqual(RestrictedReasoningDispatcher.sourceIdentity(model: "  "), "janitor:unknown-model")
    }

    // MARK: - Not arguing with the user

    func testDoesNotReAddATagAHumanRemoved() throws {
        let note = try service.createNote(title: "A note", body: "body", source: "human")
        try service.tagNote(id: note.id, tag: "mcp", source: "claude")
        try service.untagNote(id: note.id, tag: "mcp", source: "human")

        let report = try dispatch("""
        {"actions": [{"action": "tag_note", "note_id": "\(note.id.uuidString)", "tag": "mcp"}]}
        """)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertEqual(report.skipped.first?.reason, "tag was previously removed by hand")
        XCTAssertFalse(try service.getNote(id: note.id)!.tags.contains("mcp"))
    }

    func testDoesNotRaiseTheSameFlagTwice() throws {
        let note = try service.createNote(title: "A note", body: "body", source: "human")
        let json = """
        {"actions": [{"action": "flag_for_review", "note_id": "\(note.id.uuidString)", "reason": "this duplicates the other one"}]}
        """
        XCTAssertEqual(try dispatch(json).applied.count, 1)
        let second = try dispatch(json)
        XCTAssertTrue(second.applied.isEmpty)
        XCTAssertEqual(second.skipped.first?.reason, "already raised in a previous run")
        XCTAssertEqual(try service.pendingReviews().count, 1)
    }

    // MARK: - Reading the reply

    /// A reply the parser can't read applies to nothing. Guessing at intent
    /// would be this app inventing the judgement it exists to avoid making.
    func testAnUnreadableReplyAppliesNothing() throws {
        for reply in ["Sure! Here's what I found:", "```json\n{\"actions\": []}\n```", "{\"result\": []}"] {
            let report = try dispatch(reply)
            XCTAssertNotNil(report.unreadable, "read something it shouldn't have: \(reply)")
            XCTAssertTrue(report.applied.isEmpty)
        }
        XCTAssertTrue(try service.transactionLog(limit: .max).isEmpty)
    }

    func testAnEmptyActionListIsAValidAnswer() throws {
        let report = try dispatch("{\"actions\": []}")
        XCTAssertNil(report.unreadable)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertTrue(report.allRefusals.isEmpty)
    }

    func testRefusesActionsAimedAtNotesThatDoNotExist() throws {
        let report = try dispatch("""
        {"actions": [{"action": "tag_note", "note_id": "\(UUID().uuidString)", "tag": "x"}]}
        """)
        XCTAssertEqual(report.allRefusals.first?.reason, .unknownNote)
    }

    func testRefusesMalformedActions() throws {
        let report = try dispatch("""
        {"actions": [
          {"action": "tag_note", "note_id": "not-a-uuid", "tag": "x"},
          {"action": "flag_for_review", "note_id": "\(UUID().uuidString)"},
          {"tag": "orphan"}
        ]}
        """)
        XCTAssertTrue(report.applied.isEmpty)
        XCTAssertEqual(report.allRefusals.count, 3)
        for refusal in report.allRefusals {
            guard case .malformed = refusal.reason else {
                return XCTFail("expected malformed, got \(refusal.reason)")
            }
        }
    }
}

final class ReasoningAuthorityTests: XCTestCase {
    func testOwnershipIsAPrefixAndNothingElse() {
        XCTAssertTrue(ReasoningAuthority.owns(title: "Memory: capsule"))
        XCTAssertTrue(ReasoningAuthority.owns(title: "Summary: the week"))
        XCTAssertTrue(ReasoningAuthority.owns(title: "  memory: capsule"), "leading space and case must not defeat it")
        XCTAssertFalse(ReasoningAuthority.owns(title: "Paywall pricing"))
        XCTAssertFalse(ReasoningAuthority.owns(title: "A note about Memory: capsule"))
        XCTAssertFalse(ReasoningAuthority.owns(title: ""))
    }

    /// The prompt describes the ladder, and the dispatcher enforces it. They
    /// must not be able to drift apart — the description is generated from the
    /// same constant the enforcement reads.
    func testLadderDescriptionNamesTheRealOwnedPrefixes() {
        for prefix in ReasoningAuthority.ownedTitlePrefixes {
            XCTAssertTrue(ReasoningAuthority.ladderDescription.contains(prefix), prefix)
        }
    }

    func testEveryActionOnTheLadderKnowsItsTier() {
        let id = UUID()
        XCTAssertEqual(ReasoningAction.flagForReview(noteID: id, reason: "r").tier, .propose)
        XCTAssertEqual(ReasoningAction.createOwnedNote(title: "Memory: x", body: "b").tier, .own)
        XCTAssertEqual(ReasoningAction.appendToOwnedNote(noteID: id, text: "t").tier, .own)
        XCTAssertEqual(ReasoningAction.tagNote(noteID: id, tag: "t").tier, .tag)
        XCTAssertEqual(ReasoningAction.untagNote(noteID: id, tag: "t").tier, .tag)
    }
}
