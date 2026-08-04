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
    }
}
