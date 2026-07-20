import Foundation

/// The two routines the system runs on its own.
///
/// There is no third for "human review". The video this is modelled on lists
/// reviewing the proposals as routine 3, but a routine is something this app
/// makes happen, and it cannot make a person look at a queue. Naming it here
/// would only produce a scheduler entry that either does nothing or nags.
public enum RoutineKind: String, Sendable, CaseIterable, Codable {
    /// Fill the lake: run the importers.
    case dataIngestion
    /// Work the lake: run the janitor over what arrived, producing tags it can
    /// apply itself and flags only a human can resolve.
    case systemImprovement

    public var displayName: String {
        switch self {
        case .dataIngestion: return "Data ingestion"
        case .systemImprovement: return "System improvements"
        }
    }
}

/// When a routine wants to run. Wall-clock, in the user's own calendar.
public struct RoutineSchedule: Sendable, Equatable, Codable {
    /// `Calendar` weekday numbers — 1 is Sunday.
    public var weekdays: Set<Int>
    public var hour: Int
    public var minute: Int

    public init(weekdays: Set<Int>, hour: Int, minute: Int = 0) {
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
    }

    /// Tuesday and Friday, 09:00 — ingestion — and 13:00 for improvements, so
    /// the janitor is always working on data that arrived that morning rather
    /// than racing it.
    public static func recommended(for kind: RoutineKind) -> RoutineSchedule {
        // 3 = Tuesday, 6 = Friday.
        switch kind {
        case .dataIngestion: return RoutineSchedule(weekdays: [3, 6], hour: 9)
        case .systemImprovement: return RoutineSchedule(weekdays: [3, 6], hour: 13)
        }
    }

    /// The most recent moment this schedule called for, at or before `now`.
    ///
    /// Returns nil if it never fired within `lookbackDays`. Looking backwards
    /// rather than forwards is what makes a missed run recoverable: a Mac asleep
    /// at 09:00 on Tuesday still sees Tuesday 09:00 as the last due firing when
    /// it wakes on Wednesday, and catches up. A forward-only timer would silently
    /// skip it, and a pipeline that quietly stops is worse than one that never
    /// started — the corpus goes stale while still looking maintained.
    public func lastFiring(before now: Date, calendar: Calendar = .current, lookbackDays: Int = 14) -> Date? {
        guard !weekdays.isEmpty else { return nil }
        for dayOffset in 0...lookbackDays {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now),
                  weekdays.contains(calendar.component(.weekday, from: day)),
                  let firing = calendar.date(
                      bySettingHour: hour, minute: minute, second: 0, of: day, matchingPolicy: .nextTime
                  ),
                  firing <= now
            else { continue }
            return firing
        }
        return nil
    }
}

/// What the machine is doing right now. Supplied by the caller because
/// `UnliRiceCore` takes no dependency it doesn't need — reading the power source
/// means IOKit, which belongs at the edge, in the GUI target, not in the layer
/// the MCP server and the whole test suite link.
public struct MachineState: Sendable, Equatable {
    public var isOnPower: Bool
    public var idleFor: TimeInterval

    public init(isOnPower: Bool, idleFor: TimeInterval) {
        self.isOnPower = isOnPower
        self.idleFor = idleFor
    }
}

public enum RoutineDecision: Sendable, Equatable {
    case run
    /// Not now. `reason` is shown in the UI, so it says what the machine would
    /// have to do rather than just "skipped" — a routine that silently declines
    /// looks identical to one that's broken.
    case hold(reason: String)

    public var shouldRun: Bool { self == .run }
}

/// Decides whether a routine may run, as a pure function.
///
/// Pure on purpose, and for the same reason `Janitor.scan` is: a scheduler that
/// held a `NoteService` could quietly grow the ability to write, and the one
/// thing that must stay true of unattended execution is that the decision to run
/// and the act of running are separate. This answers only "may it"; the caller
/// owns "then do it".
///
/// This closes the half of deferred item #5 in PROJECT_NOTES.md that the MLX
/// work left open — the janitor previously ran from a button and nothing else,
/// and Eco's documented promise of "only while plugged in and idle" had no code
/// behind it. `gate(for:)` is that code.
public enum RoutineScheduler {
    /// How long the machine must be untouched before Eco and Balanced consider
    /// it idle. Short enough that a coffee break is enough; long enough that a
    /// pause mid-sentence isn't.
    public static let ecoIdleThreshold: TimeInterval = 5 * 60
    public static let balancedIdleThreshold: TimeInterval = 2 * 60

    public static func decide(
        schedule: RoutineSchedule,
        now: Date = Date(),
        lastRun: Date?,
        machine: MachineState,
        autonomy: JanitorAutonomy,
        calendar: Calendar = .current
    ) -> RoutineDecision {
        guard let firing = schedule.lastFiring(before: now, calendar: calendar) else {
            return .hold(reason: "not scheduled to run yet")
        }
        if let lastRun, lastRun >= firing {
            return .hold(reason: "already ran for this slot")
        }
        return gate(machine: machine, autonomy: autonomy)
    }

    /// The autonomy slider's promise about *when* work happens, as opposed to
    /// how much of it happens.
    ///
    /// Note what is not here: no level grants the routine any power the manual
    /// button doesn't already have. Aggressive runs sooner, never wider — the
    /// janitor's permission boundary is enforced in `JanitorRunner` and is not
    /// something a scheduler can widen. Same for ingest.
    public static func gate(machine: MachineState, autonomy: JanitorAutonomy) -> RoutineDecision {
        switch autonomy {
        case .eco:
            // The literal promise the slider makes at this level.
            guard machine.isOnPower else { return .hold(reason: "Eco runs only while plugged in") }
            guard machine.idleFor >= ecoIdleThreshold else {
                return .hold(reason: "Eco waits until the Mac has been idle for 5 minutes")
            }
            return .run

        case .balanced:
            // Either condition is enough: plugged in means the cost is power the
            // user isn't paying for, idle means it's attention they aren't.
            guard machine.isOnPower || machine.idleFor >= balancedIdleThreshold else {
                return .hold(reason: "waiting for the Mac to be plugged in or idle")
            }
            return .run

        case .aggressive:
            return .run
        }
    }
}
