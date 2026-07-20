import XCTest
@testable import UnliRiceCore

final class RoutineSchedulerTests: XCTestCase {
    /// Fixed calendar and time zone: a scheduler test that depends on where the
    /// machine running it happens to be is a scheduler test that fails in CI.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return try XCTUnwrap(formatter.date(from: string))
    }

    private let alwaysReady = MachineState(isOnPower: true, idleFor: 3600)

    /// 2026-07-21 is a Tuesday, 2026-07-24 a Friday.
    private var tuesdayAndFriday: RoutineSchedule {
        RoutineSchedule(weekdays: [3, 6], hour: 9)
    }

    // MARK: - Firing times

    func testLastFiringIsTodayOnceTheHourHasPassed() throws {
        let firing = tuesdayAndFriday.lastFiring(before: try date("2026-07-21 10:00"), calendar: calendar)
        XCTAssertEqual(firing, try date("2026-07-21 09:00"))
    }

    func testLastFiringLooksBackWhenTheHourHasNotArrivedYet() throws {
        // 08:00 Tuesday — today's 09:00 hasn't happened, so the last real firing
        // is the previous Friday.
        let firing = tuesdayAndFriday.lastFiring(before: try date("2026-07-21 08:00"), calendar: calendar)
        XCTAssertEqual(firing, try date("2026-07-17 09:00"))
    }

    /// The point of looking backwards: a Mac asleep at 09:00 Tuesday still
    /// catches up when it wakes on Wednesday. A forward-only timer would skip
    /// the slot silently, and a pipeline that quietly stops is worse than one
    /// that never started.
    func testAMissedSlotIsCaughtUpRatherThanSkipped() throws {
        let decision = RoutineScheduler.decide(
            schedule: tuesdayAndFriday,
            now: try date("2026-07-22 11:00"),
            lastRun: try date("2026-07-17 09:05"),
            machine: alwaysReady,
            autonomy: .balanced,
            calendar: calendar
        )
        XCTAssertEqual(decision, .run)
    }

    func testASlotAlreadyRunIsNotRunAgain() throws {
        let decision = RoutineScheduler.decide(
            schedule: tuesdayAndFriday,
            now: try date("2026-07-21 17:00"),
            lastRun: try date("2026-07-21 09:02"),
            machine: alwaysReady,
            autonomy: .aggressive,
            calendar: calendar
        )
        XCTAssertEqual(decision, .hold(reason: "already ran for this slot"))
    }

    func testNeverRunBeforeStillFiresOnTheFirstDueSlot() throws {
        let decision = RoutineScheduler.decide(
            schedule: tuesdayAndFriday,
            now: try date("2026-07-21 09:30"),
            lastRun: nil,
            machine: alwaysReady,
            autonomy: .balanced,
            calendar: calendar
        )
        XCTAssertEqual(decision, .run)
    }

    func testAnEmptyWeekdaySetNeverFires() throws {
        let schedule = RoutineSchedule(weekdays: [], hour: 9)
        XCTAssertNil(schedule.lastFiring(before: try date("2026-07-21 10:00"), calendar: calendar))
    }

    // MARK: - The autonomy gate

    /// Eco's documented promise — "only while plugged in and idle" — previously
    /// had no code behind it. These are that code.
    func testEcoRequiresBothPowerAndIdle() {
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: false, idleFor: 3600), autonomy: .eco),
            .hold(reason: "Eco runs only while plugged in")
        )
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: true, idleFor: 10), autonomy: .eco),
            .hold(reason: "Eco waits until the Mac has been idle for 5 minutes")
        )
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: true, idleFor: 600), autonomy: .eco),
            .run
        )
    }

    func testBalancedAcceptsEitherPowerOrIdle() {
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: true, idleFor: 0), autonomy: .balanced),
            .run
        )
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: false, idleFor: 600), autonomy: .balanced),
            .run
        )
        XCTAssertFalse(
            RoutineScheduler.gate(machine: MachineState(isOnPower: false, idleFor: 5), autonomy: .balanced).shouldRun
        )
    }

    func testAggressiveRunsRegardlessOfMachineState() {
        XCTAssertEqual(
            RoutineScheduler.gate(machine: MachineState(isOnPower: false, idleFor: 0), autonomy: .aggressive),
            .run
        )
    }

    // MARK: - Defaults

    func testRecommendedSchedulesPutIngestionBeforeImprovements() {
        let ingestion = RoutineSchedule.recommended(for: .dataIngestion)
        let improvement = RoutineSchedule.recommended(for: .systemImprovement)

        XCTAssertEqual(ingestion.weekdays, improvement.weekdays)
        XCTAssertLessThan(
            ingestion.hour, improvement.hour,
            "the janitor must work on data that already arrived, not race it"
        )
    }
}
