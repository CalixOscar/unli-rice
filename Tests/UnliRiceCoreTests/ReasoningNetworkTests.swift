import XCTest
@testable import UnliRiceCore

/// Counts every URL request any default-configured `URLSession` makes, so a
/// test can assert that a code path made none at all.
final class RequestCounter: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _count = 0

    static var count: Int {
        lock.lock(); defer { lock.unlock() }
        return _count
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        _count = 0
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        _count += 1
        lock.unlock()
        // Never actually claim the request — the point is to observe, and no
        // test here wants a fake response.
        return false
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

/// The promise that matters most to the overwhelming majority of installs:
/// **with no key configured, this app's network behaviour is byte-for-byte what
/// it was before this feature existed.** It is a free open-source app and most
/// people will never configure a provider; nothing about the app may change for
/// them, including what it talks to.
final class ReasoningNoKeyTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!

    override func setUpWithError() throws {
        URLProtocol.registerClass(RequestCounter.self)
        RequestCounter.reset()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-reasoning-net-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        service = NoteService(store: try EventStore(fileURL: tempURL))
    }

    override func tearDownWithError() throws {
        URLProtocol.unregisterClass(RequestCounter.self)
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    /// A whole run — plan, execute, dispatch, log — against the default
    /// provider, with a corpus the rules have plenty to say about. Zero requests.
    func testAFullRunWithNoProviderMakesNoNetworkRequests() async throws {
        let a = try service.createNote(title: "MCP server registration", body: "the mcp setup", source: "claude")
        try service.tagNote(id: a.id, tag: "mcp", source: "claude")
        let b = try service.createNote(title: "Export pipeline", body: "mcp adjacent", source: "claude")
        try service.tagNote(id: b.id, tag: "mcp", source: "claude")
        try service.createNote(title: "MCP Server Registration", body: "duplicate-ish", source: "gemini")

        let runner = ReasoningRunner(
            service: service,
            provider: NullReasoningProvider(),
            log: OutboundCallLog(besideEventLog: tempURL),
            cursorURL: ReasoningCursor.url(besideEventLog: tempURL)
        )

        let plan = try runner.plan(scope: .janitorShortlist, task: "judge these", config: JanitorConfig(autonomy: .aggressive))
        XCTAssertFalse(plan.canSend)
        XCTAssertEqual(plan.blocked, .noProvider)

        let report = try await runner.execute(plan)
        XCTAssertNil(report.dispatch)
        XCTAssertEqual(report.call.outcome, .notSent)
        XCTAssertEqual(RequestCounter.count, 0, "the no-key path reached the network")
    }

    /// The guarantee is structural, not a caller remembering to check: an empty
    /// key cannot be turned into a provider at all, so there is no object that
    /// could make the request.
    func testAProviderCannotBeBuiltWithoutAKey() {
        let url = URL(string: "https://api.example.com/v1")!
        for key in ["", "   ", "\n"] {
            XCTAssertThrowsError(try OpenAICompatibleReasoning(baseURL: url, model: "gpt-5", apiKey: key))
        }
        XCTAssertEqual(RequestCounter.count, 0)
    }

    func testTheDefaultProviderIsNotConfiguredAndAnswersNothing() async throws {
        let provider = NullReasoningProvider()
        XCTAssertFalse(provider.isConfigured)
        XCTAssertNil(provider.host)

        let response = try await provider.judge(
            JudgementRequest(system: "s", user: "u", maxOutputTokens: 100)
        )
        XCTAssertEqual(response, .none)
        XCTAssertTrue(ReasoningActionParser.parse(response.text).allowed.isEmpty)
        XCTAssertEqual(RequestCounter.count, 0)
    }

    /// This type is the one place allowed to reach a non-local host, and it must
    /// not become a second way to reach one for embeddings.
    func testRemoteSimilarityIsStillLocalhostOnly() {
        XCTAssertThrowsError(
            try RemoteSimilarity(baseURL: URL(string: "https://api.example.com/v1")!, model: "m"),
            "the loopback rule was weakened"
        )
        XCTAssertNoThrow(
            try OpenAICompatibleReasoning(
                baseURL: URL(string: "https://api.example.com/v1")!, model: "gpt-5", apiKey: "sk-test"
            ),
            "the reasoning provider is deliberately not loopback-restricted"
        )
    }

    func testRejectsBaseURLsThatArentHTTP() {
        for bad in ["file:///etc/passwd", "ftp://example.com/v1"] {
            XCTAssertThrowsError(
                try OpenAICompatibleReasoning(baseURL: URL(string: bad)!, model: "m", apiKey: "sk-test"),
                bad
            )
        }
    }
}
