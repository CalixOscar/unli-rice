import XCTest
@testable import UnliRiceCore

/// End-to-end for the thing that runs with the window closed.
///
/// `RoutineSchedulerTests` covers *whether* a routine may run. This covers what
/// happens when it does: work actually lands in the corpus, the slot is recorded
/// so it isn't served twice, a failure leaves the slot unserved, and the human
/// finds out through the notification centre rather than by going looking.
final class RoutineDriverTests: XCTestCase {
    private var directory: URL!
    private var logURL: URL!
    private var service: NoteService!

    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// 2026-07-21 is a Tuesday; ingest is scheduled for 09:00.
    private var tuesdayMorning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 7, day: 21, hour: 10))!
    }

    private let alwaysReady = MachineState(isOnPower: true, idleFor: 3600)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-driver-tests-\(UUID().uuidString)")
        logURL = directory.appendingPathComponent("events.jsonl")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        service = NoteService(store: try EventStore(fileURL: logURL))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stub pipeline. The real one scans `~/.claude/projects`, which a test
    /// has no business touching.
    private struct StubImporter: ResourceImporter {
        let identifier = "stub"
        let displayName = "Stub"
        var resources: [DiscoveredResource] = []
        var failure: Error?

        func discover() throws -> [DiscoveredResource] {
            if let failure { throw failure }
            return resources
        }
    }

    private struct Boom: Error, CustomStringConvertible {
        var description: String { "the disk went away" }
    }

    private func resource(named name: String) throws -> DiscoveredResource {
        let file = directory.appendingPathComponent("\(name).md")
        try "# \(name)\n\nsome prose".write(to: file, atomically: true, encoding: .utf8)
        return DiscoveredResource(
            sourceURL: file,
            key: name,
            title: name,
            summary: "a document",
            tags: ["ingested"],
            occurredAt: tuesdayMorning
        )
    }

    private func makeDriver(_ importer: StubImporter) -> RoutineDriver {
        RoutineDriver(service: service, eventLogURL: logURL, pipelines: { _ in [importer] })
    }

    private var settings: AgentSettings {
        AgentSettings(routinesEnabled: true, autonomyLevel: 2, monthlyReviewEnabled: false)
    }

    // MARK: -

    func testADueRoutineActuallyRunsAndIsNotRunAgainForTheSameSlot() throws {
        let driver = makeDriver(StubImporter(resources: [try resource(named: "first")]))

        let first = driver.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)
        XCTAssertTrue(first.ran.contains { $0.kind == .dataIngestion && !$0.failed })
        XCTAssertEqual(try service.listNotes().count, 1)

        // Same slot, second beat — the GUI heartbeat and launchd both firing.
        let second = driver.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)
        XCTAssertFalse(second.ran.contains { $0.kind == .dataIngestion })
        XCTAssertEqual(second.holds[.dataIngestion], "already ran for this slot")
        XCTAssertEqual(try service.listNotes().count, 1)
    }

    func testNothingRunsWhileRoutinesAreOff() throws {
        let driver = makeDriver(StubImporter(resources: [try resource(named: "first")]))
        let report = driver.tick(
            now: tuesdayMorning,
            settings: AgentSettings(routinesEnabled: false, autonomyLevel: 2),
            machine: alwaysReady,
            calendar: calendar
        )

        XCTAssertFalse(report.didWork)
        XCTAssertEqual(try service.listNotes().count, 0)
    }

    /// Eco's promise, enforced from the daemon exactly as from the window: no
    /// autonomy level grants any permission the manual button doesn't have, it
    /// only changes when work is allowed to start.
    func testEcoStillWaitsForPowerWhenRunningHeadless() throws {
        let driver = makeDriver(StubImporter(resources: [try resource(named: "first")]))
        let report = driver.tick(
            now: tuesdayMorning,
            settings: AgentSettings(routinesEnabled: true, autonomyLevel: 0),
            machine: MachineState(isOnPower: false, idleFor: 3600),
            calendar: calendar
        )

        XCTAssertFalse(report.didWork)
        XCTAssertEqual(report.holds[.dataIngestion], "Eco runs only while plugged in")
    }

    /// A failed slot must stay unserved. A pipeline that quietly stops while
    /// still looking maintained is the failure mode this whole design fears
    /// most — so the failure is both retried and *reported*.
    func testAFailedRunLeavesTheSlotUnservedAndSaysSo() throws {
        let failing = makeDriver(StubImporter(failure: Boom()))
        let report = failing.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)

        XCTAssertTrue(report.ran.contains { $0.kind == .dataIngestion && $0.failed })
        XCTAssertTrue(report.posted.contains { $0.kind == .problem })

        let state = RoutineState.load(from: RoutineState.url(besideEventLog: logURL))
        XCTAssertNil(state.lastRun(of: .dataIngestion))

        // A later beat with a working pipeline serves the same slot.
        let working = makeDriver(StubImporter(resources: [try resource(named: "recovered")]))
        let retry = working.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)
        XCTAssertTrue(retry.ran.contains { $0.kind == .dataIngestion && !$0.failed })
    }

    /// The point of the notification centre: you find out because it's here next
    /// time you're in the app, not because you remembered to check a queue.
    func testWorkQueuedByAnUnattendedRunIsAnnounced() throws {
        let note = try service.createNote(title: "Duplicate-ish", body: "", source: "human")
        try service.flagForReview(id: note.id, reason: "looks like another note", source: "janitor")

        let driver = makeDriver(StubImporter())
        let posted = driver.announceNow(settings: settings)

        XCTAssertTrue(posted.contains { $0.destination == .reviewQueue })
        XCTAssertEqual(driver.noticeStore.unreadCount(), 1)
    }

    /// A run that changed nothing is the system working. Saying so every five
    /// minutes is how a notification centre earns being ignored.
    func testAQuietRunPostsNothing() throws {
        let driver = makeDriver(StubImporter())
        let report = driver.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)

        XCTAssertTrue(report.didWork)          // it ran
        XCTAssertTrue(report.posted.isEmpty)   // and had nothing to say
    }

    /// The corpus-scoped state file is what stops the GUI and the daemon each
    /// keeping their own idea of what's been done.
    func testTheRunIsRecordedWhereBothProcessesCanSeeIt() throws {
        let driver = makeDriver(StubImporter(resources: [try resource(named: "first")]))
        driver.tick(now: tuesdayMorning, settings: settings, machine: alwaysReady, calendar: calendar)

        let state = RoutineState.load(from: RoutineState.url(besideEventLog: logURL))
        XCTAssertEqual(state.lastRun(of: .dataIngestion), tuesdayMorning)
    }
}
