import XCTest
@testable import UnliRiceCore

final class VaultSnapshotTests: XCTestCase {
    private var root: URL!
    private var logURL: URL!
    private var store: EventStore!
    private var service: NoteService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        logURL = root.appendingPathComponent("events.jsonl")
        store = try EventStore(fileURL: logURL)
        service = NoteService(store: store)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSnapshotCapturesAndVerifiesVaultFiles() throws {
        _ = try service.createNote(title: "Remember", body: "everything", source: "human")
        try Data("rules".utf8).write(to: root.appendingPathComponent(HouseRulesStateStore.filename))
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: raw.appendingPathComponent("source.txt"))

        let snapshot = try VaultSnapshotService.create(logURL: logURL)

        XCTAssertEqual(snapshot.eventCount, 1)
        XCTAssertEqual(snapshot.noteCount, 1)
        XCTAssertTrue(snapshot.files.contains { $0.relativePath == "events.jsonl" })
        XCTAssertTrue(snapshot.files.contains { $0.relativePath == "house-rules.json" })
        XCTAssertTrue(snapshot.files.contains { $0.relativePath == "raw/source.txt" })
        XCTAssertNoThrow(try VaultSnapshotService.verify(snapshot, logURL: logURL))
        let listed = try XCTUnwrap(VaultSnapshotService.list(logURL: logURL).first)
        XCTAssertEqual(listed.id, snapshot.id)
        XCTAssertEqual(listed.eventCount, snapshot.eventCount)
        XCTAssertEqual(listed.files, snapshot.files)
    }

    func testTamperedSnapshotFailsVerification() throws {
        _ = try service.createNote(title: "Remember", body: "everything", source: "human")
        let snapshot = try VaultSnapshotService.create(logURL: logURL)
        let snapshotLog = VaultSnapshotService.snapshotURL(snapshot, forLog: logURL)
            .appendingPathComponent(VaultSnapshotService.eventLogFilename)
        try Data("tampered".utf8).write(to: snapshotLog, options: .atomic)

        XCTAssertThrowsError(try VaultSnapshotService.verify(snapshot, logURL: logURL)) { error in
            XCTAssertEqual(error as? VaultSnapshotService.SnapshotError, .verificationFailed("events.jsonl"))
        }
    }

    func testRestoreAppendsOnlyMissingEventsAndRestoresMissingRawFiles() throws {
        let recoverable = try service.createNote(title: "Recoverable", body: "first", source: "human")
        try service.appendToNote(id: recoverable.id, text: "second", source: "codex")
        _ = try service.createNote(title: "Always here", body: "safe", source: "human")
        let raw = root.appendingPathComponent("raw", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        try Data("source".utf8).write(to: raw.appendingPathComponent("source.txt"))
        let snapshot = try VaultSnapshotService.create(logURL: logURL)

        try TrashService.purge(noteIDs: [recoverable.id], logURL: logURL)
        try FileManager.default.removeItem(at: raw.appendingPathComponent("source.txt"))
        XCTAssertNil(try service.getNote(id: recoverable.id))

        let receipt = try VaultSnapshotService.restore(snapshot, logURL: logURL, into: store)
        XCTAssertEqual(receipt.eventsAppended, 2)
        XCTAssertEqual(receipt.rawFilesRestored, 1)
        XCTAssertEqual(try service.getNote(id: recoverable.id)?.body, "first\n\n---\nsecond")

        let second = try VaultSnapshotService.restore(snapshot, logURL: logURL, into: store)
        XCTAssertEqual(second.eventsAppended, 0)
        XCTAssertEqual(second.rawFilesRestored, 0)
    }
}
