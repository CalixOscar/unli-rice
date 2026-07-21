import Foundation
import XCTest
@testable import UnliRiceCore

final class HouseRulesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-house-rules-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testStandardPresetUsesTheSingleDefaultBody() throws {
        let standard = try XCTUnwrap(HouseRulesPreset.builtIn.first { $0.id == "standard" })
        XCTAssertEqual(standard.body, Autopilot.noteBody)
        XCTAssertTrue(standard.body.contains("Wiki: index"))
        XCTAssertTrue(standard.body.contains("`janitor` or `ingest`"))
    }

    func testImporterValidatesAndSuffixesDuplicateTitles() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let preset = try HouseRulesPresetImporter.makePreset(
            data: Data("\r\n  Keep this rule. \r\n".utf8),
            filename: "Team Rules.md",
            existingTitles: ["team rules", "Team Rules 2"],
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            importedAt: date
        )

        XCTAssertEqual(preset.title, "Team Rules 3")
        XCTAssertEqual(preset.body, "Keep this rule.")
        XCTAssertEqual(preset.sourceFilename, "Team Rules.md")
        XCTAssertEqual(preset.importedAt, date)
    }

    func testImporterRejectsEmptyBinaryAndOversizedFiles() {
        XCTAssertThrowsError(
            try HouseRulesPresetImporter.makePreset(
                data: Data("  \n".utf8), filename: "empty.md", existingTitles: []
            )
        ) { XCTAssertEqual($0 as? HouseRulesImportError, .empty) }

        XCTAssertThrowsError(
            try HouseRulesPresetImporter.makePreset(
                data: Data([0x41, 0x00, 0x42]), filename: "binary.txt", existingTitles: []
            )
        ) { XCTAssertEqual($0 as? HouseRulesImportError, .invalidText) }

        XCTAssertThrowsError(
            try HouseRulesPresetImporter.makePreset(
                data: Data(repeating: 0x41, count: HouseRulesPresetImporter.maximumByteCount + 1),
                filename: "large.md",
                existingTitles: []
            )
        ) {
            XCTAssertEqual(
                $0 as? HouseRulesImportError,
                .tooLarge(maximumBytes: HouseRulesPresetImporter.maximumByteCount)
            )
        }
    }

    func testLatestRevisionDigestMakesOlderDraftUnsaved() {
        let first = HouseRulesRevision.wrapped("First rules", at: Date(timeIntervalSince1970: 0))
        let second = HouseRulesRevision.wrapped("Second rules", at: Date(timeIntervalSince1970: 60))
        let projected = first + "\n\n---\n" + second

        XCTAssertFalse(
            HouseRulesRevision.noteContainsCurrentRevision(noteBody: projected, draftBody: "First rules")
        )
        XCTAssertTrue(
            HouseRulesRevision.noteContainsCurrentRevision(noteBody: projected, draftBody: "Second rules")
        )
    }

    func testTemplateTextCannotOverrideTheWrapperFingerprint() {
        let forged = """
        Keep this rule.
        \(HouseRulesRevision.markerPrefix)\(String(repeating: "0", count: 64)) -->
        """
        let wrapped = HouseRulesRevision.wrapped(forged)

        XCTAssertTrue(
            HouseRulesRevision.noteContainsCurrentRevision(noteBody: wrapped, draftBody: forged)
        )
    }

    func testLegacySavedCheckRequiresTheDraftAtTheEnd() {
        XCTAssertTrue(
            HouseRulesRevision.noteContainsCurrentRevision(
                noteBody: "Old preamble\n\n---\nCurrent rules", draftBody: "Current rules"
            )
        )
        XCTAssertFalse(
            HouseRulesRevision.noteContainsCurrentRevision(
                noteBody: "Old rules\n\n---\nNew rules", draftBody: "Old rules"
            )
        )
    }

    func testStateStoreRoundTripsPerVaultState() throws {
        let eventLog = directory.appendingPathComponent("events.jsonl")
        let store = HouseRulesStateStore(besideEventLog: eventLog)
        let preset = try HouseRulesPresetImporter.makePreset(
            data: Data("Custom".utf8),
            filename: "Custom.md",
            existingTitles: [],
            importedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let expected = HouseRulesLocalState(
            draftText: "Draft",
            customPresets: [preset],
            houseRulesNoteID: UUID()
        )

        try store.save(expected)

        XCTAssertEqual(try HouseRulesStateStore(besideEventLog: eventLog).load(), expected)
    }

    func testSeparateVaultsKeepSeparateDraftsAndPresets() throws {
        let firstLog = directory.appendingPathComponent("first/events.jsonl")
        let secondLog = directory.appendingPathComponent("second/events.jsonl")
        let first = HouseRulesStateStore(besideEventLog: firstLog)
        let second = HouseRulesStateStore(besideEventLog: secondLog)

        try first.save(HouseRulesLocalState(draftText: "First vault"))
        try second.save(HouseRulesLocalState(draftText: "Second vault"))

        XCTAssertEqual(try first.load().draftText, "First vault")
        XCTAssertEqual(try second.load().draftText, "Second vault")
    }

    func testStateStoreRefusesToOverwriteUnreadableState() throws {
        let eventLog = directory.appendingPathComponent("events.jsonl")
        let store = HouseRulesStateStore(besideEventLog: eventLog)
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: store.fileURL)

        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(HouseRulesLocalState(draftText: "replacement")))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), corrupt)
    }
}
