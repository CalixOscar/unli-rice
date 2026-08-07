import XCTest
@testable import UnliRiceCore

final class ConnectionActivityTests: XCTestCase {
    private var root: URL!
    private var store: MCPConnectionActivityStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-connection-tests-\(UUID().uuidString)", isDirectory: true)
        store = MCPConnectionActivityStore(fileURL: root.appendingPathComponent("connections.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testConnectionAndToolCallAreRecordedWithoutArguments() throws {
        let first = Date(timeIntervalSince1970: 100)
        let second = Date(timeIntervalSince1970: 200)
        try store.recordConnection(clientName: "Codex", clientVersion: "1.0", at: first)
        try store.recordToolCall(
            clientName: "Codex",
            clientVersion: "1.0",
            toolName: "search_notes",
            succeeded: true,
            at: second
        )

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.clientName, "Codex")
        XCTAssertEqual(activity.firstSeenAt, first)
        XCTAssertEqual(activity.lastSeenAt, second)
        XCTAssertEqual(activity.lastToolName, "search_notes")
        XCTAssertEqual(activity.lastToolSucceeded, true)

        let persisted = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(persisted.contains("query"))
        XCTAssertFalse(persisted.contains("arguments"))
    }

    func testDifferentVersionsRemainAttributable() throws {
        try store.recordConnection(clientName: "Claude", clientVersion: "1", at: Date(timeIntervalSince1970: 100))
        try store.recordConnection(clientName: "Claude", clientVersion: "2", at: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(try store.list().map(\.clientVersion), ["2", "1"])
    }

    func testConnectedWithoutToolCallHasNilLastToolCallAt() throws {
        let now = Date(timeIntervalSince1970: 500)
        try store.recordConnection(clientName: "Claude Code", clientVersion: "1.0", at: now)

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.clientName, "Claude Code")
        XCTAssertEqual(activity.lastSeenAt, now)
        XCTAssertNil(activity.lastToolName)
        XCTAssertNil(activity.lastToolCallAt)
        XCTAssertNil(activity.lastToolSucceeded)
        // The distinction the Trust Center alarm turns on: connected and given
        // nothing is not the same as connected and handed the vault.
        XCTAssertNil(activity.lastContextDeliveredAt)
    }

    func testContextDeliveryIsRecordedWithoutClaimingAToolCall() throws {
        let now = Date(timeIntervalSince1970: 600)
        try store.recordContextDelivery(clientName: "Claude Code", clientVersion: nil, at: now)

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.lastContextDeliveredAt, now)
        XCTAssertEqual(activity.lastSeenAt, now)
        // Vault Mode reads files; nothing here can observe that, so delivery
        // must never masquerade as a confirmed read.
        XCTAssertNil(activity.lastToolCallAt)
        XCTAssertNil(activity.lastToolName)
    }

    func testDeliveryThenToolCallKeepsBothSignals() throws {
        let delivered = Date(timeIntervalSince1970: 700)
        let called = Date(timeIntervalSince1970: 800)
        try store.recordContextDelivery(clientName: "Claude Code", clientVersion: nil, at: delivered)
        try store.recordToolCall(
            clientName: "Claude Code",
            clientVersion: nil,
            toolName: "search_notes",
            succeeded: true,
            at: called
        )

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.lastContextDeliveredAt, delivered)
        XCTAssertEqual(activity.lastToolCallAt, called)
    }

    func testActivityWrittenBeforeContextFieldExistedStillDecodes() throws {
        // The prompt hook and older builds both write records without the new
        // key; a store that refuses them would take the whole Trust Center down.
        let legacy = """
        {"version":1,"clients":[{"id":"Codex","clientName":"Codex",\
        "firstSeenAt":"2026-08-04T10:00:00Z","lastSeenAt":"2026-08-04T10:00:00Z"}]}
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(legacy.utf8).write(to: root.appendingPathComponent("connections.json"))

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.clientName, "Codex")
        XCTAssertNil(activity.lastContextDeliveredAt)
    }

    func testRecordWrittenByThePromptHookDecodes() throws {
        // Verbatim output of Scripts/unlirice-prompt-hook.py. The hook writes
        // this file from Python while the app reads it from Swift, so the two
        // encoders have to agree — including the `Z`-suffixed ISO-8601 dates
        // that `.iso8601` decoding expects.
        let fromHook = """
        {
          "version": 1,
          "clients": [
            {
              "id": "Claude Code",
              "clientName": "Claude Code",
              "firstSeenAt": "2026-08-04T03:52:02Z",
              "lastSeenAt": "2026-08-04T03:52:02Z",
              "lastContextDeliveredAt": "2026-08-04T03:52:02Z"
            }
          ]
        }
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(fromHook.utf8).write(to: root.appendingPathComponent("connections.json"))

        let activity = try XCTUnwrap(store.list().first)
        XCTAssertEqual(activity.id, "Claude Code")
        XCTAssertNotNil(activity.lastContextDeliveredAt)
        XCTAssertNil(activity.lastToolCallAt)
    }
}
