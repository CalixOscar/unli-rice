import XCTest
@testable import UnliRiceCore

/// A provider that answers from a script and records what it was asked. Never
/// touches the network — the point of the seam is that this is possible.
final class StubReasoningProvider: ReasoningProvider, @unchecked Sendable {
    let host: String? = "api.example.test"
    let modelName: String
    private let reply: String
    private let lock = NSLock()
    private var _requests: [JudgementRequest] = []

    init(model: String = "gpt-5", reply: String = "{\"actions\": []}") {
        self.modelName = model
        self.reply = reply
    }

    var requests: [JudgementRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    func judge(_ request: JudgementRequest) async throws -> JudgementResponse {
        lock.lock()
        _requests.append(request)
        lock.unlock()
        return JudgementResponse(model: modelName, text: reply, promptTokens: 900, completionTokens: 40)
    }
}

final class ReasoningCursorTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var cursorURL: URL!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-reasoning-cursor-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        service = NoteService(store: try EventStore(fileURL: tempURL))
        cursorURL = ReasoningCursor.url(besideEventLog: tempURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    /// Seeds a corpus the rules put on the duplicate shortlist.
    @discardableResult
    private func seedShortlist() throws -> (older: Note, newer: Note) {
        let older = try service.createNote(title: "MCP server registration", body: "one", source: "human")
        let newer = try service.createNote(title: "MCP Server Registration", body: "two", source: "claude")
        return (older, newer)
    }

    private func runner(_ provider: ReasoningProvider) -> ReasoningRunner {
        ReasoningRunner(
            service: service, provider: provider,
            log: OutboundCallLog(besideEventLog: tempURL), cursorURL: cursorURL
        )
    }

    /// The cost control that matters after "never send the corpus": a note that
    /// hasn't changed since a model last read it produces the same judgement, so
    /// re-sending it buys nothing and costs the user money.
    func testASecondRunDoesNotReJudgeUnchangedNotes() async throws {
        try seedShortlist()
        let provider = StubReasoningProvider()
        let runner = runner(provider)

        let first = try runner.plan(scope: .janitorShortlist, task: "judge", config: JanitorConfig(autonomy: .balanced))
        XCTAssertEqual(first.noteCount, 2)
        XCTAssertEqual(first.skippedUnchanged, 0)
        _ = try await runner.execute(first)

        let second = try runner.plan(scope: .janitorShortlist, task: "judge", config: JanitorConfig(autonomy: .balanced))
        XCTAssertFalse(second.canSend)
        XCTAssertEqual(second.skippedUnchanged, 2)
        XCTAssertEqual(second.blocked, .nothingChanged(consideredNotes: 2))

        _ = try await runner.execute(second)
        XCTAssertEqual(provider.requests.count, 1, "the second run paid for the same notes again")
    }

    /// A note that *has* changed comes back. Only the changed one.
    func testAChangedNoteIsJudgedAgainAndAnUnchangedOneIsNot() async throws {
        let seeded = try seedShortlist()
        let provider = StubReasoningProvider()
        let runner = runner(provider)
        _ = try await runner.execute(try runner.plan(scope: .janitorShortlist, task: "judge"))

        try service.appendToNote(id: seeded.newer.id, text: "an edit", source: "human")

        let plan = try runner.plan(scope: .janitorShortlist, task: "judge")
        XCTAssertTrue(plan.canSend)
        XCTAssertEqual(plan.notes.map(\.id), [seeded.newer.id])
        XCTAssertEqual(plan.skippedUnchanged, 1)
    }

    /// A failed call must not advance the cursor, or a network blip silently
    /// means those notes are never looked at again.
    func testAFailedCallDoesNotAdvanceTheCursor() async throws {
        try seedShortlist()
        let failing = FailingReasoningProvider()
        let runner = runner(failing)

        let report = try await runner.execute(try runner.plan(scope: .janitorShortlist, task: "judge"))
        XCTAssertNotNil(report.failure)
        XCTAssertEqual(report.call.outcome, .failed)

        let again = try runner.plan(scope: .janitorShortlist, task: "judge")
        XCTAssertTrue(again.canSend)
        XCTAssertEqual(again.skippedUnchanged, 0)
    }

    func testAnUnreadableReplyDoesNotAdvanceTheCursorEither() async throws {
        try seedShortlist()
        let runner = runner(StubReasoningProvider(reply: "Sure! Here is what I found."))
        let report = try await runner.execute(try runner.plan(scope: .janitorShortlist, task: "judge"))
        XCTAssertNotNil(report.dispatch?.unreadable)

        XCTAssertTrue(try runner.plan(scope: .janitorShortlist, task: "judge").canSend)
    }

    func testCursorPersistsAcrossRunners() throws {
        var cursor = ReasoningCursor()
        let note = Note(id: UUID(), title: "t", body: "b", createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(cursor.needsJudgement(note))
        cursor.record([note])
        try cursor.save(to: cursorURL)

        let reloaded = ReasoningCursor.load(from: cursorURL)
        XCTAssertFalse(reloaded.needsJudgement(note))
        XCTAssertNotNil(reloaded.lastRunAt)

        var edited = note
        edited.body = "b, and one more thing"
        XCTAssertTrue(reloaded.needsJudgement(edited))

        var tagged = note
        tagged.tags = ["mcp"]
        XCTAssertTrue(reloaded.needsJudgement(tagged), "a note tagged since the run is a different question")
    }

    /// Event timestamps round-trip through the log as whole seconds. A cursor
    /// keyed on `updatedAt` would call an edit made in the same second as the
    /// run "unchanged" and never look at it again; a content fingerprint can't.
    func testAnEditInTheSameSecondAsTheRunIsStillNoticed() {
        let now = Date()
        var cursor = ReasoningCursor()
        let note = Note(id: UUID(), title: "t", body: "b", createdAt: now, updatedAt: now)
        cursor.record([note])

        var edited = note
        edited.body = "b + more"
        edited.updatedAt = now
        XCTAssertTrue(cursor.needsJudgement(edited))
    }
}

private struct FailingReasoningProvider: ReasoningProvider {
    var host: String? { "api.example.test" }
    var modelName: String { "gpt-5" }
    func judge(_ request: JudgementRequest) async throws -> JudgementResponse {
        throw OpenAICompatibleReasoning.Failure.httpError(status: 503)
    }
}

final class ReasoningCapsTests: XCTestCase {
    private func note(_ title: String, body: String = "body") -> Note {
        Note(id: UUID(), title: title, body: body, createdAt: Date(), updatedAt: Date())
    }

    private func plan(_ notes: [Note], caps: ReasoningCaps) -> ReasoningPlan {
        ReasoningRun.plan(
            task: "judge these", host: "api.example.test", model: "gpt-5",
            candidates: notes, cursor: ReasoningCursor(), caps: caps
        )
    }

    /// Over the note cap, the surplus is deferred to the next run and counted —
    /// the same "deferred, not dropped" semantics `JanitorConfig`'s budgets
    /// already have. What must never happen is exceeding the cap.
    func testTheNoteCapIsNeverExceededAndTheRemainderIsReported() {
        let notes = (1...40).map { note("Note \($0)") }
        let plan = plan(notes, caps: ReasoningCaps(maxNotesPerRun: 10, maxInputTokensPerRun: 100_000))
        XCTAssertEqual(plan.noteCount, 10)
        XCTAssertEqual(plan.deferredByCaps, 30)
        XCTAssertTrue(plan.canSend)
    }

    /// Whole notes are dropped to fit, never truncated. A body cut in half is a
    /// different note and the model has no way to know it read one.
    func testTheTokenCapDropsWholeNotesRatherThanTruncatingBodies() {
        let big = String(repeating: "word ", count: 400)
        let notes = (1...10).map { note("Note \($0)", body: big) }
        let caps = ReasoningCaps(maxNotesPerRun: 10, maxInputTokensPerRun: 2_000)
        let plan = plan(notes, caps: caps)

        XCTAssertTrue(plan.canSend)
        XCTAssertLessThan(plan.noteCount, 10)
        XCTAssertGreaterThan(plan.deferredByCaps, 0)
        XCTAssertLessThanOrEqual(plan.estimatedInputTokens, caps.maxInputTokensPerRun)
        for note in plan.notes {
            XCTAssertTrue(plan.request!.user.contains(note.body), "a body was truncated to fit")
        }
    }

    /// One note bigger than the whole cap has no honest answer but "no".
    func testASingleOversizedNoteBlocksTheRunRatherThanBeingCutInHalf() {
        let plan = plan(
            [note("Huge", body: String(repeating: "word ", count: 5_000))],
            caps: ReasoningCaps(maxNotesPerRun: 5, maxInputTokensPerRun: 500)
        )
        XCTAssertFalse(plan.canSend)
        XCTAssertNil(plan.request)
        guard case .singleNoteExceedsTokenCap = plan.blocked else {
            return XCTFail("expected the run to be blocked, got \(String(describing: plan.blocked))")
        }
    }

    /// A dry run has to be specific enough to disagree with: the host by name,
    /// the count, and the estimate labelled as one.
    func testTheDisclosureNamesTheHostAndTheCount() {
        let plan = plan([note("One"), note("Two")], caps: .default)
        XCTAssertTrue(plan.disclosure.contains("api.example.test"))
        XCTAssertTrue(plan.disclosure.contains("2 notes"))
        XCTAssertTrue(plan.disclosure.lowercased().contains("estimate"))
    }

    /// The request carries titles and bodies — exactly what consent says — and
    /// not the vault's operational metadata.
    func testTheRequestCarriesTitlesAndBodiesAndTheLadder() {
        let subject = note("Paywall pricing", body: "we settled on 14.99")
        let plan = plan([subject], caps: .default)
        let request = try! XCTUnwrap(plan.request)
        XCTAssertTrue(request.user.contains("Paywall pricing"))
        XCTAssertTrue(request.user.contains("we settled on 14.99"))
        XCTAssertTrue(request.system.contains("flag_for_review"))
        XCTAssertFalse(request.system.contains("archive_note"))
    }
}
