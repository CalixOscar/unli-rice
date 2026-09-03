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

        let event = try writer.writeCapture(text: transcript)

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

    /// `writeCapture` returns only the `created` event, so a caller mirroring
    /// these writes into a second log — which `CaptureStore` does, and which is
    /// what `sync()` republishes from — silently dropped every tag. Captures
    /// then carried no project tab, the phone's tab filter matched nothing, and
    /// the UI said "No synced notes found." over a corpus that had them.
    func testWriteCaptureEventsReturnsTagEventsAndNotJustTheCreatedOne() throws {
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: "iPhone")

        let events = try writer.writeCaptureEvents(text: "Tag me", tags: ["Unli Thoughts"])

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.kind, .created)

        let tagged = try XCTUnwrap(events.last)
        XCTAssertEqual(tagged.kind, .tagged)
        XCTAssertEqual(tagged.tag, "Unli Thoughts")
        XCTAssertEqual(tagged.device, "iPhone")
        // Same note, or the tag lands on nothing.
        XCTAssertEqual(tagged.noteId, events.first?.noteId)

        // The one-event convenience form still hands back the created event.
        XCTAssertEqual(try writer.writeCapture(text: "Head only", tags: ["x"]).kind, .created)
    }

    /// A constant fallback title scores 1.0 against itself in
    /// `Janitor.duplicateProposals`, which compares titles alone at a 0.85
    /// threshold — so two failed transcriptions would propose merging two
    /// unrelated recordings. Distinct titles are what stops that.
    func testEmptyTranscriptsGetDistinctTitlesRatherThanAConstant() throws {
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: "iPhone")

        let first = try writer.writeCapture(text: "", date: Date(timeIntervalSince1970: 1000))
        let second = try writer.writeCapture(text: "   ", date: Date(timeIntervalSince1970: 1001))

        let firstTitle = try XCTUnwrap(first.title)
        let secondTitle = try XCTUnwrap(second.title)

        XCTAssertNotEqual(firstTitle, secondTitle)
        XCTAssertFalse(firstTitle.isEmpty)
        XCTAssertNotEqual(firstTitle, "Untitled", "an empty title becomes Untitled in Projector")
    }

    func testShardWriterExplicitDeviceLabel() throws {
        let identity = DeviceIdentity.current(inDirectory: root)
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: identity.label)
        let event = try writer.writeCapture(text: "App intent capture")

        XCTAssertEqual(event.source, "human")
        XCTAssertNotNil(event.device)
        XCTAssertEqual(event.device, identity.label)
    }

    func testWriteAppendEventsEmitsOneAppendedEventWithNoTitleAndProjectsJoinedBody() throws {
        let writer = ShardWriter(shardFileURL: shardFile, deviceLabel: "iPhone")
        let created = try writer.writeCapture(text: "Original thought")

        let appends = try writer.writeAppendEvents(noteID: created.noteId, text: "Additional thought")
        XCTAssertEqual(appends.count, 1)

        let appended = try XCTUnwrap(appends.first)
        XCTAssertEqual(appended.kind, .appended)
        XCTAssertEqual(appended.noteId, created.noteId)
        XCTAssertNil(appended.title)
        XCTAssertEqual(appended.text, "Additional thought")
        XCTAssertEqual(appended.source, "human")
        XCTAssertEqual(appended.device, "iPhone")

        let projected = Projector.project([created, appended])
        let note = try XCTUnwrap(projected[created.noteId])
        XCTAssertEqual(note.body, "Original thought\n\n---\nAdditional thought")
    }

    func testEffectiveTranscriptionLocaleReturnsCurrentForEmptyIdentifier() {
        XCTAssertEqual(TranscriptionLocale.effectiveLocale(for: ""), Locale.current)
        XCTAssertEqual(TranscriptionLocale.effectiveLocale(for: "ja_JP").identifier, "ja_JP")
        XCTAssertEqual(TranscriptionLocale.effectiveLocale(for: "es_ES").identifier, "es_ES")
    }
}
