import XCTest
@testable import UnliRiceCore

final class ProjectGardenTests: XCTestCase {
    private var temporary: URL!

    override func setUp() {
        super.setUp()
        temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ProjectGardenTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporary)
        super.tearDown()
    }

    func testDirectRootAndNestedDiscoveryStopAtProjectsAndDeduplicateOverlappingRoots() throws {
        let project = temporary.appendingPathComponent("Garden")
        try mkdir(project)
        try "# Garden".write(to: project.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let nested = project.appendingPathComponent("nested")
        try mkdir(nested)
        try "".write(to: nested.appendingPathComponent("PROJECT_NOTES.md"), atomically: true, encoding: .utf8)
        let report = ProjectGarden.load(roots: [temporary, project], notes: [], now: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(report.projects.map(\.name), ["Garden"])
        XCTAssertEqual(report.projects.first?.folderURL?.standardizedFileURL.path, project.standardizedFileURL.path)
    }

    func testIgnoreHiddenDependencyAndMarkerBoundaries() throws {
        let root = temporary.appendingPathComponent("Projects")
        try mkdir(root)
        for name in [".hidden", "node_modules", "vendor"] {
            let folder = root.appendingPathComponent(name); try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        let ignored = root.appendingPathComponent("ignored"); try mkdir(ignored)
        try "".write(to: ignored.appendingPathComponent(LocalFileImporter.ignoreMarkerFilename), atomically: true, encoding: .utf8)
        try "".write(to: ignored.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let kept = root.appendingPathComponent("kept"); try mkdir(kept)
        try "".write(to: kept.appendingPathComponent("PROJECT_NOTES.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectGarden.load(roots: [root], notes: []).projects.map(\.name), ["kept"])
    }

    func testLatestAppendBlockDoesNotResurrectOldNextStepAndMemoryStatusIsBounded() throws {
        let folder = temporary.appendingPathComponent("Garden"); try mkdir(folder)
        let status = String(repeating: "s", count: 450)
        let memory = "**Status:**\n\(status)\n\n**Next step:**\n\n**Owner:** me"
        try memory.write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let body = "# Garden\n\n**Next step:** old\n\n---\n\n# Update\n\nA current paragraph."
        let report = ProjectGarden.load(roots: [folder], notes: [note(title: "Project: Garden", body: body)])
        let project = try XCTUnwrap(report.projects.first)
        XCTAssertEqual(project.status?.count, 400)
        XCTAssertNil(project.nextStep)
    }

    func testExplicitProvenanceWinsOverTagAndComponentBoundaries() throws {
        let one = temporary.appendingPathComponent("one"); let two = temporary.appendingPathComponent("two")
        try mkdir(one); try mkdir(two)
        try "".write(to: one.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        try "".write(to: two.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let body = "**Project:** `\(one.path)`"
        let linked = note(title: "linked", body: body, tags: ["one"])
        let unrelated = note(title: "boundary", body: "**Project:** `/tmp/one-other`", tags: ["one"])
        let archived = note(title: "old", body: "**Project:** `\(one.path)`", archived: true)
        let projects = ProjectGarden.load(roots: [temporary], notes: [linked, unrelated, archived]).projects
        XCTAssertEqual(projects.first(where: { $0.name == "one" })?.notes.map(\.title), ["linked"])
        XCTAssertTrue(projects.allSatisfy { !$0.notes.contains(where: { $0.title == "old" }) })
    }

    func testTodoAndUnresolvedReviewFlagsDriveAttentionOnly() throws {
        let folder = temporary.appendingPathComponent("Garden"); try mkdir(folder)
        try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let flag = ReviewFlag(id: UUID(), source: "test", reason: "check", timestamp: Date())
        let todo = note(title: "todo", body: "", tags: ["todo", "Garden"], flags: [flag])
        let project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: [todo]).projects.first)
        XCTAssertEqual(project.todoCount, 1)
        XCTAssertEqual(project.reviewCount, 1)
        XCTAssertTrue(project.needsAttention)
    }

    func testDuplicateSnapshotNamesAreAnIssueAndRemoteLessRepositoryIsUnknown() throws {
        let snapshot = RepoSnapshotFile(generatedAt: Date(timeIntervalSince1970: 42), deviceLabel: "test", repos: [
            snapshotRepo("historical"), snapshotRepo("historical")
        ])
        let report = ProjectGarden.load(roots: [], notes: [], publishedSnapshot: snapshot)
        XCTAssertEqual(report.projects.count, 0)
        XCTAssertTrue(report.issues.contains { $0.localizedCaseInsensitiveContains("duplicate") })
    }

    func testNotesOnlyRegistrationJoinsTaggedTodoAndSnapshotWithoutDuplicateCard() throws {
        let registration = note(title: "Project: X", body: "# X\n\n**Next step:** keep shipping", tags: ["X"])
        let todo = note(title: "todo", body: "", tags: ["X", "todo"])
        let snapshot = RepoSnapshotFile(generatedAt: Date(timeIntervalSince1970: 42), deviceLabel: "test", repos: [snapshotRepo("X")])
        let report = ProjectGarden.load(roots: [], notes: [registration, todo], publishedSnapshot: snapshot)
        let project = try XCTUnwrap(report.projects.first)
        XCTAssertEqual(report.projects.count, 1)
        XCTAssertEqual(project.id, "notes:x")
        XCTAssertEqual(Set(project.notes.map(\.title)), ["Project: X", "todo"])
        XCTAssertEqual(project.nextStep, "keep shipping")
        XCTAssertEqual(project.notes.count, 2)
        XCTAssertEqual(project.todoCount, 1)
        XCTAssertTrue(project.repository?.fromPublishedSnapshot == true)
        XCTAssertEqual(project.repository?.observedAt, snapshot.generatedAt)
    }

    func testSnapshotOnlyAssociatesUniqueNameTagAndUsesSnapshotStepWhenMemoryMissing() throws {
        let tagged = note(title: "history", body: "A historical note", tags: ["History"], creator: "ingest")
        let snapshot = RepoSnapshotFile(generatedAt: Date(timeIntervalSince1970: 84), deviceLabel: "test", repos: [
            RepoSnapshotFile.Repo(name: "History", currentBranch: "main", detachedHead: false, branches: [], remoteBranchCount: 0, worktrees: [], nextStep: "revisit archive")
        ])
        let report = ProjectGarden.load(roots: [], notes: [tagged], publishedSnapshot: snapshot)
        let project = try XCTUnwrap(report.projects.first)
        XCTAssertEqual(project.notes.map(\.title), ["history"])
        XCTAssertEqual(project.nextStep, "revisit archive")
        XCTAssertTrue(project.nextStepSource?.contains("saved snapshot") == true)
        XCTAssertEqual(project.statusSource, "imported note: history (note updated)")
        XCTAssertEqual(project.repository?.observedAt, snapshot.generatedAt)
    }

    func testRegistrationIsPreferredForStatusAndRandomTaskDoesNotSupplyFolderNextStep() throws {
        let folder = temporary.appendingPathComponent("Garden"); try mkdir(folder)
        try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let registration = note(title: "Project: Garden", body: "Registration status")
        let task = note(title: "task", body: "Task status\n\n**Next step:** do task", tags: ["Garden"])
        let report = ProjectGarden.load(roots: [folder], notes: [task, registration])
        let project = try XCTUnwrap(report.projects.first)
        XCTAssertEqual(project.status, "Registration status")
        XCTAssertEqual(project.statusSource, "note: Project: Garden (note updated)")
        XCTAssertNil(project.nextStep)
    }

    func testMissingRootIsReportedAndOneCharacterRegistrationIsValid() throws {
        let missing = temporary.appendingPathComponent("gone")
        let report = ProjectGarden.load(roots: [missing], notes: [note(title: "Project:X", body: "X")])
        XCTAssertEqual(report.projects.map(\.name), ["X"])
        XCTAssertTrue(report.issues.contains { $0.localizedCaseInsensitiveContains("could not read") })
    }

    func testLiveRepositoryKeepsItsDateWhileMissingMemoryUsesDatedSnapshotStep() throws {
        let folder = try repository("Live", remote: true)
        let old = Date(timeIntervalSince1970: 84)
        let now = Date(timeIntervalSince1970: 500)
        let snapshot = RepoSnapshotFile(generatedAt: old, deviceLabel: "test", repos: [
            RepoSnapshotFile.Repo(name: "Live", currentBranch: "old", detachedHead: false,
                                  branches: [], remoteBranchCount: 0, worktrees: [], nextStep: "Review the draft")
        ])
        let project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: [], publishedSnapshot: snapshot, now: now).projects.first)
        XCTAssertEqual(project.nextStep, "Review the draft")
        XCTAssertTrue(project.nextStepSource?.contains(old.formatted(date: .abbreviated, time: .shortened)) == true)
        XCTAssertEqual(project.repository?.currentBranch, "main")
        XCTAssertEqual(project.repository?.observedAt, now)
        XCTAssertEqual(project.repository?.fromPublishedSnapshot, false)

        try "**Status:** Current\n**Next step:**\n**Owner:** Me".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let reread = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: [], publishedSnapshot: snapshot).projects.first)
        XCTAssertNil(reread.nextStep, "Readable current memory clears the old snapshot step")
    }

    func testUnavailableMemoryIsReportedAndDoesNotBlockSnapshotFallback() throws {
        let folder = try repository("Unreadable", remote: false)
        try Data([0xff, 0xfe]).write(to: folder.appendingPathComponent("memory.md"))
        let snapshot = RepoSnapshotFile(generatedAt: Date(timeIntervalSince1970: 42), deviceLabel: "test", repos: [
            RepoSnapshotFile.Repo(name: "Unreadable", currentBranch: nil, detachedHead: false,
                                  branches: [], remoteBranchCount: 0, worktrees: [], nextStep: "Check the source")
        ])
        let project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: [], publishedSnapshot: snapshot).projects.first)
        XCTAssertFalse(project.issues.isEmpty)
        XCTAssertEqual(project.nextStep, "Check the source")
        XCTAssertNil(project.repository?.differentTipCount)
    }

    func testOversizedAndSymlinkMemoryAreNotInterpretedAsCurrentStatus() throws {
        let folder = temporary.appendingPathComponent("Large")
        try mkdir(folder)
        let memory = folder.appendingPathComponent("memory.md")
        try ("**Status:** Looks good\n" + String(repeating: "x", count: 128 * 1024)).write(to: memory, atomically: true, encoding: .utf8)
        var project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertNil(project.status)
        XCTAssertTrue(project.issues.contains { $0.contains("too large") })
        try FileManager.default.removeItem(at: memory)
        let external = temporary.appendingPathComponent("external.md")
        try "**Status:** Outside the project".write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: memory, withDestinationURL: external)
        project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertNil(project.status)
        XCTAssertTrue(project.issues.contains { $0.contains("symlink") })
    }

    func testMultilineFieldsAreReadAndNextStepIsBounded() throws {
        let folder = temporary.appendingPathComponent("Fields")
        try mkdir(folder)
        let body = "**Status:** First line\nsecond line\n**Task:** Work\n**Next step:** " + String(repeating: "a", count: 900) + "\n**Gotchas:** Keep separate"
        try body.write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        let project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertEqual(project.status, "First line second line")
        XCTAssertEqual(project.nextStep?.count, 800)
        XCTAssertTrue(project.nextStep?.hasSuffix("…") == true)
        XCTAssertNotNil(project.statusDate)
    }

    func testNextStepSourceKeepsItsOwnDateWhenStatusComesFromANote() throws {
        let folder = temporary.appendingPathComponent("Dates")
        try mkdir(folder)
        let memory = folder.appendingPathComponent("memory.md")
        try "**Next step:** Check the layout".write(to: memory, atomically: true, encoding: .utf8)
        let memoryDate = Date(timeIntervalSince1970: 2_000)
        try FileManager.default.setAttributes([.modificationDate: memoryDate], ofItemAtPath: memory.path)
        let registration = note(title: "Project: Dates", body: "An older recorded status")
        let project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: [registration]).projects.first)
        XCTAssertEqual(project.statusDate, registration.updatedAt)
        XCTAssertTrue(project.nextStepSource?.contains(memoryDate.formatted(date: .abbreviated, time: .shortened)) == true)
        let notesOnly = try XCTUnwrap(ProjectGarden.load(roots: [], notes: [
            note(title: "Project: Notes", body: "A story\n\n**Next step:** Read it")
        ]).projects.first)
        XCTAssertTrue(notesOnly.nextStepSource?.contains(registration.updatedAt.formatted(date: .abbreviated, time: .shortened)) == true)
    }

    func testDuplicateFolderNamesKeepSeparateIdentityAndDoNotUseAmbiguousTags() throws {
        let first = temporary.appendingPathComponent("one/Same")
        let second = temporary.appendingPathComponent("two/Same")
        for folder in [first, second] {
            try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        let registration = note(title: "Project: Same", body: "A project story")
        let tagged = note(title: "Uncertain task", body: "", tags: ["same", "todo"])
        let snapshot = RepoSnapshotFile(generatedAt: Date(), deviceLabel: "test", repos: [snapshotRepo("Same")])
        let report = ProjectGarden.load(roots: [temporary], notes: [registration, tagged], publishedSnapshot: snapshot)
        let local = report.projects.filter { $0.folderURL != nil }
        XCTAssertEqual(local.count, 2)
        XCTAssertEqual(Set(local.map(\.id)).count, 2)
        XCTAssertTrue(local.allSatisfy { $0.notes.isEmpty && $0.repository == nil })
        XCTAssertEqual(report.projects.filter { $0.folderURL == nil }.count, 1)
    }

    func testMostSpecificProjectPathOwnsTheNoteAndOverridesSourceFileAndTags() throws {
        let parent = temporary.appendingPathComponent("Parent")
        let child = parent.appendingPathComponent("Child")
        let other = temporary.appendingPathComponent("Other")
        for folder in [parent, child, other] {
            try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        let linked = note(title: "Decision", body: "**Project:** `\(child.path)`\n**File:** `\(other.path)/README.md`", tags: ["Parent", "Other"])
        let projects = ProjectGarden.load(roots: [parent, child, other], notes: [linked]).projects
        XCTAssertEqual(projects.filter { !$0.notes.isEmpty }.map(\.name), ["Child"])
    }

    func testNotesOnlyProjectsRespectProvenanceAndUseOnlyMatchingRegistration() throws {
        let alpha = note(title: "Project: Alpha", body: "Alpha story")
        let beta = note(title: "Project: Beta", body: "Beta story", tags: ["Alpha"])
        let outside = note(title: "Outside task", body: "**Project:** `/some/other/project`", tags: ["Alpha", "todo"])
        let projects = ProjectGarden.load(roots: [], notes: [beta, outside, alpha]).projects
        let project = try XCTUnwrap(projects.first { $0.name == "Alpha" })
        XCTAssertEqual(project.status, "Alpha story")
        XCTAssertEqual(project.todoCount, 0)
        XCTAssertFalse(project.notes.contains { $0.id == outside.id })
    }

    func testLatestNotesOnlyAppendClearsEarlierStepAndExcerptsStayBounded() throws {
        let registration = note(title: "Project: Resting", body: "**Next step:** Old task\n\n---\n" + String(repeating: "s", count: 900))
        let archived = note(title: "Project: Hidden", body: "Hidden", archived: true)
        let project = try XCTUnwrap(ProjectGarden.load(roots: [], notes: [archived, registration]).projects.first)
        XCTAssertEqual(project.name, "Resting")
        XCTAssertNil(project.nextStep)
        XCTAssertEqual(project.status?.count, 400)
        XCTAssertFalse(project.needsAttention)
    }

    func testRemoteComparisonIsUnknownWithoutRefsAndNeverCausesAttentionAlone() throws {
        let folder = try repository("Refs", remote: false)
        var project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertNil(project.repository?.differentTipCount)
        let remote = folder.appendingPathComponent(".git/refs/remotes/origin")
        try mkdir(remote)
        try String(repeating: "b", count: 40).write(to: remote.appendingPathComponent("main"), atomically: true, encoding: .utf8)
        project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertEqual(project.repository?.differentTipCount, 1)
        XCTAssertFalse(project.needsAttention)
        try "invalid".write(to: folder.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        project = try XCTUnwrap(ProjectGarden.load(roots: [folder], notes: []).projects.first)
        XCTAssertNil(project.repository)
        XCTAssertFalse(project.issues.isEmpty)
    }

    func testDiscoverySkipsArchiveAndSymlinkAndHonorsRootIgnoreMarker() throws {
        let root = temporary.appendingPathComponent("Search")
        let target = temporary.appendingPathComponent("Outside")
        for folder in [target, root.appendingPathComponent("Archive/Hidden")] {
            try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked"), withDestinationURL: target)
        XCTAssertTrue(ProjectGarden.load(roots: [root], notes: []).projects.isEmpty)
        try "".write(to: target.appendingPathComponent(LocalFileImporter.ignoreMarkerFilename), atomically: true, encoding: .utf8)
        XCTAssertTrue(ProjectGarden.load(roots: [target], notes: []).projects.isEmpty)
    }

    func testUnreadableFolderInsideARootIsACantReadProject() throws {
        let root = temporary.appendingPathComponent("root")
        let locked = root.appendingPathComponent("locked")
        try mkdir(locked)
        try "".write(to: locked.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let report = ProjectGarden.load(roots: [root], notes: [])
        let project = try XCTUnwrap(report.projects.first { $0.name == "locked" })
        XCTAssertEqual(project.issues.first, ProjectGarden.unreadableFolderIssue)
        XCTAssertEqual(GardenCrate.state(of: project), .cantRead(ProjectGarden.unreadableFolderIssue))
    }

    func testUnreadableRootStaysAGlobalIssue() throws {
        let root = temporary.appendingPathComponent("root")
        try mkdir(root)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path) }

        let report = ProjectGarden.load(roots: [root], notes: [])
        XCTAssertTrue(report.projects.isEmpty)
        XCTAssertTrue(report.issues.contains { $0.hasPrefix("Project discovery could not") })
    }

    func testDiscoveryDepthAndProjectCapAreReported() throws {
        let depthRoot = temporary.appendingPathComponent("Depth")
        for suffix in ["a/b/c/Near", "d/e/f/g/TooDeep"] {
            let folder = depthRoot.appendingPathComponent(suffix)
            try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        let depth = ProjectGarden.load(roots: [depthRoot], notes: [])
        XCTAssertEqual(depth.projects.map(\.name), ["Near"])
        XCTAssertFalse(depth.issues.isEmpty)
        let capRoot = temporary.appendingPathComponent("Cap")
        for i in 0...500 {
            let folder = capRoot.appendingPathComponent(String(format: "Project%03d", i))
            try mkdir(folder)
            try "".write(to: folder.appendingPathComponent("memory.md"), atomically: true, encoding: .utf8)
        }
        let capped = ProjectGarden.load(roots: [capRoot], notes: [])
        XCTAssertEqual(capped.projects.count, 500)
        XCTAssertTrue(capped.issues.contains { $0.contains("bounded") })
    }

    func testDirectoryCapAndRepeatedLoadsAreDeterministicAndReadOnly() throws {
        let root = temporary.appendingPathComponent("Directories")
        for i in 0...2_000 { try mkdir(root.appendingPathComponent(String(format: "Empty%04d", i))) }
        let report = ProjectGarden.load(roots: [root], notes: [])
        XCTAssertTrue(report.issues.contains { $0.contains("bounded") })
        let project = temporary.appendingPathComponent("Untouched")
        try mkdir(project)
        let file = project.appendingPathComponent("memory.md")
        let body = Data("**Status:** Resting\n**Next step:** None open".utf8)
        try body.write(to: file)
        let one = ProjectGarden.load(roots: [project], notes: [])
        let two = ProjectGarden.load(roots: [project], notes: [])
        XCTAssertEqual(one.projects.map(\.id), two.projects.map(\.id))
        XCTAssertEqual(try Data(contentsOf: file), body)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: project.path), ["memory.md"])
    }

    private func repository(_ name: String, remote: Bool) throws -> URL {
        let folder = temporary.appendingPathComponent(name)
        let git = folder.appendingPathComponent(".git")
        try mkdir(git.appendingPathComponent("refs/heads"))
        try "ref: refs/heads/main\n".write(to: git.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let sha = String(repeating: "a", count: 40)
        try sha.write(to: git.appendingPathComponent("refs/heads/main"), atomically: true, encoding: .utf8)
        if remote {
            try mkdir(git.appendingPathComponent("refs/remotes/origin"))
            try sha.write(to: git.appendingPathComponent("refs/remotes/origin/main"), atomically: true, encoding: .utf8)
        }
        return folder
    }

    private func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    private func note(title: String, body: String, tags: [String] = [], flags: [ReviewFlag] = [], archived: Bool = false, creator: String = "") -> Note {
        let date = Date(timeIntervalSince1970: 10)
        return Note(id: UUID(), title: title, body: body, tags: Set(tags), creator: creator, createdAt: date, updatedAt: date, archived: archived, flags: flags)
    }

    private func snapshotRepo(_ name: String) -> RepoSnapshotFile.Repo {
        RepoSnapshotFile.Repo(name: name, currentBranch: "main", detachedHead: false, branches: [], remoteBranchCount: 0, worktrees: [])
    }
}
