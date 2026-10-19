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
        XCTAssertEqual(report.projects.count, 1)
        XCTAssertTrue(report.issues.contains { $0.localizedCaseInsensitiveContains("duplicate") })
        XCTAssertNil(report.projects.first?.repository?.differentTipCount)
        XCTAssertTrue(report.projects.first?.repository?.fromPublishedSnapshot == true)
    }

    private func mkdir(_ url: URL) throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }

    private func note(title: String, body: String, tags: [String] = [], flags: [ReviewFlag] = [], archived: Bool = false) -> Note {
        let date = Date(timeIntervalSince1970: 10)
        return Note(id: UUID(), title: title, body: body, tags: Set(tags), createdAt: date, updatedAt: date, archived: archived, flags: flags)
    }

    private func snapshotRepo(_ name: String) -> RepoSnapshotFile.Repo {
        RepoSnapshotFile.Repo(name: name, currentBranch: "main", detachedHead: false, branches: [], remoteBranchCount: 0, worktrees: [])
    }
}
