import XCTest
@testable import UnliRiceCore

final class CaptureSyncBridgeTests: XCTestCase {
    func testRoundTripAndIndependentDestinationCursors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("shared"), other = root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let macLog = root.appendingPathComponent("mac/events.jsonl"), phoneLog = root.appendingPathComponent("phone/events.jsonl")
        try FileManager.default.createDirectory(at: macLog.deletingLastPathComponent(), withIntermediateDirectories: true)
        let phoneStore = try EventStore(fileURL: phoneLog)
        let writer = ShardWriter(shardFileURL: shared.appendingPathComponent("events-phone-1.jsonl"), deviceLabel: "Phone")
        let batch = try writer.writeCaptureEvents(text: "idea", tags: ["capture", "capture-pending", "project"])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        for event in batch { try phoneStore.appendRaw(try encoder.encode(event)) }
        let identity = DeviceIdentity(id: "1", label: "Mac")
        let first = try CaptureSyncBridge.synchronize(eventLogURL: macLog, sharedFolder: shared, identity: identity)
        XCTAssertEqual(first.eventsImported, 4)
        let macStore = try EventStore(fileURL: macLog)
        let mac = NoteService(store: macStore, deviceLabel: identity.label)
        XCTAssertTrue(try mac.listNotes().contains(where: CaptureContext.isPending))
        let id = batch[0].noteId
        _ = try mac.tagNote(id: id, tag: "todo", source: "codex")
        _ = try mac.untagNote(id: id, tag: "capture-pending", source: "codex")
        let localState = SyncState.url(besideEventLog: macLog)
        _ = try ShardPublisher.publishLocalEvents(eventLogURL: macLog, to: root.appendingPathComponent("mac/local.jsonl"), syncStateURL: localState, ownDeviceLabel: "Mac", isLocallyOriginated: { $0.device == nil || $0.device == "Mac" })
        let second = try CaptureSyncBridge.synchronize(eventLogURL: macLog, sharedFolder: shared, identity: identity)
        XCTAssertEqual(second.eventsPublished, 2)
        XCTAssertEqual(try CaptureSyncBridge.synchronize(eventLogURL: macLog, sharedFolder: shared, identity: identity).eventsImported, 0)
        XCTAssertEqual(try macStore.readAll().count, 6)
        let phoneState = SyncState.url(besideEventLog: phoneLog)
        _ = try ShardImporter.importShards(from: shared, into: phoneStore, syncStateURL: phoneState, ownShardFilename: "events-phone-1.jsonl", requiringShardNaming: true)
        let phone = NoteService(store: phoneStore)
        let updated = try XCTUnwrap(phone.listNotes().first)
        XCTAssertTrue(updated.tags.contains("todo")); XCTAssertFalse(updated.tags.contains("capture-pending"))
        XCTAssertEqual(try CaptureReceiptFile.readAll(fromFolder: shared).first?.receivedNoteIDs, [id])
        XCTAssertEqual(try CaptureSyncBridge.synchronize(eventLogURL: macLog, sharedFolder: other, identity: identity).eventsPublished, 2)
        let state = SyncState.load(from: localState)
        XCTAssertNotNil(state.cursor(for: "\(shared.path)/events-phone-1.jsonl"))
    }
    func testCorruptStateAndShardAreRefused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("shared"), mac = root.appendingPathComponent("mac")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
        let log = mac.appendingPathComponent("events.jsonl")
        let state = SyncState.url(besideEventLog: log)
        try Data("broken".utf8).write(to: state)
        XCTAssertThrowsError(try CaptureSyncBridge.synchronize(eventLogURL: log, sharedFolder: shared, identity: .init(id: "1", label: "Mac")))
        XCTAssertEqual(try Data(contentsOf: state), Data("broken".utf8))
        try FileManager.default.removeItem(at: state)
        try Data("bad\n".utf8).write(to: shared.appendingPathComponent("events-phone-1.jsonl"))
        XCTAssertThrowsError(try CaptureSyncBridge.synchronize(eventLogURL: log, sharedFolder: shared, identity: .init(id: "1", label: "Mac")))
    }
    func testImportOnlyKeepsNamespaceAndDoesNotPublish() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("scan"), mac = root.appendingPathComponent("mac")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
        let log = mac.appendingPathComponent("events.jsonl")
        let shard = folder.appendingPathComponent("events-phone-1.jsonl")
        _ = try ShardWriter(shardFileURL: shard, deviceLabel: "Phone").writeCaptureEvents(text: "idea")
        let result = try CaptureSyncBridge.importOnly(eventLogURL: log, from: folder, ownShardFilename: nil, cursorNamespace: folder.path)
        XCTAssertEqual(result.eventsAppended, 1)
        XCTAssertNotNil(SyncState.load(from: SyncState.url(besideEventLog: log)).cursor(for: "\(folder.path)/events-phone-1.jsonl"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["events-phone-1.jsonl"])
        XCTAssertEqual(try CaptureSyncBridge.importOnly(eventLogURL: log, from: folder, ownShardFilename: nil, cursorNamespace: folder.path).eventsAppended, 0)
    }

    func testConcurrentImportsKeepBothCursors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let mac = root.appendingPathComponent("mac")
        try FileManager.default.createDirectory(at: mac, withIntermediateDirectories: true)
        let folders = [root.appendingPathComponent("a"), root.appendingPathComponent("b")]
        for (index, folder) in folders.enumerated() {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            _ = try ShardWriter(shardFileURL: folder.appendingPathComponent("events-phone-\(index).jsonl"), deviceLabel: "Phone").writeCaptureEvents(text: "idea")
        }
        let log = mac.appendingPathComponent("events.jsonl")
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do { _ = try CaptureSyncBridge.importOnly(eventLogURL: log, from: folders[index], ownShardFilename: nil, cursorNamespace: folders[index].path) }
            catch { XCTFail("Import failed: \(error)") }
        }
        let state = SyncState.load(from: SyncState.url(besideEventLog: log))
        for (index, folder) in folders.enumerated() { XCTAssertNotNil(state.cursor(for: "\(folder.path)/events-phone-\(index).jsonl")) }
        XCTAssertEqual(try EventStore(fileURL: log).readAll().count, 2)
    }

    func testNestedLockTimesOutAndOuterReleases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("events.jsonl")
        var innerRan = false
        let start = ContinuousClock.now
        try CaptureSyncBridge.withLock(eventLogURL: log) {
            XCTAssertThrowsError(try CaptureSyncBridge.withLock(eventLogURL: log) { innerRan = true }) { error in
                guard case CaptureSyncBridge.BridgeError.lockUnavailable = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        XCTAssertFalse(innerRan)
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
        XCTAssertNoThrow(try CaptureSyncBridge.withLock(eventLogURL: log) {})
    }

}
