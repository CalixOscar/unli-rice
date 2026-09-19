import XCTest
@testable import UnliRiceCore

final class TodoHandoffTests: XCTestCase {

    private func makeNote(
        id: UUID = UUID(),
        title: String = "Test Note",
        body: String = "",
        tags: [String] = [],
        creator: String = "test"
    ) -> Note {
        Note(
            id: id,
            title: title,
            body: body,
            tags: Set(tags),
            creator: creator,
            createdAt: Date(),
            updatedAt: Date(),
            archived: false
        )
    }

    func testNoFirstLineId() {
        let item = makeNote(title: "Task 1", body: "Plain body without any handoff id", tags: ["todo"])
        XCTAssertNil(TodoHandoff.handoffID(inBody: item.body))
        let target = TodoHandoff.target(for: item, lookup: { _ in nil })
        XCTAssertEqual(target.id, item.id)
    }

    func testIdForNonHandoffNoteReturnsItem() {
        let otherID = UUID()
        let nonHandoffNote = makeNote(id: otherID, title: "Regular Note", body: "No handoff tag", tags: ["random"])
        let item = makeNote(title: "Task 2", body: "Handoff-ID: \(otherID.uuidString)\nSome description", tags: ["todo"])

        XCTAssertEqual(TodoHandoff.handoffID(inBody: item.body), otherID)
        let target = TodoHandoff.target(for: item, lookup: { id in
            id == otherID ? nonHandoffNote : nil
        })
        XCTAssertEqual(target.id, item.id)
    }

    func testIdForMissingNoteReturnsItem() {
        let missingID = UUID()
        let item = makeNote(title: "Task 3", body: "Handoff-ID: \(missingID.uuidString)\nSome description", tags: ["todo"])

        XCTAssertEqual(TodoHandoff.handoffID(inBody: item.body), missingID)
        let target = TodoHandoff.target(for: item, lookup: { _ in nil })
        XCTAssertEqual(target.id, item.id)
    }

    func testOldItemWithOrdinaryWikiLinkReturnsItem() {
        let item = makeNote(title: "Old task", body: "See [[Some Prior Note]] for details\nSecond line", tags: ["todo"])
        XCTAssertNil(TodoHandoff.handoffID(inBody: item.body))
        let target = TodoHandoff.target(for: item, lookup: { _ in nil })
        XCTAssertEqual(target.id, item.id)
    }

    func testTitleContainingDoubleBracketsHasNoEffect() {
        let handoffID = UUID()
        let handoffNote = makeNote(
            id: handoffID,
            title: "Handoff with [[odd]] title",
            body: "Checkpoint details",
            tags: ["handoff"]
        )
        let item = makeNote(
            title: "Task [[nested]]",
            body: "Handoff-ID: \(handoffID.uuidString)\n[[Handoff with [[odd]] title]]",
            tags: ["todo"]
        )

        XCTAssertEqual(TodoHandoff.handoffID(inBody: item.body), handoffID)
        let target = TodoHandoff.target(for: item, lookup: { id in
            id == handoffID ? handoffNote : nil
        })
        XCTAssertEqual(target.id, handoffNote.id)
        XCTAssertEqual(target.title, "Handoff with [[odd]] title")
    }

    func testValidHandoffResolvesTarget() {
        let handoffID = UUID()
        let handoffNote = makeNote(
            id: handoffID,
            title: "Handoff — CalmdownOscar — 2026-09-19",
            body: "Handoff body",
            tags: ["handoff", "calmdownoscar"]
        )
        let item = makeNote(
            title: "Deferred item",
            body: "Handoff-ID: \(handoffID.uuidString)\nContext notes",
            tags: ["todo", "calmdownoscar"]
        )

        let target = TodoHandoff.target(for: item, lookup: { id in
            id == handoffID ? handoffNote : nil
        })
        XCTAssertEqual(target.id, handoffNote.id)
    }
}
