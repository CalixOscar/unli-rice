import XCTest
@testable import UnliRiceCore

final class StudioTodoTests: XCTestCase {

    private func branch(_ name: String, remote: Bool = true, ahead: Int? = nil,
                        shape: String? = nil) -> RepoSnapshotFile.Branch {
        .init(name: name, sha: String(repeating: "a", count: 40),
              tipOnRemote: remote, isCurrent: false,
              aheadOfTrunk: ahead, shape: shape)
    }

    private func snapshot(_ repos: [RepoSnapshotFile.Repo]) -> RepoSnapshotFile {
        .init(deviceLabel: "test", repos: repos)
    }

    private func repo(_ name: String, _ branches: [RepoSnapshotFile.Branch]) -> RepoSnapshotFile.Repo {
        .init(name: name, currentBranch: "main", detachedHead: false,
              branches: branches, remoteBranchCount: 1, worktrees: [], trunk: "main")
    }

    // MARK: - What makes an item

    func testTipsOnNoRemoteAreTheTopPriority() {
        let t = StudioTodo.derive(from: snapshot([
            repo("Nuptia", [branch("main"), branch("wip", remote: false)])
        ]))
        XCTAssertEqual(t.atRisk.count, 1)
        XCTAssertEqual(t.items.first?.kind, .atRisk)
        XCTAssertTrue(t.items[0].title.contains("1 branch tip"))
        XCTAssertNotNil(t.items[0].fix, "an at-risk item should name the command that fixes it")
    }

    /// A worktree's commits live in the shared object store and are safe. Its
    /// uncommitted files are in that folder and nowhere else, which is the risk.
    func testUncommittedWorktreeFilesCountAsAtRisk() {
        let t = StudioTodo.derive(from: snapshot([repo("X", [branch("main")])]),
                                  worktreeDirt: ["X": 12])
        XCTAssertEqual(t.atRisk.count, 1)
        XCTAssertTrue(t.items[0].title.contains("12 uncommitted"))
        XCTAssertNil(t.items[0].fix, "there is no safe one-liner for this — it needs a look")
    }

    func testDeclaredNextStepBecomesAnItemAttributedToItsSource() {
        let t = StudioTodo.derive(from: snapshot([repo("X", [branch("main")])]),
                                  nextSteps: ["X": "Push the backlog, then compact the notes"])
        XCTAssertEqual(t.items.count, 1)
        XCTAssertEqual(t.items[0].kind, .declared)
        XCTAssertEqual(t.items[0].title, "Push the backlog, then compact the notes")
        XCTAssertTrue(t.items[0].evidence.contains("memory.md"))
    }

    func testBlankNextStepIsNotAnItem() {
        let t = StudioTodo.derive(from: snapshot([repo("X", [branch("main")])]),
                                  nextSteps: ["X": "   \n  "])
        XCTAssertTrue(t.items.isEmpty, "an empty field is not a task")
    }

    /// Clutter only once there is enough of it to bury something. Two stale branches
    /// are not worth a line in a list whose job is to surface what matters.
    func testMergedBranchesOnlyCountAsClutterInBulk() {
        let few = (1...3).map { branch("b\($0)", ahead: 0, shape: "tick") }
        XCTAssertTrue(StudioTodo.derive(from: snapshot([repo("X", few + [branch("main")])]))
            .items.isEmpty)

        let many = (1...9).map { branch("b\($0)", ahead: 0, shape: "tick") }
        let t = StudioTodo.derive(from: snapshot([repo("X", many + [branch("main")])]))
        XCTAssertEqual(t.items.count, 1)
        XCTAssertEqual(t.items[0].kind, .clutter)
    }

    // MARK: - Ordering

    /// The ordering is the whole point: work that can be permanently lost has to sit
    /// above tidying, or the list buries its own most important line.
    func testAtRiskOutranksEverythingAndClutterSinks() {
        let many = (1...9).map { branch("m\($0)", ahead: 0, shape: "tick") }
        let t = StudioTodo.derive(
            from: snapshot([repo("X", many + [branch("main"),
                                              branch("lost", remote: false),
                                              branch("ahead", ahead: 3)])]),
            nextSteps: ["X": "do the thing"])

        XCTAssertEqual(t.items.map(\.kind), [.atRisk, .declared, .unshared, .clutter])
    }

    func testItemIDsAreStableAcrossDerivations() {
        let s = snapshot([repo("X", [branch("main"), branch("wip", remote: false)])])
        XCTAssertEqual(StudioTodo.derive(from: s).items.map(\.id),
                       StudioTodo.derive(from: s).items.map(\.id))
    }

    // MARK: - Reading memory.md

    func testNextStepIsPulledOutOfAMemoryFile() {
        let body = """
        **Status:** fine
        **Task:** something
        **Files touched:** a.swift
        **Next step:** Push the 6 unbacked commits,
        then compact PROJECT_NOTES.md
        **Gotchas:** none
        **Left by:** Claude 2026-09-02
        """
        XCTAssertEqual(StudioTodo.nextStep(fromMemory: body),
                       "Push the 6 unbacked commits, then compact PROJECT_NOTES.md",
                       "a multi-line next step must survive — the contract fixes field order, not length")
    }

    func testMissingOrEmptyNextStepReadsAsNil() {
        XCTAssertNil(StudioTodo.nextStep(fromMemory: "**Status:** fine\n**Task:** x"))
        XCTAssertNil(StudioTodo.nextStep(fromMemory: "**Next step:**\n**Gotchas:** none"))
    }
}

/// The phone has no access to the Mac's project folders, so a next step it cannot read
/// is one it cannot show. These cover the snapshot-carried fallback.
extension StudioTodoTests {

    func testSnapshotNextStepIsUsedWhenTheCallerHasNone() {
        let r = RepoSnapshotFile.Repo(
            name: "X", currentBranch: "main", detachedHead: false,
            branches: [.init(name: "main", sha: String(repeating: "a", count: 40),
                             tipOnRemote: true, isCurrent: true)],
            remoteBranchCount: 1, worktrees: [], trunk: "main",
            nextStep: "Push the backlog")

        let t = StudioTodo.derive(from: .init(deviceLabel: "t", repos: [r]))
        XCTAssertEqual(t.items.count, 1)
        XCTAssertEqual(t.items[0].title, "Push the backlog")
        XCTAssertTrue(t.items[0].evidence.contains("as of the last snapshot"),
                      "a phone should be told the step is a photograph, not live")
    }

    /// A live read beats the snapshot's copy, which is only as fresh as the last publish.
    func testALiveReadWinsOverTheSnapshotCopy() {
        let r = RepoSnapshotFile.Repo(
            name: "X", currentBranch: "main", detachedHead: false,
            branches: [.init(name: "main", sha: String(repeating: "a", count: 40),
                             tipOnRemote: true, isCurrent: true)],
            remoteBranchCount: 1, worktrees: [], trunk: "main",
            nextStep: "stale")

        let t = StudioTodo.derive(from: .init(deviceLabel: "t", repos: [r]),
                                  nextSteps: ["X": "fresh"])
        XCTAssertEqual(t.items[0].title, "fresh")
        XCTAssertFalse(t.items[0].evidence.contains("snapshot"))
    }
}

extension StudioTodoTests {
    /// The noun has to be pluralised too. "3 branch are ahead" shipped, the same slip
    /// as "3 branch tipes" — both from deriving one word form instead of writing both.
    func testAheadOfTrunkPluralisesTheNounAndTheVerb() {
        let one = StudioTodo.derive(from: snapshot([repo("X", [branch("a", ahead: 2)])]))
        XCTAssertTrue(one.items.contains { $0.title == "1 branch is ahead of main" },
                      one.items.map(\.title).description)

        let many = StudioTodo.derive(from: snapshot([
            repo("X", [branch("a", ahead: 2), branch("b", ahead: 3)])
        ]))
        XCTAssertTrue(many.items.contains { $0.title == "2 branches are ahead of main" },
                      many.items.map(\.title).description)
    }
}
