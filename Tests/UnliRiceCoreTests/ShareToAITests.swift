import XCTest
@testable import UnliRiceCore

final class ShareToAITests: XCTestCase {
    private func note(_ title: String, body: String) -> Note {
        Note(id: UUID(), title: title, body: body, createdAt: Date(), updatedAt: Date())
    }

    func testEmptySelectionComposesToNothing() {
        XCTAssertEqual(ShareToAI.compose([]), "")
    }

    func testComposesThePreambleAndEveryNoteUnedited() {
        let notes = [
            note("Loose idea one", body: "we should ship the blue theme"),
            note("Loose idea two", body: "also fix the mic button")
        ]
        let text = ShareToAI.compose(notes)

        XCTAssertTrue(text.hasPrefix(ShareToAI.preamble))
        for n in notes {
            XCTAssertTrue(text.contains(n.title), "missing title: \(n.title)")
            XCTAssertTrue(text.contains(n.body), "missing body: \(n.body)")
        }
    }

    /// Nothing here may summarise or truncate — a body cut short is a different
    /// note, and this type has no way to say which half it kept.
    func testDoesNotAlterOrTruncateBodies() {
        // Ends in a non-whitespace character deliberately: the whole composed
        // message is trimmed at its outer edges (so a shared note doesn't carry
        // a dangling blank line), which would otherwise eat a body's own
        // trailing whitespace in this single-note case — a trim artifact, not
        // truncation.
        let big = String(repeating: "word ", count: 2_000) + "end"
        let text = ShareToAI.compose([note("Big note", body: big)])
        XCTAssertTrue(text.contains(big))
    }

    /// Order is preserved — whatever order the caller selected them in, since
    /// this type has no basis to reorder by "relevance" without reasoning about
    /// content, which it deliberately doesn't do.
    func testPreservesSelectionOrder() {
        let notes = [note("First", body: "a"), note("Second", body: "b"), note("Third", body: "c")]
        let text = ShareToAI.compose(notes)
        let firstRange = text.range(of: "First")!
        let secondRange = text.range(of: "Second")!
        let thirdRange = text.range(of: "Third")!
        XCTAssertTrue(firstRange.lowerBound < secondRange.lowerBound)
        XCTAssertTrue(secondRange.lowerBound < thirdRange.lowerBound)
    }

    func testEstimatedTokensIsCharactersDividedByFour() {
        XCTAssertEqual(ShareToAI.estimatedTokens(""), 0)
        XCTAssertEqual(ShareToAI.estimatedTokens("abcd"), 1)
        XCTAssertEqual(ShareToAI.estimatedTokens(String(repeating: "a", count: 400)), 100)
    }
}
