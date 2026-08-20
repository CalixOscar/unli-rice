import XCTest
@testable import UnliRiceCore

/// The regression this whole type exists for: a chosen notes folder that fails
/// to open used to fall through to the default corpus with no `else` branch, no
/// error, and no change to what the UI claimed. The app then wrote notes into a
/// store the user had never picked.
///
/// Bookmark resolution and security-scoped access are injected because neither
/// can be constructed in a unit test — what is being asserted is the decision
/// table, which is where the bug was.
final class CorpusLocationTests: XCTestCase {
    private let defaultURL = URL(fileURLWithPath: "/default/Unli Rice/events.jsonl")
    private let bookmark = Data([0x01, 0x02])
    private let chosen = URL(fileURLWithPath: "/Users/x/My Notes", isDirectory: true)

    private func resolve(
        environment: [String: String] = [:],
        folderBookmark: Data? = nil,
        folderPath: String? = nil,
        isSandboxed: Bool = false,
        resolveBookmark: @escaping (Data) -> URL? = { _ in nil },
        startAccess: @escaping (URL) -> Bool = { _ in true }
    ) -> CorpusLocation {
        CorpusLocation.resolve(
            environment: environment,
            folderBookmark: folderBookmark,
            folderPath: folderPath,
            isSandboxed: isSandboxed,
            defaultURL: defaultURL,
            resolveBookmark: resolveBookmark,
            startAccess: startAccess
        )
    }

    // MARK: - The healthy paths

    func testNoFolderChosenUsesTheDefaultAndSaysSo() {
        let location = resolve()
        XCTAssertEqual(location.url, defaultURL)
        XCTAssertEqual(location.source, .defaultLocation)
        XCTAssertFalse(location.didFallBack)
        XCTAssertTrue(location.isDefaultLocation)
    }

    func testAResolvableBookmarkOpensTheChosenFolder() {
        let location = resolve(
            folderBookmark: bookmark,
            folderPath: chosen.path,
            resolveBookmark: { _ in self.chosen }
        )
        XCTAssertEqual(location.url.path, "/Users/x/My Notes/events.jsonl")
        XCTAssertEqual(location.source, .chosenFolder(chosen))
        XCTAssertEqual(location.scopedFolder, chosen)
        XCTAssertFalse(location.isDefaultLocation)
    }

    func testEnvironmentOverrideOutranksAChosenFolder() {
        let location = resolve(
            environment: ["UNLIRICE_DATA_PATH": "/tmp/scratch.jsonl"],
            folderBookmark: bookmark,
            folderPath: chosen.path,
            resolveBookmark: { _ in self.chosen }
        )
        XCTAssertEqual(location.url.path, "/tmp/scratch.jsonl")
        XCTAssertEqual(location.source, .environmentOverride)
    }

    // MARK: - The failures that used to be silent

    func testAnUnresolvableBookmarkFallsBackButReportsTheFolderItLost() {
        let location = resolve(
            folderBookmark: bookmark,
            folderPath: chosen.path,
            resolveBookmark: { _ in nil }
        )
        XCTAssertEqual(location.url, defaultURL, "must still open something")
        XCTAssertTrue(location.didFallBack)
        XCTAssertEqual(location.source, .defaultAfterFolderFailed(.unresolvable(path: chosen.path)))
    }

    func testRefusedAccessIsDistinguishedFromAMissingFolder() {
        let location = resolve(
            folderBookmark: bookmark,
            folderPath: chosen.path,
            resolveBookmark: { _ in self.chosen },
            startAccess: { _ in false }
        )
        XCTAssertEqual(location.source, .defaultAfterFolderFailed(.accessRefused(path: chosen.path)))
        XCTAssertNil(location.scopedFolder, "no scope may be reported when access was refused")
    }

    /// The sandbox rule that was documented but never enforced for the data
    /// folder: a plain path is not authority without a bookmark.
    func testSandboxedBuildWillNotTrustAPlainPath() {
        let location = resolve(folderPath: chosen.path, isSandboxed: true)
        XCTAssertEqual(location.url, defaultURL)
        XCTAssertEqual(location.source, .defaultAfterFolderFailed(.noBookmark(path: chosen.path)))
    }

    /// ...but an unsandboxed source build still honours one, which is
    /// long-standing behaviour for the CLI and MCP server.
    func testUnsandboxedBuildStillHonoursAPlainPath() {
        let location = resolve(folderPath: chosen.path, isSandboxed: false)
        XCTAssertEqual(location.url.path, "/Users/x/My Notes/events.jsonl")
        XCTAssertEqual(location.source, .chosenFolder(chosen))
    }

    /// The divergence that split the GUI from the MCP server: given identical
    /// settings, every executable must land on the same file.
    func testSandboxedAndUnsandboxedAgreeWheneverABookmarkResolves() {
        let sandboxed = resolve(
            folderBookmark: bookmark, folderPath: chosen.path,
            isSandboxed: true, resolveBookmark: { _ in self.chosen }
        )
        let unsandboxed = resolve(
            folderBookmark: bookmark, folderPath: chosen.path,
            isSandboxed: false, resolveBookmark: { _ in self.chosen }
        )
        XCTAssertEqual(sandboxed.url, unsandboxed.url)
        XCTAssertEqual(sandboxed.source, unsandboxed.source)
    }

    func testEmptyPathIsIgnoredRatherThanResolvingToTheFilesystemRoot() {
        let location = resolve(folderPath: "")
        XCTAssertEqual(location.url, defaultURL)
        XCTAssertEqual(location.source, .defaultLocation)
    }

    /// `usingDefaultDataFolder` used to read the saved preference, so during a
    /// fallback it reported "custom folder" while the default corpus was open.
    func testAFallbackReportsItselfAsTheDefaultLocation() {
        let location = resolve(
            folderBookmark: bookmark, folderPath: chosen.path,
            resolveBookmark: { _ in nil }
        )
        XCTAssertTrue(
            location.isDefaultLocation,
            "a fallback is on the default corpus and must not claim otherwise"
        )
    }
}
