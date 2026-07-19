import XCTest
@testable import UnliRiceCore

/// Covers `ReviewQueue.cluster` — the fix for the review queue asking "is A a
/// duplicate of B?" once per pair instead of once per pile. A chain of five
/// mutually-similar notes produces up to ten pairwise duplicate flags; a human
/// should answer that once.
final class ReviewClusterTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var runner: JanitorRunner!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-cluster-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)
        runner = JanitorRunner(service: service)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    private func pendingItems() throws -> [ReviewItem] {
        try service.pendingReviews().map { ReviewItem(note: $0.note, flag: $0.flag) }
    }

    /// Mirrors `AppStore.pendingClusters`: a lookup over *all* notes, not just
    /// the flagged subset, since a duplicate pair's older note may carry no
    /// flag of its own.
    private func clusters() throws -> [ReviewCluster] {
        let allNotes = try service.listNotes(includeArchived: true)
        let index = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        return ReviewQueue.cluster(try pendingItems()) { index[$0] }
    }

    /// The exact shape from the real corpus: five notes with the same title,
    /// differing only by a numeric suffix — a token-overlap duplicate chain
    /// that produces C(5,2) = 10 pairwise flags. Should collapse to one card.
    func testFiveMutualDuplicatesFormOneCluster() throws {
        let base = "Clearspace session log"
        for suffix in ["", "-2", "-3", "-4", "-5"] {
            _ = try service.createNote(title: base + suffix, body: "session notes", source: "claude")
        }
        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        let clusters = try clusters()
        let duplicateClusters = clusters.filter(\.isDuplicateGroup)

        XCTAssertEqual(duplicateClusters.count, 1, "one pile of near-identical titles should be one decision")
        XCTAssertEqual(duplicateClusters[0].notes.count, 5)
    }

    /// Two unrelated duplicate pairs must not merge into one cluster just
    /// because they were raised in the same run — clustering is by shared
    /// note, not by "everything currently pending."
    func testUnrelatedDuplicatePairsStaySeparate() throws {
        _ = try service.createNote(title: "Weekly retro notes", body: "x", source: "claude")
        _ = try service.createNote(title: "Weekly retro notes v2", body: "x", source: "claude")
        _ = try service.createNote(title: "Grocery list draft", body: "y", source: "claude")
        _ = try service.createNote(title: "Grocery list draft v2", body: "y", source: "claude")
        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        let clusters = try clusters()
        let duplicateClusters = clusters.filter(\.isDuplicateGroup)

        XCTAssertEqual(duplicateClusters.count, 2)
        XCTAssertTrue(duplicateClusters.allSatisfy { $0.notes.count == 2 })
    }

    /// Non-duplicate flags (orphans, mistyped links) are genuinely separate
    /// questions and must not be swept into a duplicate cluster.
    func testNonDuplicateFlagsStayStandalone() throws {
        let target = try service.createNote(title: "Roadmap 2026", body: "plan", source: "claude")
        _ = try service.appendToNote(id: target.id, text: "see [[Raodmap 2026]]", source: "claude")
        _ = try service.createNote(title: "Lonely thought", body: "nothing links here", source: "claude")

        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        let clusters = try clusters()
        XCTAssertTrue(clusters.allSatisfy { !$0.isDuplicateGroup })
        XCTAssertTrue(clusters.count >= 1)
    }

    /// Resolving a cluster must resolve every flag it bundled — a human who
    /// rejects a pile of five should not find three of them still pending.
    func testResolvingClusterResolvesEveryUnderlyingFlag() throws {
        for suffix in ["", "-2", "-3"] {
            _ = try service.createNote(title: "Duplicate pile" + suffix, body: "x", source: "claude")
        }
        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        let clusters = try clusters()
        guard let cluster = clusters.first(where: \.isDuplicateGroup) else {
            return XCTFail("expected a duplicate cluster")
        }
        XCTAssertFalse(cluster.items.isEmpty)

        for item in cluster.items {
            _ = try service.resolveReview(
                id: item.note.id, flagId: item.flag.id, source: "human", outcome: "rejected"
            )
        }

        let stillPending = try pendingItems()
        let resolvedFingerprints = Set(cluster.items.map(\.flag.id))
        XCTAssertTrue(stillPending.allSatisfy { !resolvedFingerprints.contains($0.flag.id) })
    }

    /// A rejected cluster must not come back on the next scan — the whole
    /// point of stamping every flag in the group, not just one representative.
    func testRejectedClusterIsNotReRaised() throws {
        for suffix in ["", "-2"] {
            _ = try service.createNote(title: "Stays rejected" + suffix, body: "x", source: "claude")
        }
        try runner.run(config: JanitorConfig(autonomy: .aggressive))

        for item in try pendingItems() {
            _ = try service.resolveReview(
                id: item.note.id, flagId: item.flag.id, source: "human", outcome: "rejected"
            )
        }

        try runner.run(config: JanitorConfig(autonomy: .aggressive))
        let clusters = try clusters()
        XCTAssertTrue(clusters.filter(\.isDuplicateGroup).isEmpty)
    }

    // MARK: - String helper

    func testWithoutJanitorMarkerStripsStampButKeepsSentence() {
        let reason = "Possible duplicate of \"X\" (100% title overlap). Your call. [janitor:dup/AAAA/BBBB]"
        XCTAssertEqual(
            reason.withoutJanitorMarker,
            "Possible duplicate of \"X\" (100% title overlap). Your call."
        )
    }

    func testWithoutJanitorMarkerLeavesUnstampedReasonUnchanged() {
        let reason = "Flagged by a human, no stamp here."
        XCTAssertEqual(reason.withoutJanitorMarker, reason)
    }
}
