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

    /// Verifies two Mac devices ("Mac 1" and "Mac 2") syncing into the same shared folder.
    /// Mac 2 imports Mac 1's shard, but Mac 2 MUST NOT re-publish Mac 1's imported events into Mac 2's published shard.
    func testTwoMacDevicesPublishingIntoOneFolder() throws {
        let mac1Dir = rootDir.appendingPathComponent("mac1_store", isDirectory: true)
        let mac1LogURL = mac1Dir.appendingPathComponent("events.jsonl")
        let mac1SyncStateURL = mac1Dir.appendingPathComponent("sync-state.json")
        let mac1Store = try EventStore(fileURL: mac1LogURL)
        let mac1Service = NoteService(store: mac1Store, deviceLabel: "Mac 1")

        let mac2Dir = rootDir.appendingPathComponent("mac2_store", isDirectory: true)
        let mac2LogURL = mac2Dir.appendingPathComponent("events.jsonl")
        let mac2SyncStateURL = mac2Dir.appendingPathComponent("sync-state.json")
        let mac2Store = try EventStore(fileURL: mac2LogURL)
        let mac2Service = NoteService(store: mac2Store, deviceLabel: "Mac 2")

        let mac1ShardURL = sharedSyncDir.appendingPathComponent("events-mac-1.jsonl")
        let mac2ShardURL = sharedSyncDir.appendingPathComponent("events-mac-2.jsonl")

        // 1. Mac 1 creates a note
        _ = try mac1Service.createNote(title: "Note from Mac 1", body: "authored on Mac 1", source: "antigravity")

        // 2. Mac 1 publishes its shard
        let pub1 = try ShardPublisher.publishLocalEvents(
            eventLogURL: mac1LogURL,
            to: mac1ShardURL,
            syncStateURL: mac1SyncStateURL,
            ownDeviceLabel: "Mac 1",
            isLocallyOriginated: { $0.device == nil || $0.device == "Mac 1" }
        )
        XCTAssertEqual(pub1, 1)

        // 3. Mac 2 imports Mac 1's shard into its local store
        let importReceipt = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: mac2Store,
            syncStateURL: mac2SyncStateURL,
            ownShardFilename: "events-mac-2.jsonl"
        )
        XCTAssertEqual(importReceipt.eventsAppended, 1)
        mac2Service.rebuild()

        // 4. Mac 2 creates its own note
        _ = try mac2Service.createNote(title: "Note from Mac 2", body: "authored on Mac 2", source: "antigravity")

        // 5. Mac 2 publishes to its own shard
        let pub2 = try ShardPublisher.publishLocalEvents(
            eventLogURL: mac2LogURL,
            to: mac2ShardURL,
            syncStateURL: mac2SyncStateURL,
            ownDeviceLabel: "Mac 2",
            isLocallyOriginated: { $0.device == nil || $0.device == "Mac 2" }
        )
        XCTAssertEqual(pub2, 1, "Mac 2 must publish ONLY its own locally originated event, NOT Mac 1's imported event")

        let mac2ShardText = try String(contentsOf: mac2ShardURL, encoding: .utf8)
        XCTAssertTrue(mac2ShardText.contains("Note from Mac 2"))
        XCTAssertFalse(mac2ShardText.contains("Note from Mac 1"), "Mac 2 re-published Mac 1's imported event — sync loop between Macs")
    }

    /// Verifies that deleting a capture on-device before Mac retrieves it purges it locally and removes it from the published shard.
    func testDeleteBeforeMacImportExcludesNoteFromPublishedShard() throws {
        let phoneShardFilename = "events-phone-del.jsonl"
        let phoneShardURL = sharedSyncDir.appendingPathComponent(phoneShardFilename)
        let writer = ShardWriter(shardFileURL: phoneShardURL, deviceLabel: "iPhone")

        // 1. Phone captures two voice notes
        let capture1 = try writer.writeCapture(transcript: "Keep this thought")
        let capture2 = try writer.writeCapture(transcript: "Delete this secret before Mac sees it")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try phoneStore.appendRaw(encoder.encode(capture1))
        try phoneStore.appendRaw(encoder.encode(capture2))

        // 2. Initial publish -> publishes 2 events to phone shard
        _ = try ShardPublisher.publishLocalEvents(
            eventLogURL: phoneLogURL,
            to: phoneShardURL,
            syncStateURL: phoneSyncStateURL,
            ownDeviceLabel: "iPhone",
            isLocallyOriginated: { $0.device == "iPhone" }
        )
        let initialShardText = try String(contentsOf: phoneShardURL, encoding: .utf8)
        XCTAssertTrue(initialShardText.contains("Delete this secret"))

        // 3. User deletes capture 2 before Mac imports
        try TrashService.purge(noteIDs: [capture2.noteId], logURL: phoneLogURL)
        if FileManager.default.fileExists(atPath: phoneShardURL.path) {
            try FileManager.default.removeItem(at: phoneShardURL)
        }

        // Reset cursor & re-publish
        var phoneState = SyncState.load(from: phoneSyncStateURL)
        phoneState.publishedCursor = nil
        try phoneState.save(to: phoneSyncStateURL)

        _ = try ShardPublisher.publishLocalEvents(
            eventLogURL: phoneLogURL,
            to: phoneShardURL,
            syncStateURL: phoneSyncStateURL,
            ownDeviceLabel: "iPhone",
            isLocallyOriginated: { $0.device == "iPhone" }
        )

        // 4. Verify phone shard on disk no longer contains capture 2
        let updatedShardText = try String(contentsOf: phoneShardURL, encoding: .utf8)
        XCTAssertTrue(updatedShardText.contains("Keep this thought"))
        XCTAssertFalse(updatedShardText.contains("Delete this secret"), "deleted capture must be removed from published shard before Mac retrieves it")

        // 5. Mac imports phone shard -> Mac receives ONLY capture 1!
        let macReceipt = try ShardImporter.importShards(
            from: sharedSyncDir,
            into: macStore,
            syncStateURL: macSyncStateURL,
            ownShardFilename: "events-mac-111.jsonl"
        )
        XCTAssertEqual(macReceipt.eventsAppended, 1)
        macService.rebuild()

        let macNotes = try macService.listNotes()
        XCTAssertTrue(macNotes.contains { $0.id == capture1.noteId })
        XCTAssertFalse(macNotes.contains { $0.id == capture2.noteId })
    }
}
