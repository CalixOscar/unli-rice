import XCTest
@testable import UnliRiceCore

final class PhoneSyncScopeTests: XCTestCase {
    func testMigrationPreservesOffsetsAndSwitchingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old"), new = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        let oldShard = old.appendingPathComponent("events-mac-1.jsonl")
        let writer = ShardWriter(shardFileURL: oldShard, deviceLabel: "Mac")
        _ = try writer.writeCaptureEvents(text: "old")
        _ = try ShardWriter(shardFileURL: new.appendingPathComponent("events-mac-1.jsonl"), deviceLabel: "Mac").writeCaptureEvents(text: "new")
        let log = root.appendingPathComponent("phone/events.jsonl"), store = try EventStore(fileURL: log)
        let stateURL = SyncState.url(besideEventLog: log)
        XCTAssertEqual(try ShardImporter.importShards(from: old, into: store, syncStateURL: stateURL).eventsAppended, 1)
        var legacy = SyncState.load(from: stateURL)
        legacy.publishedCursor = FeedCursor(offset: 44)
        try legacy.save(to: stateURL)
        let oldOffset = try XCTUnwrap(legacy.shardCursors["events-mac-1.jsonl"])
        try SyncState.prepareScopedImports(at: stateURL, currentNamespace: old.path)
        let migrated = SyncState.load(from: stateURL)
        XCTAssertEqual(migrated.scopedImportCursorsVersion, 1)
        XCTAssertEqual(migrated.publishedCursor, FeedCursor(offset: 44))
        XCTAssertEqual(migrated.shardCursors["events-mac-1.jsonl"], oldOffset)
        XCTAssertEqual(migrated.shardCursors["\(old.path)/events-mac-1.jsonl"], oldOffset)
        try SyncState.prepareScopedImports(at: stateURL, currentNamespace: new.path)
        XCTAssertNil(SyncState.load(from: stateURL).shardCursors["\(new.path)/events-mac-1.jsonl"])
        XCTAssertEqual(try ShardImporter.importShards(from: new, into: store, syncStateURL: stateURL, cursorNamespace: new.path).eventsAppended, 1)
        _ = try writer.writeCaptureEvents(text: "old later")
        XCTAssertEqual(try ShardImporter.importShards(from: old, into: store, syncStateURL: stateURL, cursorNamespace: old.path).eventsAppended, 1)
        XCTAssertEqual(try store.readAll().count, 3)
    }
    func testOldJSONAndExistingScopedCursor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        try Data(#"{"shardCursors":{"events-mac.jsonl":{"opaque":"9"},"/old/events-mac.jsonl":{"opaque":"5"}},"publishedCursor":{"opaque":"12"}}"#.utf8).write(to: url)
        XCTAssertNil(try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: url)).scopedImportCursorsVersion)
        try SyncState.prepareScopedImports(at: url, currentNamespace: "/old")
        let state = try JSONDecoder().decode(SyncState.self, from: Data(contentsOf: url))
        XCTAssertEqual(state.shardCursors["/old/events-mac.jsonl"], FeedCursor(offset: 5))
        XCTAssertEqual(state.publishedCursor, FeedCursor(offset: 12))
    }
    func testCorruptAndUnknownVersionRefusedAndPrivateDoesNotAdopt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("state.json")
        let corrupt = Data("bad".utf8); try corrupt.write(to: url)
        XCTAssertThrowsError(try SyncState.prepareScopedImports(at: url, currentNamespace: "/old"))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        try SyncState(shardCursors: ["events-x.jsonl": FeedCursor(offset: 3)], scopedImportCursorsVersion: 2).save(to: url)
        XCTAssertThrowsError(try SyncState.prepareScopedImports(at: url, currentNamespace: "/old"))
        try SyncState(shardCursors: ["events-x.jsonl": FeedCursor(offset: 3)]).save(to: url)
        try SyncState.prepareScopedImports(at: url, currentNamespace: nil)
        try SyncState.prepareScopedImports(at: url, currentNamespace: "/new")
        let state = SyncState.load(from: url)
        XCTAssertEqual(state.shardCursors.count, 1)
        XCTAssertEqual(state.scopedImportCursorsVersion, 1)
    }
}
