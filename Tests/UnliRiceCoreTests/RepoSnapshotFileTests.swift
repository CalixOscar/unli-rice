import XCTest
@testable import UnliRiceCore

final class RepoSnapshotFileTests: XCTestCase {

    private var folder: URL!

    override func setUpWithError() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("reposnap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sample(generatedAt: Date = Date()) -> RepoSnapshotFile {
        RepoSnapshotFile(
            generatedAt: generatedAt,
            deviceLabel: "Peter's Mac",
            repos: [
                .init(name: "Unli Rice",
                      currentBranch: "feature/languages-and-append",
                      detachedHead: false,
                      branches: [
                        .init(name: "main", sha: String(repeating: "a", count: 40),
                              tipOnRemote: true, isCurrent: false),
                        .init(name: "feature/byo-llm", sha: String(repeating: "b", count: 40),
                              tipOnRemote: false, isCurrent: true)
                      ],
                      remoteBranchCount: 6,
                      worktrees: [.init(name: "byollm", branch: "feature/byo-llm", missing: false)])
            ])
    }

    func testRoundTripsThroughTheSharedFolder() throws {
        let original = sample()
        try original.write(toFolder: folder)
        let read = try RepoSnapshotFile.read(fromFolder: folder)

        XCTAssertEqual(read.deviceLabel, "Peter's Mac")
        XCTAssertEqual(read.repos.count, 1)
        XCTAssertEqual(read.repos[0].branches.map(\.name), ["main", "feature/byo-llm"])
        XCTAssertEqual(read.repos[0].worktrees.first?.branch, "feature/byo-llm")
        XCTAssertEqual(read.totalBranchesNotOnAnyRemote, 1)
        // ISO8601 drops sub-second precision; equality to the second is what matters.
        XCTAssertEqual(read.generatedAt.timeIntervalSince1970,
                       original.generatedAt.timeIntervalSince1970, accuracy: 1.0)
    }

    func testMissingFileIsNamedNotGuessedAt() {
        XCTAssertThrowsError(try RepoSnapshotFile.read(fromFolder: folder)) {
            XCTAssertEqual($0 as? RepoSnapshotFile.ReadError, .missing)
        }
    }

    /// A truncated file must read as an error, never as "no repositories" — an empty
    /// dashboard that means "I could not read this" is the failure worth preventing.
    func testTruncatedFileIsUnreadableRatherThanEmpty() throws {
        try sample().write(toFolder: folder)
        let url = folder.appendingPathComponent(RepoSnapshotFile.filename)
        let data = try Data(contentsOf: url)
        try data.prefix(data.count / 2).write(to: url)

        XCTAssertThrowsError(try RepoSnapshotFile.read(fromFolder: folder)) {
            XCTAssertEqual($0 as? RepoSnapshotFile.ReadError, .unreadable)
        }
    }

    /// A phone on an older build must say so rather than decode a subset silently.
    func testNewerVersionIsRefusedByName() throws {
        let json = """
        {"version": 99, "generatedAt": "2026-09-02T00:00:00Z", "deviceLabel": "x", "repos": []}
        """
        try json.write(to: folder.appendingPathComponent(RepoSnapshotFile.filename),
                       atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try RepoSnapshotFile.read(fromFolder: folder)) {
            XCTAssertEqual($0 as? RepoSnapshotFile.ReadError, .unsupportedVersion(99))
        }
    }

    func testStalenessIsPartOfTheData() {
        XCTAssertFalse(sample(generatedAt: Date()).isStale())
        XCTAssertTrue(sample(generatedAt: Date().addingTimeInterval(-60 * 60 * 24)).isStale())
    }

    /// The snapshot must never carry a filesystem path. The phone cannot act on repos and
    /// should not be handed anything that looks like it could.
    func testSnapshotCarriesNoFilesystemPaths() throws {
        try sample().write(toFolder: folder)
        let raw = try String(contentsOf: folder.appendingPathComponent(RepoSnapshotFile.filename),
                             encoding: .utf8)
        XCTAssertFalse(raw.contains("/Users/"), "a snapshot must not leak local paths")
        XCTAssertFalse(raw.lowercased().contains("\"path\""))
    }
}
