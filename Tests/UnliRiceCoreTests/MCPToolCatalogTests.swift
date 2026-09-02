import XCTest
@testable import UnliRiceCore

final class MCPToolCatalogTests: XCTestCase {

    // 22. MCPTool.allCases covers every case the dispatcher switches on
    func testMCPToolAllCasesExhaustiveness() {
        let expectedTools: Set<String> = [
            "create_note",
            "append_to_note",
            "tag_note",
            "untag_note",
            "archive_note",
            "unarchive_note",
            "flag_for_review",
            "resolve_review",
            "get_note",
            "list_notes",
            "search_notes",
            "note_history",
            "pending_reviews",
            "transaction_log"
        ]

        let actualTools = Set(MCPTool.allCases.map(\.rawValue))
        XCTAssertEqual(actualTools, expectedTools)
        XCTAssertEqual(MCPTool.allCases.count, 14)

        // Verify write classification
        let writeTools: Set<MCPTool> = [
            .createNote,
            .appendToNote,
            .tagNote,
            .untagNote,
            .archiveNote,
            .unarchiveNote,
            .flagForReview,
            .resolveReview
        ]

        for tool in MCPTool.allCases {
            XCTAssertEqual(tool.isWrite, writeTools.contains(tool), "tool \(tool.rawValue) write classification mismatch")
        }
    }
}
