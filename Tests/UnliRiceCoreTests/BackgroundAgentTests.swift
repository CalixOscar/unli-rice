import XCTest
@testable import UnliRiceCore
@testable import UnliRiceHost

/// The pieces that let the routines run with the window closed.
///
/// Nothing here installs anything on the machine running the test —
/// `BackgroundAgent.plist` is a pure function precisely so this can assert what
/// launchd would be told without telling it.
final class BackgroundAgentTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-agent-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Settings

    func testSettingsRoundTrip() throws {
        let settings = AgentSettings(
            routinesEnabled: true,
            autonomyLevel: 2,
            dataFolderPath: "/tmp/vault",
            scanRootPaths: ["/tmp/docs"],
            monthlyReviewEnabled: false
        )
        let url = directory.appendingPathComponent("agent.json")
        try settings.save(to: url)

        XCTAssertEqual(AgentSettings.load(from: url), settings)
        XCTAssertEqual(AgentSettings.load(from: url).autonomy, .aggressive)
    }

    /// The safe direction to fail in: an unreadable settings file must leave the
    /// agent doing nothing, not doing work nobody asked for.
    func testMissingOrCorruptSettingsMeanRoutinesAreOff() throws {
        let missing = directory.appendingPathComponent("nope.json")
        XCTAssertFalse(AgentSettings.load(from: missing).routinesEnabled)

        let corrupt = directory.appendingPathComponent("corrupt.json")
        try "not json at all".write(to: corrupt, atomically: true, encoding: .utf8)
        XCTAssertFalse(AgentSettings.load(from: corrupt).routinesEnabled)
    }

    // MARK: - Routine state

    func testRoutineStateRoundTripsAndDefaultsToNothingHavingRun() throws {
        let url = directory.appendingPathComponent("routine-state.json")
        XCTAssertNil(RoutineState.load(from: url).lastRun(of: .dataIngestion))

        var state = RoutineState()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        state.recordRun(of: .dataIngestion, at: when)
        state.lastDigestPeriod = "2026-06"
        try state.save(to: url)

        let reloaded = RoutineState.load(from: url)
        XCTAssertEqual(reloaded.lastRun(of: .dataIngestion), when)
        XCTAssertNil(reloaded.lastRun(of: .systemImprovement))
        XCTAssertEqual(reloaded.lastDigestPeriod, "2026-06")
    }

    /// The GUI heartbeat and launchd's interval genuinely do land together. The
    /// second one must decline rather than run the same slot again.
    func testOnlyOneProcessCanHoldTheRoutineLock() throws {
        let eventLog = directory.appendingPathComponent("events.jsonl")
        let first = RoutineRunLock(besideEventLog: eventLog)
        XCTAssertNotNil(first)
        XCTAssertNil(RoutineRunLock(besideEventLog: eventLog))
    }

    // MARK: - The launchd job

    func testPlistNamesTheAgentBinaryAndRunsOnAnInterval() {
        let binary = URL(fileURLWithPath: "/Applications/Unli Rice.app/Contents/MacOS/unlirice-agent")
        let plist = BackgroundAgent.plist(binary: binary, logDirectory: directory)
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [binary.path])

        XCTAssertEqual(plist["Label"] as? String, "com.unlirice.agent")
        XCTAssertEqual(plist["StartInterval"] as? Int, 300)
        // Catches up a slot missed while the Mac was off, rather than waiting
        // out a full interval first.
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    }

    func testPlistIsAValidPropertyList() throws {
        let plist = BackgroundAgent.plist(
            binary: URL(fileURLWithPath: "/bin/echo"), logDirectory: directory
        )
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(parsed?["Label"] as? String, "com.unlirice.agent")
    }

    /// A launchd job pointing at a path that doesn't exist installs perfectly
    /// happily and then does nothing forever — the exact silent failure the
    /// background agent exists to remove. So "not found" has to be a nil, not a
    /// plausible-looking guess.
    func testLocatingTheBinaryRefusesToGuess() throws {
        let fake = directory.appendingPathComponent("UnliRice")
        FileManager.default.createFile(atPath: fake.path, contents: Data())
        XCTAssertNil(BackgroundAgent.locateBinary(near: fake))

        let agent = directory.appendingPathComponent("unlirice-agent")
        FileManager.default.createFile(atPath: agent.path, contents: Data(), attributes: [.posixPermissions: 0o755])
        XCTAssertEqual(BackgroundAgent.locateBinary(near: fake), agent)
    }

    func testPlistPathIsInTheUsersLaunchAgentsFolder() {
        let home = URL(fileURLWithPath: "/Users/someone")
        XCTAssertEqual(
            BackgroundAgent.plistURL(home: home).path,
            "/Users/someone/Library/LaunchAgents/com.unlirice.agent.plist"
        )
        XCTAssertFalse(BackgroundAgent.isInstalled(home: directory))
    }
}
