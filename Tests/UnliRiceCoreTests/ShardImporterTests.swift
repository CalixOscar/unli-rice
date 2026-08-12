import XCTest
@testable import UnliRiceCore

final class ShardImporterTests: XCTestCase {
    private var root: URL!
    private var eventLogURL: URL!
    private var shardDir: URL!
    private var syncStateURL: URL!
    private var store: EventStore!
    private var service: NoteService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-importer-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        eventLogURL = root.appendingPathComponent("events.jsonl")
        shardDir = root.appendingPathComponent("shards", isDirectory: true)
        try FileManager.default.createDirectory(at: shardDir, withIntermediateDirectories: true)
        syncStateURL = root.appendingPathComponent("sync-state.json")

        store = try EventStore(fileURL: eventLogURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Purging a note rewrites events.jsonl. Re-running the importer must NOT
    /// resurrect the purged note because the byte cursor in sync-state.json has advanced.
    func testPurgeThenReimportDoesNotResurrect() throws {
        let noteID = UUID()
        let eventID = UUID()
        let shardFile = shardDir.appendingPathComponent("events-phone.jsonl")

        let foreignEvent = """
        {"id":"\(eventID.uuidString)","noteId":"\(noteID.uuidString)",\
        "timestamp":"2026-08-04T09:00:00Z","source":"human","device":"iPhone",\
        "kind":"created","title":"Phone Note","text":"captured on walk"}
        \n
        """
        try Data(foreignEvent.utf8).write(to: shardFile)

        // First import -> imports note
        let receipt1 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt1.eventsAppended, 1)

        let notesBeforePurge = try service.listNotes()
        XCTAssertTrue(notesBeforePurge.contains { $0.title == "Phone Note" })

        // Purge note from local log
        try TrashService.purge(noteIDs: [noteID], logURL: eventLogURL)

        // Note is gone from local store
        let notesAfterPurge = try service.listNotes()
        XCTAssertFalse(notesAfterPurge.contains { $0.title == "Phone Note" })

        // Re-importing must NOT resurrect the purged note
        let receipt2 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt2.eventsAppended, 0)

        let notesAfterReimport = try service.listNotes()
        XCTAssertFalse(notesAfterReimport.contains { $0.title == "Phone Note" })
    }

    func testDoubleImportIsANoOp() throws {
        let shardFile = shardDir.appendingPathComponent("events-phone.jsonl")
        let foreignEvent = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:00:00Z","source":"human","device":"iPhone",\
        "kind":"created","title":"Test Note","text":"hello"}
        \n
        """
        try Data(foreignEvent.utf8).write(to: shardFile)

        let receipt1 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt1.eventsAppended, 1)

        let receipt2 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt2.eventsAppended, 0)
    }

    func testShrunkShardIsRefused() throws {
        let shardFile = shardDir.appendingPathComponent("events-phone.jsonl")
        let line1 = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:00:00Z","source":"human","kind":"created",\
        "title":"Note 1","text":"first"}
        \n
        """
        let line2 = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:01:00Z","source":"human","kind":"created",\
        "title":"Note 2","text":"second"}
        \n
        """
        try Data((line1 + line2).utf8).write(to: shardFile)

        let receipt1 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt1.eventsAppended, 2)

        // Truncate shard file to only line 1
        try Data(line1.utf8).write(to: shardFile)

        XCTAssertThrowsError(try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)) { error in
            guard let shardError = error as? ShardFeedError,
                  case .shardShrunk = shardError else {
                XCTFail("Expected ShardFeedError.shardShrunk, got \(error)")
                return
            }
        }
    }

    func testTruncatedFinalLineLeavesCursorBeforeIt() throws {
        let shardFile = shardDir.appendingPathComponent("events-phone.jsonl")
        let line1 = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:00:00Z","source":"human","kind":"created",\
        "title":"Complete Line","text":"full"}
        \n
        """
        let line2Partial = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:01:00Z","source":"human","kind":"created"
        """ // No trailing newline, truncated JSON

        try Data((line1 + line2Partial).utf8).write(to: shardFile)

        let receipt1 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt1.eventsAppended, 1)

        // Complete line 2
        let line2Full = """
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-04T09:01:00Z","source":"human","kind":"created",\
        "title":"Second Line","text":"now complete"}
        \n
        """
        try Data((line1 + line2Full).utf8).write(to: shardFile)

        let receipt2 = try ShardImporter.importShards(from: shardDir, into: store, syncStateURL: syncStateURL)
        XCTAssertEqual(receipt2.eventsAppended, 1)

        let allNotes = try service.listNotes()
        XCTAssertEqual(allNotes.count, 2)
    }

    /// Importing from a folder that is not a dedicated `shards/` directory — a
    /// user's iCloud sync folder, a scan root — means sharing that folder with
    /// unrelated `.jsonl` files: Claude session logs, eval fixtures, exports.
    /// Appending those as events is unrecoverable, because the log is immutable.
    func testImportFromSharedFolderIgnoresJSONLThatIsNotAShard() throws {
        let sharedFolder = root.appendingPathComponent("Unli thoughts", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedFolder, withIntermediateDirectories: true)

        let phoneShard = sharedFolder.appendingPathComponent("events-phone-ABC.jsonl")
        try Data("""
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-10T02:54:55Z","source":"human","device":"iPhone",\
        "kind":"created","title":"The tabs don't work","text":"switch between projects"}

        """.utf8).write(to: phoneShard)

        // A Claude session transcript, which is also newline-delimited JSON with
        // a `type` field and no business being in anyone's event log.
        let strayLog = sharedFolder.appendingPathComponent("a3f9-session.jsonl")
        try Data("""
        {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
        "timestamp":"2026-08-10T03:00:00Z","source":"claude","kind":"created",\
        "title":"NOT A CAPTURE","text":"transcript line"}

        """.utf8).write(to: strayLog)

        let receipt = try ShardImporter.importShards(
            from: sharedFolder,
            into: store,
            syncStateURL: syncStateURL,
            requiringShardNaming: true,
            cursorNamespace: sharedFolder.path
        )

        XCTAssertEqual(receipt.eventsAppended, 1)
        XCTAssertEqual(receipt.shardsImported, 1)

        let titles = try service.listNotes().map(\.title)
        XCTAssertTrue(titles.contains("The tabs don't work"))
        XCTAssertFalse(titles.contains("NOT A CAPTURE"))
    }

    /// Two folders can hold a shard with the same filename — the phone's own
    /// copy and an iCloud copy of it. Cursors keyed by filename alone would
    /// share one byte offset between them, so whichever imported second would
    /// resume at the other's position and skip real events.
    func testSameShardFilenameInTwoFoldersKeepsSeparateCursors() throws {
        let folderA = root.appendingPathComponent("A", isDirectory: true)
        let folderB = root.appendingPathComponent("B", isDirectory: true)
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

        func shard(title: String) -> Data {
            Data("""
            {"id":"\(UUID().uuidString)","noteId":"\(UUID().uuidString)",\
            "timestamp":"2026-08-10T02:54:55Z","source":"human","device":"iPhone",\
            "kind":"created","title":"\(title)","text":"body"}

            """.utf8)
        }

        let name = "events-phone-SAME.jsonl"
        try shard(title: "From A").write(to: folderA.appendingPathComponent(name))
        try shard(title: "From B").write(to: folderB.appendingPathComponent(name))

        for folder in [folderA, folderB] {
            _ = try ShardImporter.importShards(
                from: folder,
                into: store,
                syncStateURL: syncStateURL,
                requiringShardNaming: true,
                cursorNamespace: folder.path
            )
        }

        let titles = try service.listNotes().map(\.title)
        XCTAssertTrue(titles.contains("From A"))
        XCTAssertTrue(titles.contains("From B"))
    }
}
