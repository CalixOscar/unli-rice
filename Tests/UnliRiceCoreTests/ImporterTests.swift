import XCTest
@testable import UnliRiceCore

/// Parsing tests written against the *real* record shapes found in
/// `~/.claude/projects` on this machine, not against a guess at the format.
/// Every field asserted here was observed in an actual session file.
final class ClaudeSessionImporterTests: XCTestCase {
    var projectsDirectory: URL!

    override func setUpWithError() throws {
        projectsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: projectsDirectory.appendingPathComponent("-Users-someone-Projects-Thing"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: projectsDirectory)
    }

    @discardableResult
    private func writeSession(_ id: String, lines: [String]) throws -> URL {
        let url = projectsDirectory
            .appendingPathComponent("-Users-someone-Projects-Thing")
            .appendingPathComponent("\(id).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// `message.content` is a bare String on some user records and an array of
    /// typed blocks on others — both shapes appear in the same real file, so
    /// handling only one loses the opening prompt of most sessions.
    func testExtractsTextFromBothContentShapes() throws {
        let stringShape = try XCTUnwrap(
            "{\"message\":{\"role\":\"user\",\"content\":\"plain string form\"}}".data(using: .utf8)
        )
        let blockShape = try XCTUnwrap(
            """
            {"message":{"role":"user","content":[{"type":"text","text":"block form"},\
            {"type":"tool_use","name":"Read"}]}}
            """.data(using: .utf8)
        )

        let asString = try XCTUnwrap(JSONSerialization.jsonObject(with: stringShape) as? [String: Any])
        let asBlocks = try XCTUnwrap(JSONSerialization.jsonObject(with: blockShape) as? [String: Any])

        XCTAssertEqual(ClaudeSessionImporter.text(fromMessageIn: asString), "plain string form")
        XCTAssertEqual(ClaudeSessionImporter.text(fromMessageIn: asBlocks), "block form")
    }

    /// A title the user typed beats a generated one, and a generated one beats
    /// the truncated `lastPrompt` fallback.
    func testCustomTitleWinsOverAITitle() throws {
        let url = try writeSession("a2ea2835-4f61-4ace-a52a-c399b02d29f0", lines: [
            #"{"type":"ai-title","aiTitle":"Generated title","sessionId":"a2ea2835-4f61-4ace-a52a-c399b02d29f0"}"#,
            #"{"type":"custom-title","customTitle":"Title I typed","sessionId":"a2ea2835-4f61-4ace-a52a-c399b02d29f0"}"#
        ])

        let parsed = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).parse(url)
        XCTAssertEqual(parsed.noteTitle, "Session: Title I typed (a2ea2835)")
    }

    /// `ai-title` is regenerated as a session grows; the last one saw the most.
    func testLastAITitleWins() throws {
        let url = try writeSession("11112222-3333-4444-5555-666677778888", lines: [
            #"{"type":"ai-title","aiTitle":"Early guess"}"#,
            #"{"type":"ai-title","aiTitle":"Better guess"}"#
        ])

        let parsed = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).parse(url)
        XCTAssertEqual(parsed.noteTitle, "Session: Better guess (11112222)")
    }

    /// Two sessions can genuinely share a generated title. Titles are permanent
    /// and resolve wiki-links by exact match, so the session id has to be in
    /// there or one of them becomes unreachable.
    func testTitlesStayUniqueWhenSessionTitlesCollide() throws {
        let first = try writeSession("aaaaaaaa-0000-0000-0000-000000000000", lines: [
            #"{"type":"ai-title","aiTitle":"Fix the build"}"#
        ])
        let second = try writeSession("bbbbbbbb-0000-0000-0000-000000000000", lines: [
            #"{"type":"ai-title","aiTitle":"Fix the build"}"#
        ])
        let importer = ClaudeSessionImporter(projectsDirectory: projectsDirectory)

        XCTAssertNotEqual(try importer.parse(first).noteTitle, try importer.parse(second).noteTitle)
    }

    func testSkipsSessionsBelowTheMessageFloor() throws {
        try writeSession("cccccccc-0000-0000-0000-000000000000", lines: [
            #"{"type":"ai-title","aiTitle":"Abandoned start"}"#,
            #"{"type":"user","message":{"role":"user","content":"hello"},"cwd":"/tmp"}"#
        ])

        let found = try ClaudeSessionImporter(projectsDirectory: projectsDirectory, minimumMessages: 4).discover()
        XCTAssertTrue(found.isEmpty, "a two-message abandoned session is noise, not signal")
    }

    /// A git worktree gets its own `~/.claude/projects` directory but shares the
    /// parent's session ids, so one conversation is on disk twice, diverged.
    /// They are one session and must collapse to one resource — keeping
    /// whichever copy saw more of it.
    func testTwoCopiesOfOneSessionCollapseToTheRicherOne() throws {
        let shared = "ffffffff-0000-0000-0000-000000000000"
        let short = [
            #"{"type":"ai-title","aiTitle":"Short copy","sessionId":"\#(shared)"}"#,
            #"{"type":"user","message":{"role":"user","content":"one"},"sessionId":"\#(shared)"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"a"}]},"sessionId":"\#(shared)"}"#,
            #"{"type":"user","message":{"role":"user","content":"two"},"sessionId":"\#(shared)"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"b"}]},"sessionId":"\#(shared)"}"#
        ]
        let long = short + [
            #"{"type":"user","message":{"role":"user","content":"three"},"sessionId":"\#(shared)"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"c"}]},"sessionId":"\#(shared)"}"#,
            #"{"type":"ai-title","aiTitle":"Long copy","sessionId":"\#(shared)"}"#
        ]

        // Same session id, two directories — exactly the worktree situation.
        let worktree = projectsDirectory.appendingPathComponent("-Users-someone-Projects-Thing--worktrees-x")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try short.joined(separator: "\n")
            .write(to: worktree.appendingPathComponent("\(shared).jsonl"), atomically: true, encoding: .utf8)
        try writeSession(shared, lines: long)

        let found = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).discover()

        XCTAssertEqual(found.count, 1, "one session became \(found.count) resources: \(found.map(\.title))")
        let resource = try XCTUnwrap(found.first)
        XCTAssertEqual(resource.key, shared, "the session id is the identity")
        XCTAssertTrue(resource.title.contains("Long copy"), "the fuller copy should win, got: \(resource.title)")
    }

    func testKeyIsTheSessionIdNotTheTitle() throws {
        let url = try writeSession("99999999-1111-2222-3333-444444444444", lines: [
            #"{"type":"ai-title","aiTitle":"Some title"}"#
        ])
        let parsed = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).parse(url)
        XCTAssertEqual(parsed.asResource(sourceURL: url).key, "99999999-1111-2222-3333-444444444444")
    }

    func testSummaryCarriesProjectAndOpeningPrompt() throws {
        try writeSession("dddddddd-0000-0000-0000-000000000000", lines: [
            #"{"type":"ai-title","aiTitle":"Real work"}"#,
            #"{"type":"user","message":{"role":"user","content":"Please refactor the exporter"},"cwd":"/Users/someone/Projects/Thing","timestamp":"2026-07-18T14:37:38.450Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]},"timestamp":"2026-07-18T14:38:00.000Z"}"#,
            #"{"type":"user","message":{"role":"user","content":"thanks"},"timestamp":"2026-07-18T14:39:00.000Z"}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]},"timestamp":"2026-07-18T14:40:00.000Z"}"#
        ])

        let found = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).discover()
        let resource = try XCTUnwrap(found.first)

        XCTAssertTrue(resource.summary.contains("/Users/someone/Projects/Thing"))
        XCTAssertTrue(resource.summary.contains("Please refactor the exporter"))
        XCTAssertTrue(resource.summary.contains("2 user / 2 assistant"))
        XCTAssertEqual(resource.tags, ["claude-session", "ingested"])
    }

    func testMalformedLinesDoNotAbortTheParse() throws {
        try writeSession("eeeeeeee-0000-0000-0000-000000000000", lines: [
            "{ this is not json at all",
            #"{"type":"ai-title","aiTitle":"Survived"}"#,
            "",
            #"{"type":"user","message":{"role":"user","content":"one"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"two"}]}}"#,
            #"{"type":"user","message":{"role":"user","content":"three"}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"four"}]}}"#
        ])

        let found = try ClaudeSessionImporter(projectsDirectory: projectsDirectory).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(try XCTUnwrap(found.first).title.contains("Survived"))
    }

    func testMissingProjectsDirectoryYieldsNothingRatherThanThrowing() throws {
        let importer = ClaudeSessionImporter(
            projectsDirectory: projectsDirectory.appendingPathComponent("does-not-exist")
        )
        XCTAssertEqual(try importer.discover().count, 0)
    }
}

final class LocalFileImporterTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-localfiles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ relativePath: String, _ contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private var prose: String { String(repeating: "Real prose content. ", count: 20) }

    func testFindsProseAndIgnoresCode() throws {
        try write("docs/design.md", prose)
        try write("src/main.swift", prose)

        let found = try LocalFileImporter(roots: [root]).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertTrue(try XCTUnwrap(found.first).title.hasSuffix("docs/design.md"))
    }

    /// Descending into these finds thousands of vendored READMEs nobody wrote.
    func testSkipsBuildAndDependencyDirectories() throws {
        try write("docs/real.md", prose)
        try write("node_modules/some-package/README.md", prose)
        try write(".build/checkouts/thing/README.md", prose)

        let found = try LocalFileImporter(roots: [root]).discover()
        XCTAssertEqual(found.count, 1, "found: \(found.map(\.title))")
    }

    func testSkipsFilesBelowTheSizeFloor() throws {
        try write("docs/stub.md", "tiny")
        try write("docs/real.md", prose)

        let found = try LocalFileImporter(roots: [root]).discover()
        XCTAssertEqual(found.count, 1)
    }

    /// A nominated folder is usually a folder *of projects*, and the
    /// retrospective can only see a project if a note says `**Project:**`.
    /// Nested documents belong to the project, not to the subfolder they happen
    /// to sit in.
    func testDocumentsAreAttributedToTheirProjectFolder() throws {
        try write("Nuptia/AGENTS.md", prose)
        try write("Nuptia/studio-notes/03_assets.md", prose)

        let found = try LocalFileImporter(roots: [root]).discover()
        let projects = found.map { Retrospective.project(of: note(from: $0)) }
        XCTAssertEqual(Set(projects.compactMap { $0 }), ["Nuptia"])
        XCTAssertEqual(projects.count, 2)
    }

    /// Indexing a stray file in the root itself must not invent a project named
    /// after the root — the same mistake `Retrospective.project(of:)` rejects
    /// when a "project" turns out to be someone's home directory.
    func testALooseFileInTheRootBelongsToNoProject() throws {
        try write("loose.md", prose)

        let found = try LocalFileImporter(roots: [root]).discover()
        XCTAssertNil(Retrospective.project(of: note(from: try XCTUnwrap(found.first))))
    }

    /// The shape the runner gives a discovered resource, minus everything the
    /// project line doesn't depend on.
    private func note(from resource: DiscoveredResource) -> Note {
        Note(id: UUID(), title: resource.title, body: resource.summary, createdAt: Date(), updatedAt: Date())
    }

    /// Two roots can each hold `docs/README.md`. Both must be ingestable, so the
    /// collision is broken deterministically here.
    func testCollidingTitlesAreDisambiguatedDeterministically() throws {
        try write("one/docs/README.md", prose)
        try write("two/docs/README.md", prose)

        let importer = LocalFileImporter(roots: [root])
        let found = try importer.discover()

        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(Set(found.map(\.title)).count, 2, "titles collided: \(found.map(\.title))")
        XCTAssertEqual(found.map(\.title), try importer.discover().map(\.title), "titles must be stable across runs")
    }

    /// No default root, and an empty list finds nothing — "scan everything" is
    /// not a state this type can end up in by accident.
    func testNoRootsFindsNothing() throws {
        XCTAssertEqual(try LocalFileImporter(roots: []).discover().count, 0)
    }
}
