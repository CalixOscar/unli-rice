import Darwin
import Foundation

/// What has already been done for this corpus, shared by every process that
/// might do it.
///
/// This used to be a `UserDefaults` dictionary owned by the GUI, which was fine
/// while the GUI was the only thing that could run a routine. It isn't any more:
/// `unlirice-agent` runs the same routines with the window closed. Two
/// independent processes each remembering their own "last run" would serve the
/// same 09:00 slot twice — ingesting twice, scanning twice — and the second run
/// would look, from the outside, exactly like the pipeline working.
///
/// Corpus-scoped, so it sits beside the event log: "ingest last ran on Tuesday"
/// is a fact about a vault, not about the app, and pointing the app at a
/// different vault must not inherit it.
public struct RoutineState: Codable, Equatable, Sendable {
    /// Keyed by `RoutineKind.rawValue`.
    public var lastRuns: [String: Date]

    /// The last period a review digest notice was posted for, as `yyyy-MM`.
    /// Stops the same month being announced twice, including across a restart.
    public var lastDigestPeriod: String?

    public init(lastRuns: [String: Date] = [:], lastDigestPeriod: String? = nil) {
        self.lastRuns = lastRuns
        self.lastDigestPeriod = lastDigestPeriod
    }

    public func lastRun(of kind: RoutineKind) -> Date? {
        lastRuns[kind.rawValue]
    }

    public mutating func recordRun(of kind: RoutineKind, at date: Date = Date()) {
        lastRuns[kind.rawValue] = date
    }

    // MARK: - Persistence

    public static func url(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent("routine-state.json")
    }

    /// Missing or malformed reads as "nothing has run yet".
    ///
    /// That default is the safe one in this direction — the worst case is one
    /// redundant scan, whereas defaulting to "everything already ran" would
    /// silently stop the pipeline while it still looked maintained, which is the
    /// failure `RoutineSchedule.lastFiring` exists to prevent.
    public static func load(from url: URL) -> RoutineState {
        guard let data = try? Data(contentsOf: url) else { return RoutineState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(RoutineState.self, from: data)) ?? RoutineState()
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

/// A whole-machine "someone is already doing this" lock, held for as long as the
/// object lives.
///
/// The state file above stops a *second* run being scheduled; this stops two
/// runs happening at the *same moment* — the GUI's 5-minute heartbeat and the
/// agent's launchd interval can genuinely land together, and both would read the
/// same "not yet run" state before either wrote it. `flock` is the same
/// primitive `EventStore.append` already relies on to keep concurrent MCP
/// clients from interleaving writes.
///
/// Advisory and best-effort by design: failing to acquire means "skip this
/// tick", never "error". A tick that skips is served by the next one, because
/// the scheduler looks backwards for unserved slots.
public final class RoutineRunLock {
    private let descriptor: Int32

    /// Returns nil if another process holds the lock.
    public init?(besideEventLog eventLog: URL) {
        let url = eventLog.deletingLastPathComponent().appendingPathComponent("routine.lock")
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let fd = open(url.path, O_WRONLY | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return nil
        }
        descriptor = fd
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
