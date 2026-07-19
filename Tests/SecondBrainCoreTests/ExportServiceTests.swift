import XCTest
@testable import SecondBrainCore

final class ExportServiceTests: XCTestCase {
    var tempURL: URL!
    var service: NoteService!
    var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("secondbrain-export-tests-\(UUID().uuidString)")
        tempURL = workDir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: tempURL)
        service = NoteService(store: store)

        _ = try service.createNote(title: "Rice Notes", body: "First sentence here. More detail follows.", source: "claude")
        let second = try service.createNote(title: "Rice Notes", body: "A same-titled note to test slug dedupe.", source: "gemini")
        try service.tagNote(id: second.id, tag: "duplicate-title", source: "gemini")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    func testMarkdownRenderIncludesTitleAndBody() throws {
        let notes = try service.listNotes()
        let text = MarkdownRenderer.renderCombined(notes)
        XCTAssertTrue(text.contains("# Rice Notes"))
        XCTAssertTrue(text.contains("First sentence here."))
        XCTAssertTrue(text.contains("#duplicate-title"))
    }

    func testOKFBundleStructureAndFrontmatter() throws {
        let dest = workDir.appendingPathComponent("bundle")
        try ExportService.export(using: service, format: .okfBundle, to: dest)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("index.md").path))
        XCTAssertTrue(fm.fileExists(atPath: dest.appendingPathComponent("log.md").path))

        let entries = try fm.contentsOfDirectory(atPath: dest.path)
        let conceptFiles = entries.filter { $0 != "index.md" && $0 != "log.md" }
        XCTAssertEqual(conceptFiles.count, 2, "one concept file per note")

        // Same title twice must not collide on disk.
        XCTAssertTrue(conceptFiles.contains("rice-notes.md"))
        XCTAssertTrue(conceptFiles.contains("rice-notes-2.md"))

        let content = try String(contentsOf: dest.appendingPathComponent("rice-notes.md"), encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("---\ntype: note\n"))
        XCTAssertTrue(content.contains("timestamp:"))

        let log = try String(contentsOf: dest.appendingPathComponent("log.md"), encoding: .utf8)
        XCTAssertTrue(log.contains("**Creation**"))
        XCTAssertTrue(log.contains("**Tag**"))
    }

    func testZipProducesValidArchive() throws {
        let dest = workDir.appendingPathComponent("export.zip")
        try ExportService.export(using: service, format: .zip, to: dest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        XCTAssertGreaterThan((attrs[.size] as? Int) ?? 0, 0)

        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        list.arguments = ["-l", dest.path]
        let pipe = Pipe()
        list.standardOutput = pipe
        try list.run()
        list.waitUntilExit()
        XCTAssertEqual(list.terminationStatus, 0)

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("index.md"))
        XCTAssertTrue(output.contains("rice-notes.md"))
    }

    func testPDFProducesValidDocument() throws {
        let dest = workDir.appendingPathComponent("export.pdf")
        try ExportService.export(using: service, format: .pdf, to: dest)

        let data = try Data(contentsOf: dest)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(data.prefix(4), Data("%PDF".utf8))
    }
}
