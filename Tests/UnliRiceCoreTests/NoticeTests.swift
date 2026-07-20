import XCTest
@testable import UnliRiceCore

final class NoticeTests: XCTestCase {
    var directory: URL!
    var store: NoticeStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-notice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = NoticeStore(fileURL: directory.appendingPathComponent("notices.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testPostingAndReadingBack() {
        store.post(Notice(kind: .routine, key: "a", title: "One", detail: ""))
        store.post(Notice(kind: .routine, key: "b", title: "Two", detail: ""))

        XCTAssertEqual(store.all().map(\.title), ["Two", "One"])
        XCTAssertEqual(store.unreadCount(), 2)
    }

    /// The whole reason `Notice.key` exists. An agent ticking every five minutes
    /// reports the same review queue 288 times a day; if each one stacked, the
    /// centre would be the thing you scroll past.
    func testTheSameSituationReplacesItselfWhileUnread() {
        store.post(Notice(kind: .review, key: "review-queue", title: "2 things need your OK", detail: ""))
        store.post(Notice(kind: .review, key: "review-queue", title: "3 things need your OK", detail: ""))

        XCTAssertEqual(store.all().count, 1)
        XCTAssertEqual(store.all().first?.title, "3 things need your OK")
    }

    /// …but once you've dealt with it, the situation recurring is news again.
    func testTheSameSituationPostsAgainOnceTheOldOneIsRead() {
        store.post(Notice(kind: .review, key: "review-queue", title: "First time", detail: ""))
        store.markAllRead()
        store.post(Notice(kind: .review, key: "review-queue", title: "Second time", detail: ""))

        XCTAssertEqual(store.all().count, 2)
        XCTAssertEqual(store.unreadCount(), 1)
    }

    func testReplacingKeepsTheIdSoAnOpenViewDoesNotLoseItsSelection() {
        let first = store.post(Notice(kind: .review, key: "k", title: "a", detail: ""))
        let second = store.post(Notice(kind: .review, key: "k", title: "b", detail: ""))
        XCTAssertEqual(first.id, second.id)
    }

    func testMarkingOneReadLeavesTheRest() {
        let target = store.post(Notice(kind: .routine, key: "a", title: "One", detail: ""))
        store.post(Notice(kind: .routine, key: "b", title: "Two", detail: ""))

        store.markRead(target.id)
        XCTAssertEqual(store.unreadCount(), 1)
        XCTAssertTrue(store.all().first { $0.id == target.id }!.isRead)
    }

    func testOlderNoticesFallOffTheEnd() {
        for index in 0..<(NoticeStore.capacity + 10) {
            store.post(Notice(kind: .routine, key: "k\(index)", title: "n\(index)", detail: ""))
        }
        XCTAssertEqual(store.all().count, NoticeStore.capacity)
        XCTAssertEqual(store.all().first?.title, "n\(NoticeStore.capacity + 9)")
    }

    func testDestinationsSurviveAFileRoundTrip() {
        store.post(
            Notice(
                kind: .retrospective, key: "r", title: "June", detail: "",
                destination: .retrospective(period: "2026-06")
            )
        )
        let reopened = NoticeStore(fileURL: directory.appendingPathComponent("notices.json"))
        XCTAssertEqual(reopened.all().first?.destination, .retrospective(period: "2026-06"))
    }

    // MARK: - What gets a notice at all

    /// A run that touched nothing is the system working correctly, and is not
    /// news. This is enforced in `RoutineDriver`; the factory's own rule is the
    /// narrower one — an empty queue produces no notice at all.
    func testAnEmptyReviewQueueProducesNoNotice() {
        XCTAssertNil(NoticeFactory.reviewQueue(pendingCount: 0, clusterCount: 0))
    }

    /// Five duplicate flags about one pile of notes are one decision, so the
    /// notice counts clusters rather than flags — the same collapsing
    /// `ReviewQueueView` does.
    func testTheReviewNoticeCountsDecisionsNotFlags() {
        let notice = NoticeFactory.reviewQueue(pendingCount: 5, clusterCount: 1)
        XCTAssertEqual(notice?.title, "One thing needs your OK")
    }

    func testAFailedRoutineGetsItsOwnLineRatherThanReplacingTheSuccess() {
        store.post(NoticeFactory.routineRan(kind: .dataIngestion, summary: "3 indexed"))
        store.post(NoticeFactory.routineFailed(kind: .dataIngestion, reason: "disk full"))

        XCTAssertEqual(store.all().count, 2)
        XCTAssertEqual(store.all().first?.kind, .problem)
    }
}
