import XCTest
@testable import UnliRiceCore

final class NoteProvenanceTests: XCTestCase {
    func testParsesMostRecentIngestProvenance() {
        let body = """
        **File:** `/old/note.md`
        **Raw:** `old-note.md` [raw:old]

        **Revised:** later
        **File:** `/new/note.md`
        **Project:** `/Projects/Unli Rice`
        **Session:** `session-123`
        **Raw:** `new-note.md` [raw:new]
        """

        let provenance = NoteProvenance.parse(body)
        XCTAssertEqual(provenance.rawFilename, "new-note.md")
        XCTAssertEqual(provenance.sourceFilePath, "/new/note.md")
        XCTAssertEqual(provenance.projectPath, "/Projects/Unli Rice")
        XCTAssertEqual(provenance.sessionID, "session-123")
    }

    func testRawURLLivesBesideEventLog() {
        let provenance = NoteProvenance(rawFilename: "source.jsonl")
        let log = URL(fileURLWithPath: "/vault/events.jsonl")
        XCTAssertEqual(provenance.rawURL(besideEventLog: log)?.path, "/vault/raw/source.jsonl")
    }
}
