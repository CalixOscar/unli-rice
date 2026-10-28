import XCTest
@testable import UnliRiceCore

/// The two background Extras switches: what they default to in each situation,
/// and that "off" really skips the work.
final class ExtrasSettingsTests: XCTestCase {
    var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-extras-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Counts calls; the janitor must not make any when duplicates are off.
    private final class SpySimilarity: SimilarityProvider, @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        var calls: Int { lock.lock(); defer { lock.unlock() }; return _calls }
        var calibration: SimilarityCalibration { TokenOverlapSimilarity().calibration }
        func similarity(_ a: String, _ b: String) -> Double {
            lock.lock(); _calls += 1; lock.unlock()
            return TokenOverlapSimilarity().similarity(a, b)
        }
    }

    // (a)
    func testSettingsJSONWithoutTheKeysDecodesToOn() throws {
        let json = #"{"routinesEnabled": true, "autonomyLevel": 2, "scanRootPaths": ["/tmp/x"], "monthlyReviewEnabled": false}"#
        let settings = try JSONDecoder().decode(AgentSettings.self, from: Data(json.utf8))
        XCTAssertTrue(settings.bulkImportEnabled)
        XCTAssertTrue(settings.duplicateDetectionEnabled)
        XCTAssertTrue(settings.routinesEnabled)
    }

    // (b)
    func testExplicitFalseSurvivesSaveAndLoad() throws {
        let url = directory.appendingPathComponent("agent.json")
        try AgentSettings(bulkImportEnabled: false, duplicateDetectionEnabled: false).save(to: url)
        let loaded = AgentSettings.load(from: url)
        XCTAssertFalse(loaded.bulkImportEnabled)
        XCTAssertFalse(loaded.duplicateDetectionEnabled)

        try AgentSettings(bulkImportEnabled: true, duplicateDetectionEnabled: true).save(to: url)
        let loadedOn = AgentSettings.load(from: url)
        XCTAssertTrue(loadedOn.bulkImportEnabled)
        XCTAssertTrue(loadedOn.duplicateDetectionEnabled)
    }

    // (c)
    func testMissingOrCorruptFileLoadsAsOff() throws {
        let missing = directory.appendingPathComponent("nope.json")
        let fromMissing = AgentSettings.load(from: missing)
        XCTAssertFalse(fromMissing.bulkImportEnabled)
        XCTAssertFalse(fromMissing.duplicateDetectionEnabled)

        let corrupt = directory.appendingPathComponent("corrupt.json")
        try Data("{ not json".utf8).write(to: corrupt)
        let fromCorrupt = AgentSettings.load(from: corrupt)
        XCTAssertFalse(fromCorrupt.bulkImportEnabled)
        XCTAssertFalse(fromCorrupt.duplicateDetectionEnabled)
    }

    // (d)
    func testToggleSurvivesTwoLaunches() throws {
        let url = directory.appendingPathComponent("agent.json")
        // Launch 1: the user turns bulk import off and leaves duplicates on.
        var first = AgentSettings(bulkImportEnabled: true, duplicateDetectionEnabled: true)
        first.bulkImportEnabled = false
        try first.save(to: url)

        // Launch 2: loads, saves again without touching the switches.
        let second = AgentSettings.load(from: url)
        XCTAssertFalse(second.bulkImportEnabled)
        XCTAssertTrue(second.duplicateDetectionEnabled)
        try second.save(to: url)

        // Launch 3: still the same.
        let third = AgentSettings.load(from: url)
        XCTAssertFalse(third.bulkImportEnabled)
        XCTAssertTrue(third.duplicateDetectionEnabled)
    }

    // (e)
    func testPipelinesSkipLocalFilesWhenBulkImportIsOff() throws {
        let root = directory.appendingPathComponent("scan")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let claude = directory.appendingPathComponent("claude")
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)

        let off = Pipelines.standard(scanRoots: [root], claudeProjectsDirectory: claude, includeLocalFiles: false)
        XCTAssertFalse(off.contains { $0 is LocalFileImporter })
        XCTAssertTrue(off.contains { $0 is ClaudeSessionImporter }, "Claude session import is not an extra")

        let on = Pipelines.standard(scanRoots: [root], claudeProjectsDirectory: claude)
        XCTAssertTrue(on.contains { $0 is LocalFileImporter })
    }

    // (f)
    func testDuplicateDetectionOffNeverCallsTheProviderButStillTags() throws {
        let store = try EventStore(fileURL: directory.appendingPathComponent("events.jsonl"))
        let service = NoteService(store: store)
        let a = try service.createNote(title: "Billing retries", body: "x", source: "claude")
        try service.tagNote(id: a.id, tag: "billing", source: "claude")
        let b = try service.createNote(title: "Billing webhooks", body: "y", source: "claude")
        try service.tagNote(id: b.id, tag: "billing", source: "claude")
        try service.createNote(title: "Billing edge cases", body: "z", source: "claude")
        try service.createNote(title: "Billing webhooks", body: "dupe", source: "gemini")
        let notes = try service.listNotes()

        let spy = SpySimilarity()
        let off = Janitor.scan(
            notes: notes,
            config: JanitorConfig(autonomy: .balanced, detectsDuplicates: false),
            similarity: spy
        )
        XCTAssertEqual(spy.calls, 0)
        XCTAssertTrue(off.contains { if case .addTag = $0.kind { return true } else { return false } })
        XCTAssertFalse(off.contains { if case .possibleDuplicate = $0.kind { return true } else { return false } })

        // Control: with it on, the same notes do reach the provider.
        let onSpy = SpySimilarity()
        let on = Janitor.scan(notes: notes, config: JanitorConfig(autonomy: .balanced), similarity: onSpy)
        XCTAssertGreaterThan(onSpy.calls, 0)
        XCTAssertTrue(on.contains { if case .possibleDuplicate = $0.kind { return true } else { return false } })
    }
}
