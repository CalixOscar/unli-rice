import XCTest
@testable import UnliRiceCore

/// Fixtures are hand-built `.git` directories rather than real clones, so the tests
/// assert against git's on-disk *format* — which is what the scanner actually parses —
/// and run with no git binary present. That matters: the whole reason this type exists
/// is that the sandbox forbids shelling out, so a test suite that needed `git` would be
/// testing something the shipped app can never do.
final class GitRepoScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gitscan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Builders

    @discardableResult
    private func makeRepo(_ name: String) throws -> URL {
        let repo = root.appendingPathComponent(name)
        for sub in ["refs/heads", "refs/remotes", "worktrees"] {
            try FileManager.default.createDirectory(
                at: repo.appendingPathComponent(".git/\(sub)"), withIntermediateDirectories: true)
        }
        try write("ref: refs/heads/main\n", to: repo.appendingPathComponent(".git/HEAD"))
        return repo
    }

    private func write(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    private func sha(_ seed: String) -> String {
        String(seed.utf8.map { String(format: "%02x", $0) }.joined().prefix(40))
            .padding(toLength: 40, withPad: "0", startingAt: 0)
    }

    // MARK: - Refs

    func testReadsLooseBranchesIncludingSlashedNames() throws {
        let repo = try makeRepo("alpha")
        let a = sha("aa"), b = sha("bb")
        try write(a + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))
        try write(b + "\n", to: repo.appendingPathComponent(".git/refs/heads/feature/deep/name"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)

        XCTAssertEqual(snap.branches.map(\.name), ["feature/deep/name", "main"])
        XCTAssertEqual(snap.branches.first { $0.name == "main" }?.sha, a)
        XCTAssertEqual(snap.currentBranch, "main")
        XCTAssertFalse(snap.detachedHead)
    }

    /// The failure this guards: an established repo keeps most refs in `packed-refs`,
    /// so reading only `refs/` reports a nearly empty repository.
    func testReadsPackedRefsAndPrefersLooseWhenBothExist() throws {
        let repo = try makeRepo("beta")
        let stale = sha("old"), fresh = sha("new"), remote = sha("rr")
        try write("""
        # pack-refs with: peeled fully-peeled sorted
        \(stale) refs/heads/main
        \(sha("pk")) refs/heads/packed-only
        \(remote) refs/remotes/origin/main
        ^\(sha("peeled"))
        """, to: repo.appendingPathComponent(".git/packed-refs"))
        // A loose ref for the same branch is newer and must win.
        try write(fresh + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)

        XCTAssertEqual(snap.branches.map(\.name), ["main", "packed-only"])
        XCTAssertEqual(snap.branches.first { $0.name == "main" }?.sha, fresh,
                       "loose ref must win over the packed one")
        XCTAssertEqual(snap.remoteBranchCount, 1)
    }

    func testSymrefsAndPeeledLinesAreNotBranches() throws {
        let repo = try makeRepo("gamma")
        try write(sha("m") + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))
        // origin/HEAD is a symref, not a commit — it must not become a remote branch.
        try write("ref: refs/remotes/origin/main\n",
                  to: repo.appendingPathComponent(".git/refs/remotes/origin/HEAD"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)
        XCTAssertEqual(snap.remoteBranchCount, 0)
    }

    // MARK: - The question the scanner exists to answer

    func testTipOnRemoteIsTrueOnlyWhenSomeRemoteRefMatchesExactly() throws {
        let repo = try makeRepo("delta")
        let pushed = sha("p"), local = sha("l")
        try write(pushed + "\n", to: repo.appendingPathComponent(".git/refs/heads/shipped"))
        try write(local + "\n", to: repo.appendingPathComponent(".git/refs/heads/scratch"))
        try write(pushed + "\n", to: repo.appendingPathComponent(".git/refs/remotes/origin/shipped"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)

        XCTAssertTrue(snap.branches.first { $0.name == "shipped" }?.tipOnRemote == true)
        XCTAssertFalse(snap.branches.first { $0.name == "scratch" }?.tipOnRemote == true)
        XCTAssertEqual(snap.branchesNotOnAnyRemote.map(\.name), ["scratch"])
    }

    /// A tip pushed under a *differently named* remote branch still counts as backed
    /// up. This is the real Unli Rice case: `feature/languages-and-append` is 22 ahead
    /// of origin/main, but 16 of those commits sit on origin/feature/folder-first.
    func testTipMatchesRemoteUnderAnyName() throws {
        let repo = try makeRepo("epsilon")
        let tip = sha("t")
        try write(tip + "\n", to: repo.appendingPathComponent(".git/refs/heads/local-name"))
        try write(tip + "\n", to: repo.appendingPathComponent(".git/refs/remotes/origin/other-name"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)
        XCTAssertTrue(snap.branches[0].tipOnRemote)
    }

    // MARK: - HEAD

    func testDetachedHeadReportsNoBranch() throws {
        let repo = try makeRepo("zeta")
        try write(sha("d") + "\n", to: repo.appendingPathComponent(".git/HEAD"))
        try write(sha("m") + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)
        XCTAssertNil(snap.currentBranch)
        XCTAssertTrue(snap.detachedHead)
        XCTAssertFalse(snap.branches.contains { $0.isCurrent })
    }

    // MARK: - Worktrees

    func testWorktreeIsListedAndMissingOneIsFlagged() throws {
        let repo = try makeRepo("eta")
        try write(sha("m") + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))

        let live = root.appendingPathComponent("eta-live")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        try write("\(live.path)/.git\n",
                  to: repo.appendingPathComponent(".git/worktrees/live/gitdir"))
        try write("ref: refs/heads/side\n",
                  to: repo.appendingPathComponent(".git/worktrees/live/HEAD"))

        try write("\(root.path)/eta-gone/.git\n",
                  to: repo.appendingPathComponent(".git/worktrees/gone/gitdir"))
        try write("ref: refs/heads/dead\n",
                  to: repo.appendingPathComponent(".git/worktrees/gone/HEAD"))

        let snap = try GitRepoScanner().scan(repositoryAt: repo)

        XCTAssertEqual(snap.worktrees.map(\.name), ["gone", "live"])
        XCTAssertEqual(snap.worktrees.first { $0.name == "live" }?.branch, "side")
        XCTAssertFalse(snap.worktrees.first { $0.name == "live" }?.missing == true)
        XCTAssertTrue(snap.worktrees.first { $0.name == "gone" }?.missing == true)
    }

    /// Scanning a linked worktree must resolve `commondir` and report the parent's
    /// branches. Without it a worktree looks like an empty repository.
    func testScanningALinkedWorktreeResolvesTheCommonDir() throws {
        let repo = try makeRepo("theta")
        try write(sha("m") + "\n", to: repo.appendingPathComponent(".git/refs/heads/main"))
        try write(sha("s") + "\n", to: repo.appendingPathComponent(".git/refs/heads/side"))

        let wt = root.appendingPathComponent("theta-wt")
        try FileManager.default.createDirectory(at: wt, withIntermediateDirectories: true)
        let wtGitDir = repo.appendingPathComponent(".git/worktrees/theta-wt")
        try write("gitdir: \(wtGitDir.path)\n", to: wt.appendingPathComponent(".git"))
        try write("ref: refs/heads/side\n", to: wtGitDir.appendingPathComponent("HEAD"))
        try write("\(repo.path)/.git\n", to: wtGitDir.appendingPathComponent("commondir"))

        let snap = try GitRepoScanner().scan(repositoryAt: wt)

        XCTAssertEqual(snap.branches.map(\.name), ["main", "side"])
        XCTAssertEqual(snap.currentBranch, "side")
    }

    // MARK: - Not a repository

    func testPlainDirectoryThrowsAndScanAllSkipsIt() throws {
        let plain = root.appendingPathComponent("just-a-folder")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        XCTAssertThrowsError(try GitRepoScanner().scan(repositoryAt: plain)) { err in
            XCTAssertEqual(err as? GitRepoScanner.ScanError, .notARepository(plain.path))
        }

        try makeRepo("real")
        let all = GitRepoScanner().scanAll(in: root)
        XCTAssertEqual(all.map(\.name), ["real"], "non-repositories are skipped, not errors")
    }
}

/// Fixtures prove the format parsing; this proves it against a repository git itself
/// wrote. Skips unless `UNLIRICE_TEST_REPO` names one, so it never fails in CI or on a
/// fresh clone — a test that depends on one machine's checkout is worse than no test.
///
///   UNLIRICE_TEST_REPO="$PWD" swift test --filter RealRepository
final class GitRepoScannerRealRepositoryTests: XCTestCase {

    func testScansARepositoryGitActuallyWrote() throws {
        guard let path = ProcessInfo.processInfo.environment["UNLIRICE_TEST_REPO"] else {
            throw XCTSkip("set UNLIRICE_TEST_REPO to a real checkout to run this")
        }
        let snap = try GitRepoScanner().scan(repositoryAt: URL(fileURLWithPath: path))

        XCTAssertFalse(snap.branches.isEmpty, "a real repo has branches")

        // The regression this test exists for. Loose refs live inside `.git`, a hidden
        // directory; an enumerator using `.skipsHiddenFiles` yields nothing on a real
        // volume while working fine in a temp-dir fixture. That shipped as "13 branches"
        // where git says 21, with the 9 missing ones silently falling back to their
        // stale packed-refs SHAs. Count the files and demand the scanner match.
        let headsDir = URL(fileURLWithPath: path).appendingPathComponent(".git/refs/heads")
        var looseOnDisk = 0
        if let e = FileManager.default.enumerator(at: headsDir,
                                                  includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let u as URL in e
            where (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                looseOnDisk += 1
            }
        }
        if looseOnDisk > 0 {
            XCTAssertGreaterThanOrEqual(
                snap.branches.count, looseOnDisk,
                "\(looseOnDisk) loose refs on disk but only \(snap.branches.count) branches found — "
                + "the loose-ref walk is dropping them")
        }
        XCTAssertTrue(snap.currentBranch != nil || snap.detachedHead)

        // Every name must be a plain ref name. This is the symlink-prefix bug that
        // turned `main` into `/privatemain` — it only shows up on real paths.
        for b in snap.branches {
            XCTAssertFalse(b.name.hasPrefix("/"), "corrupted branch name: \(b.name)")
            XCTAssertEqual(b.sha.count, 40, "bad sha for \(b.name): \(b.sha)")
        }
        for w in snap.worktrees {
            XCTAssertTrue(w.path.hasPrefix("/"), "worktree path should be absolute: \(w.path)")
        }

        print("""

        —— \(snap.name) ——
        current:   \(snap.currentBranch ?? (snap.detachedHead ? "(detached)" : "?"))
        branches:  \(snap.branches.count)   remote refs: \(snap.remoteBranchCount)
        worktrees: \(snap.worktrees.count)
        tips on no remote (\(snap.branchesNotOnAnyRemote.count)):
        \(snap.branchesNotOnAnyRemote.map { "  · " + $0.name }.joined(separator: "\n"))
        worktrees:
        \(snap.worktrees.map { "  · \($0.name) [\($0.branch ?? "detached")]\($0.missing ? "  MISSING" : "")" }.joined(separator: "\n"))

        """)
    }
}

/// The trunk. Before 2026-09-02 the graph drew `main` as one lane among many, with the
/// vertical line representing nothing — so a branch sitting exactly on main's tip
/// (`feature/design-system`) was rendered as a fork that does not exist.
final class GitRepoScannerTrunkTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("trunk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func write(_ s: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: url, atomically: true, encoding: .utf8)
    }
    private func sha(_ c: String) -> String { String(repeating: c, count: 40) }

    private func repo(_ name: String) throws -> URL {
        let r = root.appendingPathComponent(name)
        try write("ref: refs/heads/main\n", to: r.appendingPathComponent(".git/HEAD"))
        return r
    }

    func testOriginHEADNamesTheTrunk() throws {
        let r = try repo("a")
        try write(sha("a") + "\n", to: r.appendingPathComponent(".git/refs/heads/main"))
        try write(sha("b") + "\n", to: r.appendingPathComponent(".git/refs/heads/trunk"))
        try write("ref: refs/remotes/origin/trunk\n",
                  to: r.appendingPathComponent(".git/refs/remotes/origin/HEAD"))

        XCTAssertEqual(try GitRepoScanner().scan(repositoryAt: r).defaultBranch, "trunk",
                       "origin/HEAD is authoritative, even when a branch called main exists")
    }

    func testFallsBackToMainThenMaster() throws {
        let r = try repo("b")
        try write(sha("a") + "\n", to: r.appendingPathComponent(".git/refs/heads/main"))
        XCTAssertEqual(try GitRepoScanner().scan(repositoryAt: r).defaultBranch, "main")

        let r2 = try repo("c")
        try write("ref: refs/heads/master\n", to: r2.appendingPathComponent(".git/HEAD"))
        try write(sha("a") + "\n", to: r2.appendingPathComponent(".git/refs/heads/master"))
        XCTAssertEqual(try GitRepoScanner().scan(repositoryAt: r2).defaultBranch, "master")
    }

    /// An origin/HEAD pointing at a branch we do not have locally must not be returned —
    /// the graph would then have a trunk it cannot draw.
    func testUnresolvableOriginHEADIsIgnored() throws {
        let r = try repo("d")
        try write(sha("a") + "\n", to: r.appendingPathComponent(".git/refs/heads/main"))
        try write("ref: refs/remotes/origin/gone\n",
                  to: r.appendingPathComponent(".git/refs/remotes/origin/HEAD"))
        XCTAssertEqual(try GitRepoScanner().scan(repositoryAt: r).defaultBranch, "main")
    }

    func testNoTrunkWhenNothingMatches() throws {
        let r = try repo("e")
        try write("ref: refs/heads/wip\n", to: r.appendingPathComponent(".git/HEAD"))
        try write(sha("a") + "\n", to: r.appendingPathComponent(".git/refs/heads/wip"))
        XCTAssertNil(try GitRepoScanner().scan(repositoryAt: r).defaultBranch)
    }
}
