import XCTest
@testable import UnliRiceCore

final class ShardWriterTests: XCTestCase {
    private var root: URL!
    private var shardFile: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("unlirice-shardwriter-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        shardFile = root.appendingPathComponent("events-iphone.jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testShardWriterCreatesEventWithDerivedTitleAndDeviceAttribution() throws {
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: "iPhone")
        let transcript = "Remember to buy extra unli rice for the team dinner [[special note]]"

        let event = try writer.writeCapture(transcript: transcript)

        XCTAssertEqual(event.source, "human")
        XCTAssertEqual(event.device, "iPhone")
        XCTAssertEqual(event.kind, .created)
        XCTAssertEqual(event.text, transcript)

        // Verifies title derivation: ImporterText.sanitizeTitle(ImporterText.condense(transcript, limit: 60))
        let expectedTitle = ImporterText.sanitizeTitle(ImporterText.condense(transcript, limit: 60))
        XCTAssertEqual(event.title, expectedTitle)

        let raw = try String(contentsOf: shardFile, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"source\":\"human\""))
        XCTAssertTrue(raw.contains("\"device\":\"iPhone\""))
        XCTAssertTrue(raw.contains("\"title\":\"\(expectedTitle)\""))
    }

    /// A constant fallback title scores 1.0 against itself in
    /// `Janitor.duplicateProposals`, which compares titles alone at a 0.85
    /// threshold — so two failed transcriptions would propose merging two
    /// unrelated recordings. Distinct titles are what stops that.
    func testEmptyTranscriptsGetDistinctTitlesRatherThanAConstant() throws {
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: "iPhone")

        let first = try writer.writeCapture(transcript: "", date: Date(timeIntervalSince1970: 1000))
        let second = try writer.writeCapture(transcript: "   ", date: Date(timeIntervalSince1970: 1001))

        let firstTitle = try XCTUnwrap(first.title)
        let secondTitle = try XCTUnwrap(second.title)

        XCTAssertNotEqual(firstTitle, secondTitle)
        XCTAssertFalse(firstTitle.isEmpty)
        XCTAssertNotEqual(firstTitle, "Untitled", "an empty title becomes Untitled in Projector")
    }
}
