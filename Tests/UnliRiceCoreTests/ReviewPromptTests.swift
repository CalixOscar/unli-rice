import XCTest
@testable import UnliRiceCore

/// Apple allows three prompts per 365 days and silently drops the rest, so every one of
/// these is guarding a budget that cannot be refilled.
final class ReviewPromptTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    func testNoAskBeforeTheFirstMilestone() {
        XCTAssertNil(ReviewPrompt.milestoneToAsk(noteCount: 99, state: .init(), now: now))
    }

    func testAsksAtTheFirstMilestoneReached() {
        XCTAssertEqual(ReviewPrompt.milestoneToAsk(noteCount: 100, state: .init(), now: now), 100)
    }

    /// Someone who arrives with a large corpus should be asked at the rung they have
    /// actually reached, not walked up from the bottom over three separate prompts —
    /// that would spend the entire budget on one user in quick succession.
    func testSpendsTheHIGHESTMilestoneReachedNotTheLowest() {
        XCTAssertEqual(ReviewPrompt.milestoneToAsk(noteCount: 2500, state: .init(), now: now),
                       2000)
    }

    func testTheSameMilestoneNeverAsksTwice() {
        let after = ReviewPrompt.recordAsk(.init(), milestone: 100, now: daysAgo(365))
        XCTAssertNil(ReviewPrompt.milestoneToAsk(noteCount: 200, state: after, now: now),
                     "200 notes has not reached the next rung")
        XCTAssertEqual(ReviewPrompt.milestoneToAsk(noteCount: 600, state: after, now: now), 500)
    }

    /// The floor between asks. Three prompts inside a week would be within Apple's
    /// yearly ceiling and still obviously wrong.
    func testAFloorBetweenAsksEvenWhenABiggerMilestoneIsReached() {
        let recent = ReviewPrompt.recordAsk(.init(), milestone: 100, now: daysAgo(10))
        XCTAssertNil(ReviewPrompt.milestoneToAsk(noteCount: 5000, state: recent, now: now))

        let old = ReviewPrompt.recordAsk(.init(), milestone: 100, now: daysAgo(121))
        XCTAssertEqual(ReviewPrompt.milestoneToAsk(noteCount: 5000, state: old, now: now), 2000)
    }

    func testHardCapAtThreeAsksForever() {
        var s = ReviewPrompt.State()
        for (i, m) in ReviewPrompt.milestones.enumerated() {
            s = ReviewPrompt.recordAsk(s, milestone: m, now: daysAgo(1000 - i * 200))
        }
        XCTAssertEqual(s.asksMade, 3)
        XCTAssertNil(ReviewPrompt.milestoneToAsk(noteCount: 100_000, state: s, now: now),
                     "the cap is per install and does not reset")
    }

    /// Recording must carry the rung, not just the fact of asking. Losing that is how a
    /// ladder degrades into the single permanent boolean this replaces.
    func testRecordingCarriesWhichRungWasSpent() {
        let s = ReviewPrompt.recordAsk(.init(), milestone: 500, now: now)
        XCTAssertEqual(s.highestMilestoneUsed, 500)
        XCTAssertEqual(s.lastAsk, now)
        XCTAssertNil(ReviewPrompt.milestoneToAsk(noteCount: 500, state: s, now: now))
    }

    func testStateRoundTripsThroughCodable() throws {
        let s = ReviewPrompt.recordAsk(.init(), milestone: 100, now: now)
        let back = try JSONDecoder().decode(ReviewPrompt.State.self,
                                            from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }
}
