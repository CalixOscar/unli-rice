import XCTest
@testable import UnliRiceCore

final class ProfileRevisionTests: XCTestCase {
    func testSingleUnsegmentedNoteReturnsWholeBody() {
        let raw = "Solo developer working on Unli Rice."
        XCTAssertEqual(ProfileRevision.latestBody(in: raw), raw)
    }

    func testLegacyRevisionFormatExtractsLatestBody() {
        let legacy = """
        Old identity text

        ---
        ### Revision (2026-08-01T12:00:00Z)

        New updated identity text for Unli Rice
        """
        XCTAssertEqual(ProfileRevision.latestBody(in: legacy), "New updated identity text for Unli Rice")
    }

    func testMarkerRevisionFormatExtractsLatestBody() {
        let wrapped = ProfileRevision.wrapped("Current active identity", title: "Profile: identity")
        let fullNote = """
        Old text

        ---

        \(wrapped)
        """
        XCTAssertEqual(ProfileRevision.latestBody(in: fullNote), "Current active identity")
    }

    func testNoteContainsCurrentRevisionMatching() {
        let wrapped = ProfileRevision.wrapped("Current active identity", title: "Profile: identity")
        XCTAssertTrue(ProfileRevision.noteContainsCurrentRevision(noteBody: wrapped, draftBody: "Current active identity"))
        XCTAssertFalse(ProfileRevision.noteContainsCurrentRevision(noteBody: wrapped, draftBody: "Stale identity"))
    }
}
