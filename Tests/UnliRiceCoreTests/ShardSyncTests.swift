import XCTest
@testable import UnliRiceCore

final class ShardSyncTests: XCTestCase {
    private var rootDir: URL!
    private var sharedSyncDir: URL!

    private var macLogURL: URL!
    private var macSyncStateURL: URL!
    private var macStore: EventStore!
    private var macService: NoteService!

    private var phoneLogURL: URL!
    private var phoneSyncStateURL: URL!
    private var phoneStore: EventStore!
    private var phoneService: NoteService!

    override func setUpWithError() throws {
        rootDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)

        sharedSyncDir = rootDir.appendingPathComponent("shared_sync", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedSyncDir, withIntermediateDirectories: true)

        let macDir = rootDir.appendingPathComponent("mac_store", isDirectory: true)
        macLogURL = macDir.appendingPathComponent("events.jsonl")
        macSyncStateURL = macDir.appendingPathComponent("sync-state.json")
        macStore = try EventStore(fileURL: macLogURL)
        macService = NoteService(store: macStore)

        let phoneDir = rootDir.appendingPathComponent("phone_store", isDirectory: true)
        phoneLogURL = phoneDir.appendingPathComponent("events.jsonl")
        phoneSyncStateURL = phoneDir.appendingPathComponent("sync-state.json")
        phoneStore = try EventStore(fileURL: phoneLogURL)
        phoneService = NoteService(store: phoneStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: rootDir)
    }

    /// Loop prevention test: Mac published shard must contain ONLY locally originated events.
    /// Foreign imported events must NOT be re-exported back to the shared directory.
    func testMacPublishesOnlyLocallyOriginatedEvents() throws {
        // 1. Create a local Mac note
        _ = try macService.createNote(title: "Mac Note", body: "created on Mac", source: "antigravity")

        // 2. Append an imported foreign event (device: "iPhone") directly to Mac store
        let foreignEvent = Event(
            id: UUID(),
            noteId: UUID(),
            timestamp: Date(),
            source: "human",
            kind: .created,
            title: "Phone Capture",
            text: "phone text",
            device: "iPhone"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let rawForeign = try encoder.encode(foreignEvent)
        try macStore.appendRaw(rawForeign)

        // 3. Publish Mac local events to own published shard file
        let macShardURL = sharedSyncDir.appendingPathComponent("events-mac-123.jsonl")
        let publishedCount = try ShardPublisher.publishLocalEvents(
            eventLogURL: macLogURL,
            to: macShardURL,
            syncStateURL: macSyncStateURL,
            ownDeviceLabel: "Mac"
        )

        // Only 1 event (the Mac note) should be published. The foreign iPhone event must be filtered out!
        XCTAssertEqual(publishedCount, 1)

        let publishedContent = try String(contentsOf: macShardURL, encoding: .utf8)
        XCTAssertTrue(publishedContent.contains("Mac Note"))
        XCTAssertFalse(publishedContent.contains("Phone Capture"))
    }

    /// Full bidirectional sync test between simulated Mac and Phone.
    func testBidirectionalSyncWithTwoDevices() throws {
        let macShardFilename = "events-mac-111.jsonl"
        let phoneShardFilename = "events-phone-222.jsonl"

        let macShardURL = sharedSyncDir.appendingPathComponent(macShardFilename)
        let phoneShardURL = sharedSyncDir.appendingPathComponent(phoneShardFilename)

        // Mac originates Note A
        _ = try macService.createNote(title: "Note A", body: "Mac text", source: "claude")
        try ShardPublisher.publishLocalEvents(
            eventLogURL: macLogURL,
            to: macShardURL,
            syncStateURL: macSyncStateURL,
            ownDeviceLabel: "Mac"
        )

        // Phone originates Note B
        let writer = ShardWriter(shardFileURL: phoneShardURL, deviceLabel: "iPhone")
        let phoneEvent = try writer.writeCapture(transcript: "Note B from phone")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try phoneStore.appendRaw(encoder.encode(phoneEvent))

        // Mac imports foreign shards (skipping own shard)
        let macReceipt = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: macStore,
            syncStateURL: macSyncStateURL,
            ownShardFilename: macShardFilename
        )
        XCTAssertEqual(macReceipt.eventsAppended, 1)

        // Phone imports foreign shards (skipping own shard)
        let phoneReceipt = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: phoneStore,
            syncStateURL: phoneSyncStateURL,
            ownShardFilename: phoneShardFilename
        )
        XCTAssertEqual(phoneReceipt.eventsAppended, 1)

        // Rebuild and verify projections
        macService.rebuild()
        phoneService.rebuild()

        let macNotes = try macService.listNotes()
        let phoneNotes = try phoneService.listNotes()

        XCTAssertEqual(macNotes.count, 2)
        XCTAssertEqual(phoneNotes.count, 2)

        XCTAssertTrue(macNotes.contains { $0.title.contains("Note B") })
        XCTAssertTrue(phoneNotes.contains { $0.title == "Note A" })
    }

    /// Verifies that purging a note on Mac after bidirectional sync does NOT resurrect the note upon re-sync.
    func testPurgeWithBidirectionalCursors() throws {
        let macShardFilename = "events-mac-111.jsonl"
        let phoneShardFilename = "events-phone-222.jsonl"

        let phoneShardURL = sharedSyncDir.appendingPathComponent(phoneShardFilename)
        let writer = ShardWriter(shardFileURL: phoneShardURL, deviceLabel: "iPhone")
        let phoneEvent = try writer.writeCapture(transcript: "Temporary Phone Thought")

        // Mac imports Phone shard
        _ = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: macStore,
            syncStateURL: macSyncStateURL,
            ownShardFilename: macShardFilename
        )
        macService.rebuild()

        let notesBeforePurge = try macService.listNotes()
        XCTAssertTrue(notesBeforePurge.contains { $0.id == phoneEvent.noteId })

        // Mac purges the note
        try TrashService.purge(noteIDs: [phoneEvent.noteId], logURL: macLogURL)
        macService.rebuild()

        let notesAfterPurge = try macService.listNotes()
        XCTAssertFalse(notesAfterPurge.contains { $0.id == phoneEvent.noteId })

        // Mac re-runs sync
        let reimportReceipt = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: macStore,
            syncStateURL: macSyncStateURL,
            ownShardFilename: macShardFilename
        )
        XCTAssertEqual(reimportReceipt.eventsAppended, 0)
        macService.rebuild()

        let notesAfterReimport = try macService.listNotes()
        XCTAssertFalse(notesAfterReimport.contains { $0.id == phoneEvent.noteId })
    }

    /// The mirror image of `testMacPublishesOnlyLocallyOriginatedEvents`, from the
    /// phone's side. Mac-authored events carry no `device` at all — `NoteService`
    /// never sets one — so a filter that only inspects events that *have* a
    /// device label cannot recognise them as foreign.
    func testPhoneDoesNotRepublishImportedMacEvents() throws {
        // The phone's own capture, labelled with its device.
        try phoneStore.append(Event(
            noteId: UUID(), source: "human", kind: .created,
            title: "Dictated on the walk in", text: "mine", device: "iPhone"
        ))

        // A Mac event the phone imported. Mac events have device == nil.
        try phoneStore.append(Event(
            noteId: UUID(), source: "claude", kind: .created,
            title: "Written on the Mac", text: "not mine", device: nil
        ))

        let phoneShard = sharedSyncDir.appendingPathComponent("events-phone-test.jsonl")
        let published = try ShardPublisher.publishLocalEvents(
            eventLogURL: phoneLogURL,
            to: phoneShard,
            syncStateURL: phoneSyncStateURL,
            ownDeviceLabel: "iPhone",
            isLocallyOriginated: { $0.device == "iPhone" }
        )

        let shardText = try String(contentsOf: phoneShard, encoding: .utf8)
        XCTAssertFalse(
            shardText.contains("Written on the Mac"),
            "the phone re-published an imported Mac event into its own shard — a sync loop"
        )
        XCTAssertEqual(published, 1, "only the phone's own capture should be published")
    }

    /// FIX 3 Test: Verifies that purging a note on Mac rewrites events.jsonl smaller,
    /// and ShardPublisher detects the shrink, rebuilds the published shard from scratch,
    /// and removes the purged note from the published shard.
    func testPurgeThenPublishRebuildsPublishedShard() throws {
        _ = try macService.createNote(title: "Note A Keep", body: "body A", source: "antigravity")
        let noteB = try macService.createNote(title: "Note B Purge", body: "body B", source: "antigravity")

        let macShardURL = sharedSyncDir.appendingPathComponent("events-mac-purge-test.jsonl")

        // 1. Initial publish -> publishes 2 events
        let count1 = try ShardPublisher.publishLocalEvents(
            eventLogURL: macLogURL,
            to: macShardURL,
            syncStateURL: macSyncStateURL,
            ownDeviceLabel: "Mac"
        )
        XCTAssertEqual(count1, 2)

        let initialShardContent = try String(contentsOf: macShardURL, encoding: .utf8)
        XCTAssertTrue(initialShardContent.contains("Note A Keep"))
        XCTAssertTrue(initialShardContent.contains("Note B Purge"))

        // 2. Purge Note B on Mac -> rewrites macLogURL smaller
        try TrashService.purge(noteIDs: [noteB.id], logURL: macLogURL)
        macService.rebuild()

        // 3. Publish again -> ShardPublisher catches log shrink, rebuilds published shard from scratch
        let count2 = try ShardPublisher.publishLocalEvents(
            eventLogURL: macLogURL,
            to: macShardURL,
            syncStateURL: macSyncStateURL,
            ownDeviceLabel: "Mac"
        )
        XCTAssertEqual(count2, 1)

        let rebuiltShardContent = try String(contentsOf: macShardURL, encoding: .utf8)
        XCTAssertTrue(rebuiltShardContent.contains("Note A Keep"))
        XCTAssertFalse(rebuiltShardContent.contains("Note B Purge"), "purged note must not linger in published shard")
    }
}
