import XCTest
@testable import UnliRiceCore

final class TrackpadSwipeTests: XCTestCase {
    func testSwipeLeftFlipsNextOnce() {
        var swipe = TrackpadSwipe()
        _ = swipe.handle(phase: .began, fingerDX: 0, dy: 0)
        let results = (0..<10).map { _ in swipe.handle(phase: .changed, fingerDX: -10, dy: 0) }
        XCTAssertTrue(results.allSatisfy(\.consume))
        XCTAssertEqual(results.compactMap(\.flip), [1])
    }
    func testSwipeRightFlipsPrevious() {
        var swipe = TrackpadSwipe()
        let result = swipe.handle(phase: .began, fingerDX: 50, dy: 0)
        XCTAssertTrue(result.consume); XCTAssertEqual(result.flip, -1)
    }
    func testBelowThresholdDoesNotFlip() {
        var swipe = TrackpadSwipe()
        XCTAssertNil(swipe.handle(phase: .began, fingerDX: -40, dy: 0).flip)
    }
    func testVerticalGestureNeverFlipsOrConsumes() {
        var swipe = TrackpadSwipe()
        _ = swipe.handle(phase: .began, fingerDX: 0, dy: 0)
        let first = swipe.handle(phase: .changed, fingerDX: -1, dy: -20)
        XCTAssertFalse(first.consume); XCTAssertNil(first.flip)
        for _ in 0..<60 {
            let result = swipe.handle(phase: .changed, fingerDX: -10, dy: 0)
            XCTAssertFalse(result.consume); XCTAssertNil(result.flip)
        }
    }
    func testMomentumAfterHorizontalIsConsumed() {
        var swipe = TrackpadSwipe()
        _ = swipe.handle(phase: .began, fingerDX: -10, dy: 0)
        XCTAssertTrue(swipe.handle(phase: .ended, fingerDX: 0, dy: 0).consume)
        XCTAssertTrue(swipe.handle(phase: .momentum, fingerDX: 0, dy: 0).consume)
    }
    func testMomentumAfterVerticalPassesThrough() {
        var swipe = TrackpadSwipe()
        _ = swipe.handle(phase: .began, fingerDX: 0, dy: 10)
        XCTAssertFalse(swipe.handle(phase: .ended, fingerDX: 0, dy: 0).consume)
        XCTAssertFalse(swipe.handle(phase: .momentum, fingerDX: 0, dy: 0).consume)
    }
    func testOtherPhasePassesThrough() {
        var swipe = TrackpadSwipe()
        let result = swipe.handle(phase: .other, fingerDX: -100, dy: 0)
        XCTAssertFalse(result.consume); XCTAssertNil(result.flip)
    }
    func testNextGestureFlipsAgain() {
        var swipe = TrackpadSwipe()
        XCTAssertEqual(swipe.handle(phase: .began, fingerDX: -50, dy: 0).flip, 1)
        _ = swipe.handle(phase: .ended, fingerDX: 0, dy: 0)
        XCTAssertEqual(swipe.handle(phase: .began, fingerDX: -50, dy: 0).flip, 1)
    }
}
