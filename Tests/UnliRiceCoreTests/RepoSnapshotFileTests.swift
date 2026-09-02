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

/// Decodes a snapshot written by the real `check-repos.sh --json`, not one this test
/// encoded itself. A Codable round-trip proves the model is self-consistent; it proves
/// nothing about whether a shell script and a Swift decoder agree on the same JSON —
/// which is the actual seam here, and the one that will break silently.
///
///   UNLIRICE_TEST_SNAPSHOT=/path/to/repos.json swift test --filter ProducedSnapshot
final class RepoSnapshotProducedSnapshotTests: XCTestCase {

    func testDecodesASnapshotWrittenByTheScript() throws {
        guard let path = ProcessInfo.processInfo.environment["UNLIRICE_TEST_SNAPSHOT"] else {
            throw XCTSkip("set UNLIRICE_TEST_SNAPSHOT to a check-repos.sh --json output")
        }
        let url = URL(fileURLWithPath: path)
        let file = try RepoSnapshotFile.read(fromFolder: url.deletingLastPathComponent())

        XCTAssertEqual(file.version, RepoSnapshotFile.currentVersion)
        XCTAssertFalse(file.repos.isEmpty)
        XCTAssertFalse(file.deviceLabel.isEmpty)

        for r in file.repos {
            XCTAssertFalse(r.branches.isEmpty, "\(r.name) decoded with no branches")
            for b in r.branches {
                XCTAssertEqual(b.sha.count, 40, "\(r.name)/\(b.name) has a bad sha")
                // A parent must name a branch that exists, or the graph draws an edge
                // to nowhere.
                if let p = b.parent {
                    XCTAssertTrue(r.branches.contains { $0.name == p },
                                  "\(r.name)/\(b.name) has parent '\(p)' which is not a branch")
                    XCTAssertNotEqual(p, b.name, "a branch cannot be its own parent")
                    XCTAssertNotNil(b.aheadOfParent)
                    XCTAssertGreaterThan(b.aheadOfParent ?? 0, 0,
                                         "parenting must be by STRICT ancestry; distance 0 is an alias")
                }
            }
            // No cycles: following parents must terminate.
            for b in r.branches {
                var seen: Set<String> = [b.name]
                var cur = b.parent
                var hops = 0
                while let c = cur, hops < 64 {
                    XCTAssertTrue(seen.insert(c).inserted, "cycle in \(r.name) at \(c)")
                    cur = r.branches.first { $0.name == c }?.parent
                    hops += 1
                }
                XCTAssertLessThan(hops, 64, "parent chain did not terminate in \(r.name)")
            }
        }
        print("\n—— decoded \(file.repos.count) repos, ancestry present in "
              + "\(file.repos.filter(\.hasAncestry).count) ——\n")
    }
}
