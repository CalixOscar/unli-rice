import XCTest
@testable import UnliRiceCore

final class UnwrittenClientsTests: XCTestCase {

    private func makeActivity(
        name: String,
        version: String? = nil,
        lastToolName: String? = nil,
        lastWriteAt: Date? = nil,
        lastSeenAt: Date = Date()
    ) -> MCPConnectionActivity {
        MCPConnectionActivity(
            id: "\(name):\(version ?? "")",
            clientName: name,
            clientVersion: version,
            firstSeenAt: lastSeenAt.addingTimeInterval(-100),
            lastSeenAt: lastSeenAt,
            lastToolName: lastToolName,
            lastToolCallAt: lastToolName != nil ? lastSeenAt : nil,
            lastToolSucceeded: lastToolName != nil ? true : nil,
            lastContextDeliveredAt: nil,
            lastWriteAt: lastWriteAt
        )
    }

    // 11. Only tool call is search_notes, name in no event source -> reported
    func testOnlySearchToolCallReportedAsUnwritten() {
        let act = makeActivity(name: "Claude Code", lastToolName: "search_notes", lastWriteAt: nil)
        let unwritten = UnwrittenClients.firstUnwritten(among: [act], knownWriterSources: [])
        XCTAssertNotNil(unwritten)
        XCTAssertEqual(unwritten?.clientName, "Claude Code")
    }

    // 12. Write, then search on a newer client-version record -> not reported (version-collapsing fix)
    func testWriteThenSearchOnNewerVersionNotReported() {
        let t1 = Date().addingTimeInterval(-50)
        let t2 = Date()
        let oldWrite = makeActivity(name: "Claude Code", version: "1.2", lastToolName: "create_note", lastWriteAt: t1, lastSeenAt: t1)
        let newSearch = makeActivity(name: "Claude Code", version: "1.3", lastToolName: "search_notes", lastWriteAt: nil, lastSeenAt: t2)

        let unwritten = UnwrittenClients.firstUnwritten(among: [oldWrite, newSearch], knownWriterSources: [])
        XCTAssertNil(unwritten, "write evidence from earlier version record must protect the client")
    }

    // 13. Write -> failed write -> still not reported (evidence is not revoked by a later failure)
    func testFailedWriteDoesNotRevokeEarlierWriteEvidence() {
        let t1 = Date().addingTimeInterval(-50)
        let t2 = Date()
        let write = makeActivity(name: "Claude Code", lastToolName: "create_note", lastWriteAt: t1, lastSeenAt: t1)
        var failedWrite = makeActivity(name: "Claude Code", lastToolName: "append_to_note", lastWriteAt: nil, lastSeenAt: t2)
        failedWrite.lastToolSucceeded = false

        let unwritten = UnwrittenClients.firstUnwritten(among: [write, failedWrite], knownWriterSources: [])
        XCTAssertNil(unwritten, "subsequent failure cannot revoke prior write evidence")
    }

    // 14. Reopening: fresh record for existing client inherits nothing, union still finds earlier write
    func testFreshRecordForExistingClientFindsEarlierWriteInUnion() {
        let t1 = Date().addingTimeInterval(-100)
        let t2 = Date()
        let earlierRecord = makeActivity(name: "Claude Code", lastToolName: "create_note", lastWriteAt: t1, lastSeenAt: t1)
        let freshReopenedRecord = makeActivity(name: "Claude Code", lastToolName: nil, lastWriteAt: nil, lastSeenAt: t2)

        let unwritten = UnwrittenClients.firstUnwritten(among: [earlierRecord, freshReopenedRecord], knownWriterSources: [])
        XCTAssertNil(unwritten)
    }

    // 15. Alias table: Claude Code <-> claude-code <-> claude all match
    func testAliasTableMatchesAcrossRepresentations() {
        let act1 = makeActivity(name: "Claude Code", lastToolName: "search_notes", lastWriteAt: nil)
        let act2 = makeActivity(name: "claude-code", lastToolName: "search_notes", lastWriteAt: nil)
        let act3 = makeActivity(name: "claude", lastToolName: "search_notes", lastWriteAt: nil)

        // Matches against known writer source "claude"
        XCTAssertNil(UnwrittenClients.firstUnwritten(among: [act1], knownWriterSources: ["claude"]))
        XCTAssertNil(UnwrittenClients.firstUnwritten(among: [act2], knownWriterSources: ["claude"]))
        XCTAssertNil(UnwrittenClients.firstUnwritten(among: [act3], knownWriterSources: ["claude"]))

        // Matches against known writer source "claude-code"
        XCTAssertNil(UnwrittenClients.firstUnwritten(among: [act1], knownWriterSources: ["claude-code"]))

        // Direct matching predicate
        XCTAssertTrue(UnwrittenClients.matches(clientName: "Claude Code", writerSource: "claude"))
        XCTAssertTrue(UnwrittenClients.matches(clientName: "claude-code", writerSource: "claude"))
        XCTAssertTrue(UnwrittenClients.matches(clientName: "Claude Code", writerSource: "claude-code"))
    }
}
