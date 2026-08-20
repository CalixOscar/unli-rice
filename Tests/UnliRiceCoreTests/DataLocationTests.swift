import XCTest
@testable import UnliRiceCore

/// The path-precedence rule behind "point Unli Rice at my existing folder."
///
/// Tested as a pure function rather than through `AppStore` so it can be
/// asserted without touching real `UserDefaults`, the real environment, or the
/// user's actual event log.
final class DataLocationTests: XCTestCase {
    private let fallback = URL(fileURLWithPath: "/default/Unli Rice/events.jsonl")

    func testDefaultWinsWhenNothingIsSet() {
        let url = DataLocation.resolvedEventLogURL(
            environment: [:], persistedFolderPath: nil, defaultURL: fallback
        )
        XCTAssertEqual(url, fallback)
    }

    func testPersistedFolderIsUsedWhenSet() {
        let url = DataLocation.resolvedEventLogURL(
            environment: [:], persistedFolderPath: "/Users/x/Vault", defaultURL: fallback
        )
        XCTAssertEqual(url.path, "/Users/x/Vault/events.jsonl")
    }

    /// `UNLIRICE_DATA_PATH` has to outrank a persisted preference: it's what
    /// tests and smoke runs use to stay off real data, and a stale preference
    /// silently overriding it would let a test write into whatever vault the
    /// user last opened.
    func testEnvironmentOverrideBeatsAPersistedFolder() {
        let url = DataLocation.resolvedEventLogURL(
            environment: ["UNLIRICE_DATA_PATH": "/tmp/test-events.jsonl"],
            persistedFolderPath: "/Users/x/Vault",
            defaultURL: fallback
        )
        XCTAssertEqual(url.path, "/tmp/test-events.jsonl")
    }

    func testEmptyValuesAreIgnoredRatherThanResolvingToTheFilesystemRoot() {
        let url = DataLocation.resolvedEventLogURL(
            environment: ["UNLIRICE_DATA_PATH": ""],
            persistedFolderPath: "",
            defaultURL: fallback
        )
        XCTAssertEqual(url, fallback)
    }

    /// One place decides the filename, so the GUI and the MCP config block the
    /// wizard generates can't disagree about what to open inside a folder.
    // MARK: - Adopting a store from a previous default location

    /// The regression behind the 2026-07 fork: the default moved twice, and the
    /// second move only ever consulted the *pre-rename* predecessor. Both
    /// existed, so order alone handed a fresh App Group container the small
    /// pre-rename log and orphaned the corpus that was actually in use.
    func testAdoptsTheLargestPredecessorNotTheOldestOne() {
        let previousDefault = URL(fileURLWithPath: "/support/Unli Rice/events.jsonl")
        let preRename = URL(fileURLWithPath: "/support/SecondBrain/events.jsonl")
        let counts = [previousDefault: 724, preRename: 150]

        let chosen = DataLocation.storeToAdopt(
            from: [previousDefault, preRename],
            eventCount: { counts[$0] }
        )
        XCTAssertEqual(chosen, previousDefault)
    }

    /// Order must not decide it either way round.
    func testAdoptionIgnoresCandidateOrdering() {
        let big = URL(fileURLWithPath: "/support/Unli Rice/events.jsonl")
        let small = URL(fileURLWithPath: "/support/SecondBrain/events.jsonl")
        let counts = [big: 724, small: 150]

        XCTAssertEqual(
            DataLocation.storeToAdopt(from: [small, big], eventCount: { counts[$0] }),
            big
        )
    }

    func testAnEmptyOrUnreadableLogIsNeverAdopted() {
        let empty = URL(fileURLWithPath: "/support/Unli Rice/events.jsonl")
        let missing = URL(fileURLWithPath: "/support/SecondBrain/events.jsonl")
        let counts: [URL: Int] = [empty: 0]

        XCTAssertNil(
            DataLocation.storeToAdopt(from: [empty, missing], eventCount: { counts[$0] })
        )
    }

    func testNoCandidatesMeansNoAdoption() {
        XCTAssertNil(DataLocation.storeToAdopt(from: [], eventCount: { _ in nil }))
    }

    /// Both relocations this app has made must stay on the candidate list; if
    /// either is dropped, a machine that skipped a version loses its corpus.
    func testPredecessorListCoversBothRelocations() {
        let paths = DataLocation.predecessorEventLogURLs().map(\.path)
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.contains { $0.contains("/Unli Rice/events.jsonl") })
        XCTAssertTrue(paths.contains { $0.contains("/SecondBrain/events.jsonl") })
    }

    func testEventCountReadsARealLog() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("adopt-\(UUID().uuidString).jsonl")
        try #"{"a":1}"# .appending("\n{\"b\":2}\n").write(to: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertEqual(DataLocation.eventCount(atPath: tmp), 2)
        XCTAssertNil(DataLocation.eventCount(atPath: tmp.appendingPathExtension("nope")))
    }

    func testEventLogFilenameInsideAChosenFolder() {
        let url = DataLocation.eventLogURL(inFolder: URL(fileURLWithPath: "/Users/x/Vault"))
        XCTAssertEqual(url.lastPathComponent, "events.jsonl")
    }
}
