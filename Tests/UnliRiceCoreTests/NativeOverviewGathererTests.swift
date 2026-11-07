import XCTest
@testable import UnliRiceCore

final class NativeOverviewGathererTests: XCTestCase {
    func testEmptyRootsProduceEmptyLocalOverview() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = NoteService(store: try EventStore(fileURL: folder.appendingPathComponent("events.jsonl")))
        let output = try NativeOverviewGatherer.gather(roots: [], service: service, corpusFolder: folder, identity: DeviceIdentity(id: "1", label: "Mac"))
        XCTAssertTrue(output.report.projects.isEmpty)
        XCTAssertTrue(output.overview.projects.isEmpty)
        XCTAssertTrue(output.receivedCaptureIDs.isEmpty)
    }

    func testValidEmptyDirectoryProducesEmptyOverview() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let root = folder.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let service = NoteService(store: try EventStore(fileURL: folder.appendingPathComponent("events.jsonl")))
        let output = try NativeOverviewGatherer.gather(roots: [root], service: service, corpusFolder: folder, identity: DeviceIdentity(id: "1", label: "Mac"))
        XCTAssertTrue(output.report.projects.isEmpty)
    }

    func testIncompleteCaptureIsExcludedAndWarningIsPublished() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try EventStore(fileURL: folder.appendingPathComponent("events.jsonl")), service = NoteService(store: store)
        let healthy = try service.createNote(title: "Healthy", body: "", source: "human")
        _ = try service.tagNote(id: healthy.id, tag: CaptureContext.captureTag, source: "human")
        let incomplete = UUID(), create = Event(noteId: incomplete, source: "human", kind: .created, title: "Incomplete", causalParents: [])
        let tag = Event(noteId: incomplete, source: "human", kind: .tagged, tag: CaptureContext.captureTag, causalParents: [create.id])
        let pending = Event(noteId: incomplete, source: "human", kind: .appended, text: "missing", causalParents: [UUID()])
        try store.append(create); try store.append(tag); try store.append(pending)
        let output = try NativeOverviewGatherer.gather(roots: [], service: service, corpusFolder: folder, identity: DeviceIdentity(id: "1", label: "Mac"))
        XCTAssertEqual(output.receivedCaptureIDs, [healthy.id])
        XCTAssertTrue(output.report.issues.contains { $0.contains("1 note is waiting") })
        XCTAssertTrue(output.overview.issues.contains { $0.contains("1 note is waiting") })
    }

    func testMissingRootDoesNotProduceFreshOverview() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = NoteService(store: try EventStore(fileURL: folder.appendingPathComponent("events.jsonl")))
        XCTAssertThrowsError(try NativeOverviewGatherer.gather(roots: [folder.appendingPathComponent("missing")], service: service, corpusFolder: folder, identity: DeviceIdentity(id: "1", label: "Mac")))
    }
}
