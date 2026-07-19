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
    func testEventLogFilenameInsideAChosenFolder() {
        let url = DataLocation.eventLogURL(inFolder: URL(fileURLWithPath: "/Users/x/Vault"))
        XCTAssertEqual(url.lastPathComponent, "events.jsonl")
    }
}
