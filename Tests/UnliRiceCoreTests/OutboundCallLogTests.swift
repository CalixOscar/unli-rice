import XCTest
@testable import UnliRiceCore

final class OutboundCallLogTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var log: OutboundCallLog!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-outbound-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        service = NoteService(store: try EventStore(fileURL: tempURL))
        log = OutboundCallLog(besideEventLog: tempURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    func testRecordsAndReadsBackNewestFirst() throws {
        let older = OutboundCall(host: "a.test", model: "m", at: Date(timeIntervalSince1970: 1), noteCount: 1, estimatedTokens: 10, outcome: .succeeded)
        let newer = OutboundCall(host: "b.test", model: "m", at: Date(timeIntervalSince1970: 2), noteCount: 2, estimatedTokens: 20, outcome: .succeeded)
        try log.record(older)
        try log.record(newer)
        XCTAssertEqual(try log.list().map(\.host), ["b.test", "a.test"])
    }

    /// The rule this log lives or dies by, and the same one
    /// `MCPConnectionActivity` already holds: metadata, never note contents. A
    /// diagnostic that quietly accumulates the user's own writing would be a
    /// worse leak than the feature it exists to make auditable.
    func testAWholeRunLeavesNoNoteContentInTheLog() async throws {
        let secret = "the paywall price is fourteen ninety nine"
        let older = try service.createNote(title: "MCP server registration", body: secret, source: "human")
        _ = try service.createNote(title: "MCP Server Registration", body: secret, source: "claude")

        let provider = StubReasoningProvider(reply: """
        {"actions": [
          {"action": "flag_for_review", "note_id": "\(older.id.uuidString)", "reason": "\(secret)"},
          {"action": "archive_note", "note_id": "\(older.id.uuidString)"}
        ]}
        """)
        let runner = ReasoningRunner(
            service: service, provider: provider, log: log,
            cursorURL: ReasoningCursor.url(besideEventLog: tempURL)
        )
        _ = try await runner.execute(try runner.plan(scope: .janitorShortlist, task: "judge"))

        let raw = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(raw.contains(secret), "note content reached the outbound log")
        XCTAssertFalse(raw.contains("MCP server registration"), "a note title reached the outbound log")

        let call = try XCTUnwrap(try log.list().first)
        XCTAssertEqual(call.host, "api.example.test")
        XCTAssertEqual(call.noteCount, 2)
        XCTAssertEqual(call.outcome, .succeeded)
        XCTAssertEqual(call.reportedTokens, 940)
        XCTAssertEqual(call.detail, "1 applied, 1 refused")
    }

    /// "We chose not to call" is evidence too. A log that only lists successes
    /// answers an easier question than the one the Trust Center was built for.
    func testARunThatSendsNothingStillLeavesAReceipt() async throws {
        let runner = ReasoningRunner(service: service, provider: NullReasoningProvider(), log: log)
        _ = try await runner.execute(try runner.plan(scope: .janitorShortlist, task: "judge"))

        let call = try XCTUnwrap(try log.list().first)
        XCTAssertEqual(call.outcome, .notSent)
        XCTAssertEqual(call.noteCount, 0)
        XCTAssertEqual(call.detail, "no provider configured")
    }

    func testDryRunIsRecordedAsSuch() throws {
        let runner = ReasoningRunner(service: service, provider: StubReasoningProvider(), log: log)
        let note = Note(id: UUID(), title: "t", body: "b", createdAt: Date(), updatedAt: Date())
        let plan = ReasoningRun.plan(
            task: "judge", host: "api.example.test", model: "gpt-5",
            candidates: [note], cursor: ReasoningCursor(), caps: .default
        )
        let call = runner.recordDryRun(plan)
        XCTAssertEqual(call.outcome, .dryRun)
        XCTAssertEqual(try log.list().first?.outcome, .dryRun)
    }
}

/// The key must not end up anywhere weaker than the keychain. These cover the
/// contract every implementation has to hold; the real Keychain-backed store is
/// exercised by the app, not by the suite, which must never touch the login
/// keychain.
final class ReasoningKeyStoreTests: XCTestCase {
    func testStoresRetrievesAndRemovesPerHost() throws {
        let store = InMemoryReasoningKeyStore()
        XCTAssertNil(try store.key(forHost: "api.example.test"))

        try store.setKey("sk-one", forHost: "api.example.test")
        try store.setKey("sk-two", forHost: "openrouter.test")
        XCTAssertEqual(try store.key(forHost: "api.example.test"), "sk-one")
        XCTAssertEqual(try store.key(forHost: "openrouter.test"), "sk-two")

        try store.setKey("sk-three", forHost: "API.EXAMPLE.TEST")
        XCTAssertEqual(try store.key(forHost: "api.example.test"), "sk-three", "host lookup must be case-insensitive")

        try store.removeKey(forHost: "api.example.test")
        XCTAssertNil(try store.key(forHost: "api.example.test"))
        XCTAssertEqual(try store.key(forHost: "openrouter.test"), "sk-two")
    }

    /// The keychain service string is load-bearing: changing it orphans every
    /// stored key on every install.
    func testKeychainServiceStringIsStable() {
        XCTAssertEqual(KeychainReasoningKeyStore.service, "com.calmdownoscar.unlirice.reasoning")
    }
}
