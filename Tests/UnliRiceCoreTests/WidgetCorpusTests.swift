import XCTest
@testable import UnliRiceCore

final class WidgetCorpusTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WidgetCorpusTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testMissingLogReturnsLogMissingAndCreatesNoFile() throws {
        let missingURL = tempDir.appendingPathComponent("nonexistent-events.jsonl")

        // 1. EventStore(readingExisting:) throws .logMissing and does not create the file
        XCTAssertThrowsError(try EventStore(readingExisting: missingURL)) { error in
            XCTAssertEqual(error as? WidgetCorpus.Unreadable, .logMissing)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingURL.path))

        // 2. WidgetCorpus.resolve with missing log returns .logMissing and creates no file
        let container = tempDir.appendingPathComponent("group-container", isDirectory: true)
        let unliRiceDir = container.appendingPathComponent("Unli Rice", isDirectory: true)
        try FileManager.default.createDirectory(at: unliRiceDir, withIntermediateDirectories: true)

        let result = WidgetCorpus.resolve(
            environment: [:],
            containerURL: container,
            settingsURL: nil
        )

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .logMissing)
        case .success:
            XCTFail("Expected .logMissing when events.jsonl does not exist")
        }

        let expectedLog = unliRiceDir.appendingPathComponent("events.jsonl")
        XCTAssertFalse(FileManager.default.fileExists(atPath: expectedLog.path))
    }

    func testUndecodableSettingsReturnsSettingsUnreadable() throws {
        let badSettingsURL = tempDir.appendingPathComponent("agent.json")
        try "not valid json at all".write(to: badSettingsURL, atomically: true, encoding: .utf8)

        // AgentSettings.loadStrict throws
        XCTAssertThrowsError(try AgentSettings.loadStrict(from: badSettingsURL))

        let container = tempDir.appendingPathComponent("group-container", isDirectory: true)
        let result = WidgetCorpus.resolve(
            environment: [:],
            containerURL: container,
            settingsURL: badSettingsURL
        )

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .settingsUnreadable)
        case .success:
            XCTFail("Expected .settingsUnreadable for malformed agent.json")
        }
    }

    func testFolderBookmarkThatFailsReturnsFolderFailedNeverDefault() throws {
        let settingsURL = tempDir.appendingPathComponent("agent.json")
        var settings = AgentSettings()
        settings.dataFolderBookmark = Data([0xDE, 0xAD, 0xBE, 0xEF])
        settings.dataFolderPath = "/path/to/custom/notes"
        try settings.save(to: settingsURL)

        let container = tempDir.appendingPathComponent("group-container", isDirectory: true)
        let defaultDir = container.appendingPathComponent("Unli Rice", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultDir, withIntermediateDirectories: true)
        let defaultLog = defaultDir.appendingPathComponent("events.jsonl")
        try "".write(to: defaultLog, atomically: true, encoding: .utf8)

        let result = WidgetCorpus.resolve(
            environment: [:],
            containerURL: container,
            settingsURL: settingsURL,
            resolveBookmark: { _ in nil }, // bookmark fails to resolve
            startAccess: { _ in false }
        )

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .folderFailed, "Must fail with .folderFailed, never fall back to default")
        case .success:
            XCTFail("Must not fall back to default when bookmark fails")
        }
    }

    func testLogWithCorruptLineIncrementsSkippedLines() throws {
        let logURL = tempDir.appendingPathComponent("events.jsonl")

        let validEvent1 = Event(
            noteId: UUID(),
            timestamp: Date(),
            source: "test",
            kind: .created,
            title: "Note 1",
            text: "Body 1"
        )
        let validEvent2 = Event(
            noteId: UUID(),
            timestamp: Date(),
            source: "test",
            kind: .created,
            title: "Note 2",
            text: "Body 2"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let line1 = try encoder.encode(validEvent1)
        let line2 = "this is a corrupt event line that will fail decoding".data(using: .utf8)!
        let line3 = try encoder.encode(validEvent2)

        var logData = Data()
        logData.append(line1)
        logData.append(UInt8(ascii: "\n"))
        logData.append(line2)
        logData.append(UInt8(ascii: "\n"))
        logData.append(line3)
        logData.append(UInt8(ascii: "\n"))
        try logData.write(to: logURL)

        let store = try EventStore(readingExisting: logURL)
        XCTAssertEqual(store.skippedLines, 0)

        let batch = try store.read(from: EventStoreCursor(offset: 0))
        XCTAssertEqual(batch.events.count, 2)
        XCTAssertEqual(store.skippedLines, 1)
    }

    func testNoGroupContainerReturnsNoGroupContainer() {
        let result = WidgetCorpus.resolve(
            environment: [:],
            containerURL: nil,
            settingsURL: nil
        )

        switch result {
        case .failure(let error):
            XCTAssertEqual(error, .noGroupContainer)
        case .success:
            XCTFail("Expected .noGroupContainer when containerURL is nil")
        }
    }
}
