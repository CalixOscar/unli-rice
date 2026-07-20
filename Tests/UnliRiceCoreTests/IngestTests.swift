import XCTest
@testable import UnliRiceCore

/// An importer that returns exactly what a test tells it to, so the runner's
/// safety rules can be exercised without touching the real filesystem layout of
/// `~/.claude` or the user's documents.
private struct StubImporter: ResourceImporter {
    let identifier = "stub"
    let displayName = "Stub"
    var resources: [DiscoveredResource]
    func discover() throws -> [DiscoveredResource] { resources }
}

final class IngestTests: XCTestCase {
    var root: URL!
    var eventLogURL: URL!
    var sourceDirectory: URL!
    var service: NoteService!
    var rawStore: RawStore!
    var runner: IngestRunner!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-ingest-tests-\(UUID().uuidString)")
        eventLogURL = root.appendingPathComponent("events.jsonl")
        sourceDirectory = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        service = NoteService(store: try EventStore(fileURL: eventLogURL))
        rawStore = RawStore(directoryURL: RawStore.directoryURL(besideEventLog: eventLogURL))
        runner = IngestRunner(service: service, rawStore: rawStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func writeSource(_ name: String, _ contents: String) throws -> URL {
        let url = sourceDirectory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func resource(
        at url: URL,
        title: String,
        key: String? = nil,
        tags: [String] = ["ingested"]
    ) -> DiscoveredResource {
        DiscoveredResource(
            sourceURL: url,
            key: key ?? url.path,
            title: title,
            summary: "**File:** `\(url.path)`",
            tags: tags,
            occurredAt: Date()
        )
    }

    // MARK: - The permission boundary

    /// The load-bearing test for this component, mirroring the janitor's: no
    /// matter what an importer hands it, the only event kinds ingest can ever
    /// produce are `created`, `appended` and `tagged`. Nothing here archives,
    /// flags, untags, or resolves.
    func testIngestOnlyEverWritesCreatedAppendedAndTagged() throws {
        let first = try writeSource("a.md", "alpha content that is long enough to matter")
        let second = try writeSource("b.md", "beta content that is long enough to matter")
        let importer = StubImporter(resources: [
            resource(at: first, title: "Doc: sources/a.md"),
            resource(at: second, title: "Doc: sources/b.md")
        ])

        try runner.run(importer: importer)
        // Second pass with changed content, to exercise the append path too.
        try writeSource("a.md", "alpha content, revised and still long enough")
        try runner.run(importer: importer)

        let events = try service.transactionLog(limit: Int.max)
            .filter { $0.source == IngestRunner.sourceIdentity }
        XCTAssertFalse(events.isEmpty, "ingest should have done something to make this test meaningful")

        let kinds = Set(events.map(\.kind))
        XCTAssertTrue(
            kinds.isSubset(of: [.created, .appended, .tagged]),
            "ingest produced forbidden event kinds: \(kinds.subtracting([.created, .appended, .tagged]))"
        )
    }

    /// A generated title can collide with one a human already owns. When it
    /// does, the resource is skipped — appending machine-built index text onto
    /// someone's hand-written note is not undoable, because appends are events.
    func testNeverWritesIntoANoteItDidNotCreate() throws {
        let mine = try service.createNote(
            title: "Doc: sources/a.md",
            body: "my own careful notes",
            source: "claude"
        )
        let url = try writeSource("a.md", "unrelated file that happens to collide")

        let report = try runner.run(importer: StubImporter(resources: [resource(at: url, title: "Doc: sources/a.md")]))

        XCTAssertEqual(report.indexed.count, 0)
        XCTAssertEqual(report.revised.count, 0)
        XCTAssertEqual(report.skipped.count, 1)
        XCTAssertEqual(try service.getNote(id: mine.id)?.body, "my own careful notes")
    }

    /// Archiving is how a human says "stop showing me this". Re-indexing would
    /// quietly undo that.
    func testArchivedNoteIsNotReindexed() throws {
        let url = try writeSource("a.md", "content long enough to matter here")
        let importer = StubImporter(resources: [resource(at: url, title: "Doc: sources/a.md")])
        try runner.run(importer: importer)

        let note = try XCTUnwrap(try service.listNotes().first)
        try service.archiveNote(id: note.id, reason: "not interesting", source: "human")

        try writeSource("a.md", "content changed, but I already said no")
        let report = try runner.run(importer: importer)

        XCTAssertEqual(report.revised.count, 0)
        XCTAssertEqual(report.skipped.count, 1)
    }

    // MARK: - Idempotence

    func testUnchangedResourceIsSkippedOnASecondRun() throws {
        let url = try writeSource("a.md", "content long enough to matter here")
        let importer = StubImporter(resources: [resource(at: url, title: "Doc: sources/a.md")])

        let first = try runner.run(importer: importer)
        XCTAssertEqual(first.indexed.count, 1)

        let second = try runner.run(importer: importer)
        XCTAssertEqual(second.indexed.count, 0)
        XCTAssertEqual(second.revised.count, 0)
        XCTAssertEqual(second.skipped.count, 1)
        XCTAssertEqual(try service.listNotes().count, 1, "a repeat run must not create a second note")
    }

    /// A changed file appends a revision rather than creating a second note —
    /// and the bytes that were there before stay in `/raw`.
    func testChangedResourceIsRevisedAndTheOldRawCopySurvives() throws {
        let url = try writeSource("a.md", "the original content, long enough")
        let importer = StubImporter(resources: [resource(at: url, title: "Doc: sources/a.md")])
        try runner.run(importer: importer)

        try writeSource("a.md", "the revised content, also long enough")
        let report = try runner.run(importer: importer)

        XCTAssertEqual(report.revised.count, 1)
        XCTAssertEqual(try service.listNotes().count, 1)

        let stored = try FileManager.default.contentsOfDirectory(atPath: rawStore.directoryURL.path)
        XCTAssertEqual(stored.count, 2, "both revisions should be in /raw — nothing is replaced")

        let note = try XCTUnwrap(try service.listNotes().first)
        XCTAssertTrue(note.body.contains("Revised"))
    }

    /// Found by dry-running the real `~/.claude/projects`: a git worktree gets
    /// its own project directory but shares the parent's session ids, so the
    /// same resource is discovered twice in a single pass and the second copy
    /// must see the note the first one just created.
    func testTheSameKeyTwiceInOneRunDoesNotCreateTwoNotes() throws {
        let first = try writeSource("worktree-a.md", "the same session, seen from two directories")
        let second = try writeSource("worktree-b.md", "the same session, seen from two directories")
        let importer = StubImporter(resources: [
            resource(at: first, title: "Session: Fix the build (aaaaaaaa)", key: "aaaaaaaa"),
            resource(at: second, title: "Session: Fix the build (aaaaaaaa)", key: "aaaaaaaa")
        ])

        let report = try runner.run(importer: importer)

        XCTAssertEqual(try service.listNotes().count, 1, "a permanent title was minted twice")
        XCTAssertEqual(report.indexed.count, 1)
        XCTAssertEqual(report.skipped.count, 1, "the duplicate should be recognised as already indexed")
    }

    /// The bug the first calibration run caught, and the reason `key` exists at
    /// all. A Claude session's `ai-title` is regenerated as the conversation
    /// grows, so the *same* session presents a different title on a later run.
    /// Matching on title minted a brand-new permanent note every time; matching
    /// on the session id recognises it.
    func testADriftedTitleForTheSameKeyDoesNotCreateASecondNote() throws {
        let url = try writeSource("session.jsonl", "the conversation, as it stood this morning")
        try runner.run(importer: StubImporter(resources: [
            resource(at: url, title: "Session: Fix the build (aaaaaaaa)", key: "aaaaaaaa")
        ]))

        // The session continued: new content, and a regenerated title.
        try writeSource("session.jsonl", "the conversation, now considerably longer than before")
        let report = try runner.run(importer: StubImporter(resources: [
            resource(at: url, title: "Session: Fix the build and ship it (aaaaaaaa)", key: "aaaaaaaa")
        ]))

        XCTAssertEqual(try service.listNotes().count, 1, "a drifting title minted a duplicate note")
        XCTAssertEqual(report.revised.count, 1)
        // The title is permanent: it keeps the name it was created with.
        XCTAssertEqual(try service.listNotes().first?.title, "Session: Fix the build (aaaaaaaa)")
    }

    /// Two genuinely different resources that happen to share a title: the
    /// second must not be silently folded into the first.
    func testDifferentKeysWithTheSameTitleDoNotCollide() throws {
        let first = try writeSource("a.md", "the first document, long enough to matter")
        let second = try writeSource("b.md", "the second document, long enough to matter")
        try runner.run(importer: StubImporter(resources: [
            resource(at: first, title: "Doc: README.md", key: "one")
        ]))

        let report = try runner.run(importer: StubImporter(resources: [
            resource(at: second, title: "Doc: README.md", key: "two")
        ]))

        XCTAssertEqual(report.indexed.count, 0)
        XCTAssertEqual(report.skipped.count, 1, "it must refuse rather than write into the other note")
        XCTAssertEqual(try service.listNotes().count, 1)
    }

    func testNoteBudgetDefersRatherThanDrops() throws {
        let resources = try (0..<5).map { index -> DiscoveredResource in
            let url = try writeSource("doc\(index).md", "content number \(index), long enough to matter")
            return resource(at: url, title: "Doc: sources/doc\(index).md")
        }
        let importer = StubImporter(resources: resources)

        let first = try runner.run(importer: importer, config: IngestConfig(noteBudget: 2))
        XCTAssertEqual(first.indexed.count, 2)
        XCTAssertEqual(first.skipped.count, 3)

        // Deferred, not dropped: the importer is deterministic, so the next run
        // finds them again.
        let second = try runner.run(importer: importer, config: IngestConfig(noteBudget: 2))
        XCTAssertEqual(second.indexed.count, 2)
        XCTAssertEqual(try service.listNotes().count, 4)
    }

    func testTagsFromTheImporterAreApplied() throws {
        let url = try writeSource("a.md", "content long enough to matter here")
        try runner.run(importer: StubImporter(resources: [
            resource(at: url, title: "Doc: sources/a.md", tags: ["document", "ingested"])
        ]))

        let note = try XCTUnwrap(try service.listNotes().first)
        XCTAssertEqual(note.tags, ["document", "ingested"])
    }

    // MARK: - RawStore

    /// Ingesting copies. The user's original must be exactly where it was.
    func testRawStoreCopiesAndNeverMovesTheOriginal() throws {
        let url = try writeSource("a.md", "content long enough to matter here")
        let (resource, wasNew) = try rawStore.ingest(contentsOf: url)

        XCTAssertTrue(wasNew)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the original was moved, not copied")
        XCTAssertEqual(try String(contentsOf: rawStore.url(for: resource), encoding: .utf8),
                       "content long enough to matter here")
    }

    func testRawStoreDeduplicatesIdenticalBytes() throws {
        let first = try writeSource("a.md", "identical bytes in two places")
        let second = try writeSource("b.md", "identical bytes in two places")

        let one = try rawStore.ingest(contentsOf: first)
        let two = try rawStore.ingest(contentsOf: second)

        XCTAssertEqual(one.resource.digest, two.resource.digest)
        XCTAssertTrue(one.wasNew)
        XCTAssertFalse(two.wasNew, "the same bytes should not be stored twice")
        XCTAssertTrue(rawStore.contains(digest: one.resource.digest))
    }

    func testRawStoreRefusesFilesOverTheByteLimit() throws {
        let url = try writeSource("big.md", String(repeating: "x", count: 5000))
        let tiny = RawStore(directoryURL: rawStore.directoryURL, byteLimit: 1000)

        XCTAssertThrowsError(try tiny.ingest(contentsOf: url))
    }

    /// The digest suffix has to survive a process restart, or every run mints a
    /// new permanent title for the same file.
    func testStableSuffixIsDeterministic() {
        XCTAssertEqual(
            ImporterText.stableSuffix(for: "/Users/x/docs/README.md"),
            ImporterText.stableSuffix(for: "/Users/x/docs/README.md")
        )
        XCTAssertNotEqual(
            ImporterText.stableSuffix(for: "/Users/x/a/README.md"),
            ImporterText.stableSuffix(for: "/Users/x/b/README.md")
        )
    }
}
