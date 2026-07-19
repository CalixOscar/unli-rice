import XCTest
@testable import UnliRiceCore

/// Covers `ChatContext` — pure string formatting, no MLX involved. The only
/// thing worth getting wrong here is the safety framing, so that's most of
/// what's tested: every prompt sent to the model states its own boundary.
final class ChatContextTests: XCTestCase {
    private func note(
        title: String, body: String = "body", tags: Set<String> = [], updatedAt: Date = Date()
    ) -> Note {
        Note(id: UUID(), title: title, body: body, tags: tags, createdAt: updatedAt, updatedAt: updatedAt)
    }

    // MARK: - The boundary is always stated

    func testQuestionPromptAlwaysCarriesThePreamble() {
        let prompt = ChatContext.questionPrompt("anything", notes: [], pendingClusters: [])
        XCTAssertTrue(prompt.contains(ChatContext.preamble))
    }

    func testClusterRecommendationPromptAlwaysCarriesThePreamble() {
        let a = note(title: "Duplicate A")
        let b = note(title: "Duplicate B")
        let cluster = ReviewCluster(
            id: "dup-group/x",
            notes: [a, b],
            items: [ReviewItem(note: a, flag: ReviewFlag(id: UUID(), source: "janitor", reason: "x", timestamp: Date()))]
        )
        let prompt = ChatContext.clusterRecommendationPrompt(cluster)
        XCTAssertTrue(prompt.contains(ChatContext.preamble))
    }

    /// The one sentence that matters most: even a strong recommendation from
    /// the model must be legible as a suggestion, not an instruction it could
    /// act on itself.
    func testPreambleStatesTheModelCannotActOnItsOwnSuggestions() {
        let text = ChatContext.preamble.lowercased()
        XCTAssertTrue(text.contains("cannot") || text.contains("no ability") || text.contains("can only"))
    }

    // MARK: - Bounding

    func testCorpusBriefCapsNoteCountAtMaxNotes() {
        // Ascending updatedAt: "Note 0" is the oldest, "Note 49" the most
        // recent — corpusBrief sorts newest-first, so the oldest is exactly
        // what the cap should drop.
        let base = Date()
        let notes = (0 ..< 50).map { note(title: "Note \($0)", updatedAt: base.addingTimeInterval(Double($0))) }
        let brief = ChatContext.corpusBrief(notes: notes, pendingClusters: [], maxNotes: 5)

        XCTAssertFalse(brief.contains("Note 0:"))
        XCTAssertTrue(brief.contains("Note 49"))
        XCTAssertTrue(brief.contains("(5 of 50 total)"))
    }

    func testCorpusBriefExcludesArchivedNotes() {
        var archived = note(title: "Old and gone")
        archived.archived = true
        let live = note(title: "Still here")

        let brief = ChatContext.corpusBrief(notes: [archived, live], pendingClusters: [])

        XCTAssertFalse(brief.contains("Old and gone"))
        XCTAssertTrue(brief.contains("Still here"))
    }

    func testCorpusBriefTruncatesLongBodies() {
        let long = note(title: "Long note", body: String(repeating: "x", count: 5000))
        let brief = ChatContext.corpusBrief(notes: [long], pendingClusters: [], maxBodyChars: 100)

        XCTAssertFalse(brief.contains(String(repeating: "x", count: 5000)))
        XCTAssertTrue(brief.contains("…"))
    }

    func testClusterBriefIncludesEveryNoteInTheCluster() {
        let notes = [note(title: "First"), note(title: "Second"), note(title: "Third")]
        let cluster = ReviewCluster(id: "dup-group/y", notes: notes, items: [])
        let brief = ChatContext.clusterBrief(cluster)

        for note in notes {
            XCTAssertTrue(brief.contains(note.title))
        }
    }

    // MARK: - History folding

    func testQuestionPromptFoldsInPriorTurns() {
        let prompt = ChatContext.questionPrompt(
            "and then what?",
            notes: [],
            pendingClusters: [],
            priorTurns: [("what is this app?", "A local notes app.")]
        )
        XCTAssertTrue(prompt.contains("what is this app?"))
        XCTAssertTrue(prompt.contains("A local notes app."))
        XCTAssertTrue(prompt.contains("and then what?"))
    }

    func testQuestionPromptCapsPriorTurnsAtFour() {
        let turns = (0 ..< 10).map { ("q\($0)", "a\($0)") }
        let prompt = ChatContext.questionPrompt("latest", notes: [], pendingClusters: [], priorTurns: turns)

        XCTAssertFalse(prompt.contains("q0\n"))
        XCTAssertTrue(prompt.contains("q9"))
    }

    // MARK: - stripThinkingBlock

    /// The exact failure caught by actually running the app: Qwen3 emitting a
    /// `<think>` block the panel then showed verbatim as if it were the answer.
    func testStripThinkingBlockRemovesLeadingReasoning() {
        let raw = "<think>\nMaybe the user wants X, but actually Y...\n</think>\n\nThe short answer is Y."
        XCTAssertEqual(ChatContext.stripThinkingBlock(raw), "The short answer is Y.")
    }

    func testStripThinkingBlockLeavesPlainAnswerUnchanged() {
        let raw = "The short answer is Y."
        XCTAssertEqual(ChatContext.stripThinkingBlock(raw), raw)
    }

    /// If `enable_thinking: false` primed an empty block anyway, stripping it
    /// should still leave a real answer, not an empty string.
    func testStripThinkingBlockHandlesEmptyThinkBlock() {
        let raw = "<think>\n\n</think>\n\nStraight to the point."
        XCTAssertEqual(ChatContext.stripThinkingBlock(raw), "Straight to the point.")
    }

    /// Not the failure mode this guards against — a mid-answer `<think>` tag
    /// is left alone rather than guessed at.
    func testStripThinkingBlockIgnoresNonLeadingThinkTag() {
        let raw = "The answer is X. <think>huh, or is it?</think>"
        XCTAssertEqual(ChatContext.stripThinkingBlock(raw), raw)
    }
}
