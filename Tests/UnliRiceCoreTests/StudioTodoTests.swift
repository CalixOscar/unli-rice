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

    // MARK: - Regression & Coverage Tests (Plan §6 1-10)

    func testDeriveWithNoWorktreeDirtHasNoneCoverage() {
        let snap = snapshot([repo("X", [branch("main")])])
        let t = StudioTodo.derive(from: snap)
        XCTAssertEqual(t.coverage.dirt, .none)
    }

    func testDerivePartialWorktreeDirtCoverage() {
        let snap = snapshot([repo("X", [branch("main")]), repo("Y", [branch("main")])])
        let t = StudioTodo.derive(from: snap, worktreeDirt: ["X": 0])
        XCTAssertEqual(t.coverage.dirt, .partial(missing: ["Y"]))
    }

    func testStudioTodoUnread() {
        let unread = StudioTodo.unread()
        XCTAssertTrue(unread.items.isEmpty)
        XCTAssertFalse(unread.coverage.snapshotRead)
    }

    func testInitItemsDefaultsToUnknownCoverage() {
        let t = StudioTodo(items: [])
        XCTAssertEqual(t.coverage.dirt, .none)
        XCTAssertFalse(t.coverage.snapshotRead)
    }

    func testReadNoStepSuppressesSnapshotNextStepFallback() {
        let r = RepoSnapshotFile.Repo(
            name: "X", currentBranch: "main", detachedHead: false,
            branches: [branch("main")],
            remoteBranchCount: 1, worktrees: [], trunk: "main",
            nextStep: "snapshot step")

        let suppressed = StudioTodo.derive(from: snapshot([r]), nextSteps: ["X": .readNoStep])
        XCTAssertFalse(suppressed.items.contains { $0.title == "snapshot step" })

        let unreadFallback = StudioTodo.derive(from: snapshot([r]), nextSteps: ["X": .unreadable])
        XCTAssertTrue(unreadFallback.items.contains { $0.title == "snapshot step" })
    }

    func testReadNoStepCountsTowardCoverageNextSteps() {
        let r1 = repo("X", [branch("main")])
        let r2 = repo("Y", [branch("main")])
        let snap = snapshot([r1, r2])

        let partial = StudioTodo.derive(from: snap, nextSteps: ["X": .readNoStep, "Y": .unreadable])
        XCTAssertEqual(partial.coverage.nextSteps, .partial(missing: ["Y"]))

        let complete = StudioTodo.derive(from: snap, nextSteps: ["X": .readNoStep, "Y": .step("do this")])
        XCTAssertEqual(complete.coverage.nextSteps, .complete)
    }

    func testEmptyStateUnreadWhenSnapshotNotRead() {
        let cov = StudioTodo.Coverage(snapshotRead: false, repositories: [], dirt: .none, nextSteps: .none)
        let state = TodoEmptyState.for(coverage: cov)
        XCTAssertEqual(state, .unread)
        XCTAssertNotEqual(state, .nothingOutstanding)
    }

    func testEmptyStateEmptySnapshotWhenNoRepos() {
        let cov = StudioTodo.Coverage(snapshotRead: true, repositories: [], dirt: .none, nextSteps: .none)
        let state = TodoEmptyState.for(coverage: cov)
        XCTAssertEqual(state, .emptySnapshot)
    }

    func testEmptyStateQualifiedWhenPartialDirt() {
        let cov = StudioTodo.Coverage(
            snapshotRead: true,
            repositories: ["X", "Y"],
            dirt: .partial(missing: ["Y"]),
            nextSteps: .complete
        )
        let state = TodoEmptyState.for(coverage: cov)
        switch state {
        case .qualified(let msg):
            XCTAssertTrue(msg.contains("dirt not measured for 1 of 2 repositories"), msg)
        default:
            XCTFail("Expected .qualified, got \(state)")
        }
    }

    func testEmptyStateNothingOutstandingOnlyWhenComplete() {
        let complete = StudioTodo.Coverage(
            snapshotRead: true,
            repositories: ["X"],
            dirt: .complete,
            nextSteps: .complete
        )
        XCTAssertEqual(TodoEmptyState.for(coverage: complete), .nothingOutstanding)

        let incomplete = StudioTodo.Coverage(
            snapshotRead: true,
            repositories: ["X"],
            dirt: .none,
            nextSteps: .complete
        )
        XCTAssertNotEqual(TodoEmptyState.for(coverage: incomplete), .nothingOutstanding)
    }

    // MARK: - AI-Flagged To-Dos (§2.8)

    private func testNote(
        id: UUID = UUID(),
        title: String = "A task",
        tags: Set<String> = ["todo", "x"],
        creator: String = "claude",
        archived: Bool = false
    ) -> Note {
        Note(
            id: id,
            title: title,
            body: "context",
            tags: tags,
            sources: [creator],
            creator: creator,
            createdAt: Date(),
            updatedAt: Date(),
            archived: archived
        )
    }

    func testAIFlaggedNoteProducesItemWithRightNoteID() {
        let noteID = UUID()
        let n = testNote(id: noteID, title: "Bump marketing URL", tags: ["todo", "nuptia"], creator: "claude")
        let t = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            aiFlags: ["nuptia": [n]]
        )
        XCTAssertEqual(t.items.count, 1)
        XCTAssertEqual(t.items[0].kind, .aiFlagged)
        XCTAssertEqual(t.items[0].noteID, noteID)
        XCTAssertEqual(t.items[0].project, "Nuptia")
        XCTAssertEqual(t.items[0].title, "Bump marketing URL")
        XCTAssertTrue(t.items[0].evidence.contains("Flagged by claude"))
        XCTAssertNil(t.items[0].fix)
    }

    func testNoteWithTodoOnlyOrProjectOnlyProducesNothing() {
        let todoOnly = testNote(title: "Only todo", tags: ["todo"])
        let projOnly = testNote(title: "Only project", tags: ["nuptia"])
        let t1 = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            aiFlags: ["nuptia": [todoOnly]]
        )
        XCTAssertTrue(t1.items.isEmpty)

        let t2 = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            aiFlags: ["nuptia": [projOnly]]
        )
        XCTAssertTrue(t2.items.isEmpty)

        let unrelated = testNote(title: "Other project", tags: ["todo", "other"])
        let t3 = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            aiFlags: ["other": [unrelated]]
        )
        XCTAssertTrue(t3.items.isEmpty)
    }

    func testArchivedNoteProducesNothing() {
        let archived = testNote(tags: ["todo", "nuptia"], archived: true)
        let t = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            aiFlags: ["nuptia": [archived]]
        )
        XCTAssertTrue(t.items.isEmpty, "archived notes must produce no items")
    }

    func testTwoNotesForSameProjectSortedByKindProjectTitle() {
        let n1 = testNote(title: "Zulu task", tags: ["todo", "nuptia"])
        let n2 = testNote(title: "Alpha task", tags: ["todo", "nuptia"])
        let t = StudioTodo.derive(
            from: snapshot([repo("Nuptia", [branch("main")])]),
            nextSteps: ["Nuptia": "Declared step"],
            aiFlags: ["nuptia": [n1, n2]]
        )
        XCTAssertEqual(t.items.count, 3)
        XCTAssertEqual(t.items[0].kind, .declared)
        XCTAssertEqual(t.items[1].kind, .aiFlagged)
        XCTAssertEqual(t.items[1].title, "Alpha task")
        XCTAssertEqual(t.items[2].kind, .aiFlagged)
        XCTAssertEqual(t.items[2].title, "Zulu task")
    }

    func testKindOrderingPlacesAIFlaggedBetweenDeclaredAndUnshared() {
        XCTAssertEqual(StudioTodo.Kind.allCases, [.atRisk, .declared, .aiFlagged, .unshared, .clutter])
        XCTAssertLessThan(StudioTodo.Kind.declared, StudioTodo.Kind.aiFlagged)
        XCTAssertLessThan(StudioTodo.Kind.aiFlagged, StudioTodo.Kind.unshared)
    }

    // MARK: - Python Hook Agreement Tests (§2.6, §2.8)

    private struct PythonDumpResponse: Codable {
        struct TodoItem: Codable {
            let id: String
            let title: String
            let creator: String
            let createdAt: String
            let tags: [String]
            let archived: Bool
        }
        let todos: [TodoItem]?
        let error: String?
    }

    func testPythonFoldAndProjectorAgreeOnOpenTodosForProject() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hookScriptURL = repoRoot.appendingPathComponent("Scripts/unlirice-prompt-hook.py")
        XCTAssertTrue(FileManager.default.fileExists(atPath: hookScriptURL.path))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-hook-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: logURL)
        let service = NoteService(store: store)

        // 1. Open to-do for clearspace
        let n1 = try service.createNote(title: "Bump ClearSpace URL", body: "Need to update marketing url", source: "claude")
        _ = try service.tagNote(id: n1.id, tag: "todo", source: "claude")
        _ = try service.tagNote(id: n1.id, tag: "clearspace", source: "claude")

        // 2. Open to-do for clearspace with append
        let n2 = try service.createNote(title: "Fix ClearSpace icon", body: "Wrong asset used", source: "codex")
        _ = try service.tagNote(id: n2.id, tag: "todo", source: "codex")
        _ = try service.tagNote(id: n2.id, tag: "clearspace", source: "codex")
        _ = try service.appendToNote(id: n2.id, text: "Found high-res asset", source: "human")

        // 3. To-do for clearspace, then archived -> should NOT be included
        let n3 = try service.createNote(title: "Old task", body: "Deprecated", source: "human")
        _ = try service.tagNote(id: n3.id, tag: "todo", source: "human")
        _ = try service.tagNote(id: n3.id, tag: "clearspace", source: "human")
        _ = try service.archiveNote(id: n3.id, reason: "done", source: "human")

        // 4. To-do for clearspace, archived then unarchived -> SHOULD be included
        let n4 = try service.createNote(title: "Reopened task", body: "Turned out not done", source: "antigravity")
        _ = try service.tagNote(id: n4.id, tag: "todo", source: "antigravity")
        _ = try service.tagNote(id: n4.id, tag: "clearspace", source: "antigravity")
        _ = try service.archiveNote(id: n4.id, reason: "mistake", source: "human")
        _ = try service.unarchiveNote(id: n4.id, source: "human")

        // 5. To-do for clearspace, then untagged 'todo' -> should NOT be included
        let n5 = try service.createNote(title: "Untagged task", body: "Not a todo anymore", source: "claude")
        _ = try service.tagNote(id: n5.id, tag: "todo", source: "claude")
        _ = try service.tagNote(id: n5.id, tag: "clearspace", source: "claude")
        _ = try service.untagNote(id: n5.id, tag: "todo", source: "claude")

        // 6. To-do for another project -> should NOT be included for clearspace
        let n6 = try service.createNote(title: "Other project task", body: "For nuptia", source: "codex")
        _ = try service.tagNote(id: n6.id, tag: "todo", source: "codex")
        _ = try service.tagNote(id: n6.id, tag: "nuptia", source: "codex")

        // 7. Clearspace note without 'todo' -> should NOT be included
        let n7 = try service.createNote(title: "Just clearspace info", body: "Architecture note", source: "claude")
        _ = try service.tagNote(id: n7.id, tag: "clearspace", source: "claude")

        // 8. To-do for clearspace, flagged for review -> SHOULD be included
        let n8 = try service.createNote(title: "Flagged todo", body: "Check with team", source: "claude")
        _ = try service.tagNote(id: n8.id, tag: "todo", source: "claude")
        _ = try service.tagNote(id: n8.id, tag: "clearspace", source: "claude")
        let flag = try service.flagForReview(id: n8.id, reason: "needs second look", source: "janitor")
        _ = try service.resolveReview(id: n8.id, flagId: flag.id, source: "human", outcome: "kept")

        // 1. Fold in Swift using Projector
        let events = try store.readAll()
        let projected = Projector.project(events)
        let swiftOpenTodos: [Note] = projected.values.filter { (note: Note) -> Bool in
            !note.archived && note.tags.contains("todo") && note.tags.contains("clearspace")
        }
        let swiftIDs = Set(swiftOpenTodos.map { $0.id.uuidString })
        XCTAssertEqual(swiftIDs, Set([n1.id.uuidString, n2.id.uuidString, n4.id.uuidString, n8.id.uuidString]))

        // 2. Fold in Python via unlirice-prompt-hook.py --dump-todos
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [hookScriptURL.path, "--dump-todos", logURL.path, "ClearSpace"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let response = try JSONDecoder().decode(PythonDumpResponse.self, from: stdoutData)
        let pythonTodos = try XCTUnwrap(response.todos)
        let pythonIDs = Set(pythonTodos.map(\.id))

        // Assert exact agreement on note IDs
        XCTAssertEqual(pythonIDs, swiftIDs)
        XCTAssertEqual(pythonTodos.count, swiftOpenTodos.count)

        // Assert properties match for each note
        for pyItem in pythonTodos {
            let swNoteOpt: Note? = swiftOpenTodos.first { $0.id.uuidString.lowercased() == pyItem.id.lowercased() }
            let swNote = try XCTUnwrap(swNoteOpt)
            XCTAssertEqual(pyItem.title, swNote.title)
            XCTAssertEqual(pyItem.creator, swNote.creator)
            XCTAssertEqual(Set(pyItem.tags), swNote.tags)
            XCTAssertEqual(pyItem.archived, swNote.archived)
        }
    }

    func testPythonFoldFailsOpenOnUnrecognizedEventKind() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hookScriptURL = repoRoot.appendingPathComponent("Scripts/unlirice-prompt-hook.py")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-hook-failopen-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logURL = tempDir.appendingPathComponent("events.jsonl")
        let malformedLine = """
        {"kind": "futureEventKindAddedLater", "noteId": "00000000-0000-0000-0000-000000000001", "timestamp": "2026-09-01T00:00:00Z", "source": "test"}
        """
        try malformedLine.write(to: logURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [hookScriptURL.path, "--dump-todos", logURL.path, "ClearSpace"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 1)
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""
        XCTAssertTrue(stderrStr.contains("unrecognized event kind 'futureEventKindAddedLater'"), stderrStr)
    }
}
