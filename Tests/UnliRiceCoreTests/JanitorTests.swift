import XCTest
@testable import UnliRiceCore

final class JanitorTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var runner: JanitorRunner!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-janitor-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
        runner = JanitorRunner(service: service)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    private func duplicates(in proposals: [JanitorProposal]) -> [JanitorProposal] {
        proposals.filter { if case .possibleDuplicate = $0.kind { return true } else { return false } }
    }

    // MARK: - The permission boundary

    /// The load-bearing test for the whole design: whatever the janitor decides,
    /// the only event kinds it can ever produce are `tagged` and `flagged`.
    func testJanitorOnlyEverWritesTagsAndFlags() throws {
        let original = try service.createNote(title: "MCP server registration", body: "the mcp setup", source: "claude")
        try service.tagNote(id: original.id, tag: "mcp", source: "claude")
        let other = try service.createNote(title: "Export pipeline", body: "mcp adjacent", source: "claude")
        try service.tagNote(id: other.id, tag: "mcp", source: "claude")
        try service.createNote(title: "MCP Server Registration", body: "duplicate-ish", source: "gemini")
        try service.createNote(title: "Lonely thought", body: "links to [[MCP server registratio]]", source: "human")

        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        let janitorEvents = try service.transactionLog(limit: Int.max)
            .filter { $0.source == JanitorRunner.sourceIdentity }
        XCTAssertFalse(janitorEvents.isEmpty, "janitor should have done something to make this test meaningful")

        let kinds = Set(janitorEvents.map(\.kind))
        XCTAssertTrue(
            kinds.isSubset(of: [.tagged, .flagged]),
            "janitor produced forbidden event kinds: \(kinds.subtracting([.tagged, .flagged]))"
        )
    }

    func testStructuralProposalsAreQueuedNeverApplied() throws {
        let first = try service.createNote(title: "Auth flow design", body: "a", source: "claude")
        let second = try service.createNote(title: "Auth flow design", body: "b", source: "gemini")

        let report = try runner.run(config: JanitorConfig(autonomy: .balanced))

        XCTAssertEqual(report.queued.count, 1)
        XCTAssertEqual(report.applied.count, 0)

        // Both notes still exist, unarchived, with their bodies untouched.
        XCTAssertEqual(try service.getNote(id: first.id)?.body, "a")
        XCTAssertEqual(try service.getNote(id: second.id)?.body, "b")
        XCTAssertFalse(try service.getNote(id: first.id)!.archived)
        XCTAssertFalse(try service.getNote(id: second.id)!.archived)

        let pending = try service.pendingReviews()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].flag.source, "janitor")
    }

    // MARK: - Autonomy gating

    func testEcoRunsCosmeticRulesButQueuesNoStructuralProposals() throws {
        let a = try service.createNote(title: "Billing retries", body: "x", source: "claude")
        try service.tagNote(id: a.id, tag: "billing", source: "claude")
        let b = try service.createNote(title: "Billing webhooks", body: "y", source: "claude")
        try service.tagNote(id: b.id, tag: "billing", source: "claude")
        // Untagged, but its own text says "billing" — a cosmetic candidate.
        let c = try service.createNote(title: "Billing edge cases", body: "z", source: "claude")
        // A blatant duplicate that Eco must stay quiet about.
        try service.createNote(title: "Billing webhooks", body: "dupe", source: "gemini")

        let report = try runner.run(config: JanitorConfig(autonomy: .eco))

        XCTAssertTrue(report.queued.isEmpty, "Eco promised no structural proposals")
        XCTAssertTrue(try service.pendingReviews().isEmpty)
        XCTAssertTrue(try service.getNote(id: c.id)!.tags.contains("billing"))
    }

    func testAggressiveProposesMoreEagerlyThanBalanced() throws {
        // 60% title overlap: above Aggressive's 0.55 bar, below Balanced's 0.75.
        try service.createNote(title: "Vector search rollout plan", body: "a", source: "claude")
        try service.createNote(title: "Vector search plan notes", body: "b", source: "gemini")

        let notes = try service.listNotes()
        let balanced = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .balanced))
        let aggressive = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .aggressive))

        XCTAssertEqual(duplicates(in: balanced).count, 0)
        XCTAssertEqual(duplicates(in: aggressive).count, 1)
    }

    func testOnlyAggressiveReportsOrphans() throws {
        try service.createNote(title: "A thought with no home", body: "no tags, no links", source: "human")

        let notes = try service.listNotes()
        let balanced = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .balanced))
        let aggressive = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .aggressive))

        XCTAssertFalse(balanced.contains { $0.kind == .orphaned })
        XCTAssertTrue(aggressive.contains { $0.kind == .orphaned })
    }

    // MARK: - Idempotence and deference to the human

    func testRepeatedRunsDoNotReRaiseTheSameProposal() throws {
        try service.createNote(title: "Sync conflict handling", body: "a", source: "claude")
        try service.createNote(title: "Sync conflict handling", body: "b", source: "gemini")

        let first = try runner.run(config: JanitorConfig(autonomy: .balanced))
        let second = try runner.run(config: JanitorConfig(autonomy: .balanced))

        XCTAssertEqual(first.queued.count, 1)
        XCTAssertEqual(second.queued.count, 0)
        XCTAssertEqual(try service.pendingReviews().count, 1)
    }

    func testAResolvedProposalIsNotRaisedAgain() throws {
        try service.createNote(title: "Storage footprint targets", body: "a", source: "claude")
        try service.createNote(title: "Storage footprint targets", body: "b", source: "gemini")
        try runner.run(config: JanitorConfig(autonomy: .balanced))

        let pending = try service.pendingReviews()[0]
        try service.resolveReview(id: pending.note.id, flagId: pending.flag.id, source: "human", outcome: "not a duplicate")

        let report = try runner.run(config: JanitorConfig(autonomy: .balanced))
        XCTAssertEqual(report.queued.count, 0, "a human said no; the janitor must not ask again")
        XCTAssertTrue(try service.pendingReviews().isEmpty)
    }

    func testJanitorDoesNotReAddATagAHumanRemoved() throws {
        let a = try service.createNote(title: "Projector internals", body: "x", source: "claude")
        try service.tagNote(id: a.id, tag: "projector", source: "claude")
        let b = try service.createNote(title: "Projector link pass", body: "y", source: "claude")
        try service.tagNote(id: b.id, tag: "projector", source: "claude")
        let c = try service.createNote(title: "Notes on the projector second pass", body: "z", source: "claude")

        try runner.run(config: JanitorConfig(autonomy: .balanced))
        XCTAssertTrue(try service.getNote(id: c.id)!.tags.contains("projector"))

        try service.untagNote(id: c.id, tag: "projector", source: "human")

        let report = try runner.run(config: JanitorConfig(autonomy: .balanced))
        XCTAssertFalse(try service.getNote(id: c.id)!.tags.contains("projector"))
        XCTAssertEqual(report.applied.count, 0)
    }

    // MARK: - Blast radius

    /// Regression for what the real event log actually did: "memory" was on
    /// enough notes that the janitor wanted to put it on nearly all of them.
    func testDoesNotProposeATagThatAlreadyCoversMostOfTheCorpus() throws {
        for index in 0..<10 {
            let note = try service.createNote(title: "Note \(index) about memory", body: "memory", source: "claude")
            // 8 of 10 notes carry it — well past the saturation cap.
            if index < 8 { try service.tagNote(id: note.id, tag: "memory", source: "claude") }
        }

        let proposals = Janitor.scan(notes: try service.listNotes(), config: JanitorConfig(autonomy: .balanced))
        XCTAssertFalse(
            proposals.contains { $0.kind == .addTag("memory") },
            "a tag already on most of the corpus is wallpaper, not a filter"
        )
    }

    func testOneRunCannotFloodTheReviewQueue() throws {
        for index in 0..<30 {
            try service.createNote(title: "Duplicate heading \(index % 2)", body: "b\(index)", source: "claude")
        }

        let config = JanitorConfig(autonomy: .balanced)
        let report = try runner.run(config: config)
        XCTAssertLessThanOrEqual(report.queued.count, config.structuralBudget)
        XCTAssertLessThanOrEqual(try service.pendingReviews().count, config.structuralBudget)
    }

    func testBudgetDefersRatherThanDropsWork() throws {
        for index in 0..<30 {
            try service.createNote(title: "Same heading", body: "b\(index)", source: "claude")
        }

        let first = try runner.run(config: JanitorConfig(autonomy: .balanced))
        let second = try runner.run(config: JanitorConfig(autonomy: .balanced))

        XCTAssertEqual(first.queued.count, JanitorConfig(autonomy: .balanced).structuralBudget)
        XCTAssertGreaterThan(second.queued.count, 0, "leftover work should come back next run, not vanish")
        XCTAssertTrue(
            Set(first.queued.map(\.fingerprint)).isDisjoint(with: Set(second.queued.map(\.fingerprint))),
            "the second run must raise new proposals, not repeat the first run's"
        )
    }

    func testHighestConfidenceProposalsWinTheBudget() throws {
        try service.createNote(title: "Identical title here", body: "a", source: "claude")
        try service.createNote(title: "Identical title here", body: "b", source: "gemini")
        // Genuinely unrelated titles — no shared tokens, so these are orphans
        // and nothing else.
        for word in ["kestrel", "obsidian", "harbour", "vellum", "tundra", "lantern", "quarry", "meridian", "thicket", "basalt"] {
            try service.createNote(title: "\(word) memo", body: "x", source: "claude")
        }

        let report = try runner.run(config: JanitorConfig(autonomy: .aggressive))
        // The exact-title duplicate is the most confident conclusion available,
        // so it must survive the budget even against a crowd of orphans.
        XCTAssertEqual(duplicates(in: report.queued).count, 1)
    }

    // MARK: - Rules

    func testNeverInventsATagThatIsNotAlreadyEstablished() throws {
        let only = try service.createNote(title: "Kubernetes notes", body: "kubernetes stuff", source: "claude")
        try service.tagNote(id: only.id, tag: "kubernetes", source: "claude")
        let other = try service.createNote(title: "More kubernetes", body: "kubernetes again", source: "claude")

        // Used by exactly one note, so below Balanced's threshold of 2.
        let report = try runner.run(config: JanitorConfig(autonomy: .balanced))
        XCTAssertEqual(report.applied.count, 0)
        XCTAssertTrue(try service.getNote(id: other.id)!.tags.isEmpty)
    }

    func testFlagsMistypedLinkButIgnoresDeliberateForwardReference() throws {
        try service.createNote(title: "Event log format", body: "the real one", source: "claude")
        let typo = try service.createNote(title: "Typo note", body: "see [[Event log formt]]", source: "claude")
        let forward = try service.createNote(title: "Forward note", body: "see [[Something Not Written Yet]]", source: "claude")

        let notes = try service.listNotes()
        let proposals = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .balanced))
            .filter { if case .likelyMistypedLink = $0.kind { return true } else { return false } }

        XCTAssertEqual(proposals.count, 1)
        XCTAssertEqual(proposals[0].noteID, typo.id)
        XCTAssertFalse(proposals.contains { $0.noteID == forward.id })
    }

    func testArchivedNotesAreOutOfScope() throws {
        let a = try service.createNote(title: "Retired idea", body: "x", source: "claude")
        try service.createNote(title: "Retired idea", body: "y", source: "gemini")
        try service.archiveNote(id: a.id, reason: "obsolete", source: "human")

        // The surviving note may still be flagged as an orphan at this level —
        // what must not happen is a duplicate proposal against the archived one.
        let report = try runner.run(config: JanitorConfig(autonomy: .aggressive))
        XCTAssertTrue(duplicates(in: report.queued).isEmpty, "archiving means stop bringing this up")
        XCTAssertFalse(try service.getNote(id: a.id)!.flags.contains { $0.source == "janitor" })
    }

    func testPreviewWritesNothing() throws {
        try service.createNote(title: "Same title", body: "a", source: "claude")
        try service.createNote(title: "Same title", body: "b", source: "gemini")

        let before = try service.transactionLog(limit: Int.max).count
        let proposals = try runner.preview(config: JanitorConfig(autonomy: .aggressive))
        let after = try service.transactionLog(limit: Int.max).count

        XCTAssertFalse(proposals.isEmpty)
        XCTAssertEqual(before, after)
    }

    func testDuplicatePairIsProposedOnceNotTwice() throws {
        try service.createNote(title: "Identical heading", body: "a", source: "claude")
        try service.createNote(title: "Identical heading", body: "b", source: "gemini")

        let report = try runner.run(config: JanitorConfig(autonomy: .aggressive))
        XCTAssertEqual(duplicates(in: report.queued).count, 1)
    }
}
