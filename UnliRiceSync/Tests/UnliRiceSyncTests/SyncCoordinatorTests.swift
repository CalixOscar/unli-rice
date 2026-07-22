import XCTest
import SwiftData
import UnliRiceCore
@testable import UnliRiceSync

// Needs macOS 14 / a real SwiftData+CloudKit-capable SDK to run — this
// environment has neither, so these are written but never executed. Verify
// on the Mac before trusting them. `cloudKitDatabase: .none` here on purpose:
// these exercise SyncCoordinator's merge logic against a local, in-memory
// SwiftData store, not real CloudKit — there is no substitute for also
// testing against two real devices signed into the same iCloud account, which
// no unit test can do.
final class SyncCoordinatorTests: XCTestCase {
    var tempURL: URL!
    var store: EventStore!

    override func setUpWithError() throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-sync-tests-\(UUID().uuidString)")
            .appendingPathComponent("events.jsonl")
        store = try EventStore(fileURL: tempURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempURL.deletingLastPathComponent())
    }

    private func makeInMemoryCoordinator() throws -> SyncCoordinator {
        let schema = Schema([SyncEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return SyncCoordinator(container: container, store: store)
    }

    func testPushSendsLocalEventsToTheStore() async throws {
        try store.append(Event(noteId: UUID(), source: "claude", kind: .created, title: "Local note", text: "body"))
        let coordinator = try makeInMemoryCoordinator()

        try await coordinator.sync()

        // Round-tripping through a second coordinator sharing the same
        // container would be the real assertion; here we at least assert sync
        // doesn't throw and the local log is unchanged (nothing to pull yet).
        let events = try store.readAll()
        XCTAssertEqual(events.count, 1)
    }

    func testSyncTwiceInARowIsIdempotent() async throws {
        try store.append(Event(noteId: UUID(), source: "claude", kind: .created, title: "Note", text: "body"))
        let coordinator = try makeInMemoryCoordinator()

        try await coordinator.sync()
        try await coordinator.sync()

        // A second push must not re-insert the same event id as a duplicate
        // SyncEvent — this is the core correctness property, since a real
        // CloudKit round trip will call sync() far more than once.
        let events = try store.readAll()
        XCTAssertEqual(events.count, 1)
    }

    func testPullFoldsRemoteEventsIntoTheLocalLogInTimestampOrder() async throws {
        let schema = Schema([SyncEvent.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])

        // Simulate "another device already wrote here" by inserting directly,
        // bypassing this device's local EventStore entirely.
        let context = ModelContext(container)
        let noteId = UUID()
        let older = Event(noteId: noteId, timestamp: Date(timeIntervalSince1970: 1000), source: "gemini", kind: .created, title: "From another device", text: "first")
        let newer = Event(noteId: noteId, timestamp: Date(timeIntervalSince1970: 2000), source: "gemini", kind: .appended, text: "second")
        context.insert(SyncEvent(event: newer))
        context.insert(SyncEvent(event: older))
        try context.save()

        let coordinator = SyncCoordinator(container: container, store: store)
        try await coordinator.sync()

        let events = try store.readAll()
        XCTAssertEqual(events.map(\.id), [older.id, newer.id], "pulled events must land in timestamp order regardless of insertion order")
    }
}
