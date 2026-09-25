import XCTest
@testable import UnliRiceCore

final class TodoWidgetListTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(_ title: String, tags: Set<String>, daysAgo: Double,
                      creator: String = "claude", archived: Bool = false) -> Note {
        let at = now.addingTimeInterval(-daysAgo * 86_400)
        return Note(id: UUID(), title: title, body: "", tags: tags, creator: creator,
                    createdAt: at, updatedAt: at, archived: archived)
    }

    // MARK: - rows

    func testOnlyOpenTodoNotesOldestFirst() {
        let newer = note("Newer", tags: ["todo", "badminton"], daysAgo: 1)
        let older = note("Older", tags: ["todo", "calmdownoscar"], daysAgo: 5)
        let done = note("Done already", tags: ["todo", "badminton"], daysAgo: 9, archived: true)
        let plain = note("Just a note", tags: ["badminton"], daysAgo: 7)
        let handoff = note("Handoff — Badminton", tags: ["handoff", "badminton"], daysAgo: 2)

        let rows = TodoWidgetList.rows(from: [newer, plain, done, older, handoff], now: now)

        XCTAssertEqual(rows.map(\.title), ["Older", "Newer"])
        XCTAssertEqual(rows.map(\.id), [older.id, newer.id])
    }

    func testOneRowForATodoTaggedForTwoProjects() {
        let both = note("Fix the shared link", tags: ["todo", "unlidisk", "calmdownoscar"], daysAgo: 2)
        let rows = TodoWidgetList.rows(from: [both], now: now)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].subtitle.hasSuffix("calmdownoscar, unlidisk"), rows[0].subtitle)
    }

    func testSubtitleIsPlainWords() {
        let n = note("Update the website link", tags: ["todo", "calmdownoscar"], daysAgo: 2, creator: "codex")
        let subtitle = TodoWidgetList.rows(from: [n], now: now)[0].subtitle
        XCTAssertTrue(subtitle.hasPrefix("Suggested by Codex · "), subtitle)
        XCTAssertTrue(subtitle.hasSuffix(" · calmdownoscar"), subtitle)
        XCTAssertFalse(subtitle.contains("todo"), "the reserved tag is not a project")
    }

    func testNoProjectTagReadsNoProject() {
        let n = note("Loose item", tags: ["todo"], daysAgo: 1)
        XCTAssertTrue(TodoWidgetList.rows(from: [n], now: now)[0].subtitle.hasSuffix("no project"))
    }

    func testTitleIsTrimmed() {
        let n = note("  Spaced out \n", tags: ["todo"], daysAgo: 1)
        XCTAssertEqual(TodoWidgetList.rows(from: [n], now: now)[0].title, "Spaced out")
    }

    func testSameTimestampOrderIsStable() {
        let a = note("A", tags: ["todo"], daysAgo: 3)
        let b = note("B", tags: ["todo"], daysAgo: 3)
        let forward = TodoWidgetList.rows(from: [a, b], now: now).map(\.id)
        let backward = TodoWidgetList.rows(from: [b, a], now: now).map(\.id)
        XCTAssertEqual(forward, backward)
    }

    // MARK: - wording

    func testEveryFailureHasAPlainReason() {
        let all: [WidgetCorpus.Unreadable] = [.settingsUnreadable, .folderFailed, .noGroupContainer,
                                              .logMissing, .logUnreadable]
        for failure in all {
            let reason = TodoWidgetList.reason(for: failure)
            XCTAssertFalse(reason.isEmpty)
            for jargon in ["jsonl", "bookmark", "container", "corpus", "Group"] {
                XCTAssertFalse(reason.contains(jargon), "\(failure): \(reason)")
            }
        }
        XCTAssertEqual(TodoWidgetList.reason(for: .folderFailed),
                       "The widget can't open a custom notes folder yet.")
    }

    func testFixedCopy() {
        XCTAssertEqual(TodoWidgetList.emptyText,
                       "Nothing to do. When an AI assistant spots something for later, it shows up here.")
        XCTAssertEqual(TodoWidgetList.unknownText,
                       "Can't read your to-do list right now. Open Unli Rice to fix it.")
        XCTAssertEqual(TodoWidgetList.markDoneLabel("Call the bank"), "Mark done: Call the bank")
        XCTAssertEqual(TodoWidgetList.moreText(4), "+4 more, open Unli Rice")
    }

    // MARK: - TodoDone

    private func service() throws -> (NoteService, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoWidgetListTests-\(UUID().uuidString)", isDirectory: true)
        let log = dir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: log)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return (NoteService(store: store), log)
    }

    private func archiveEvents(_ log: URL) throws -> Int {
        let text = try String(contentsOf: log, encoding: .utf8)
        return text.split(separator: "\n").filter { $0.contains("\"kind\":\"archived\"") }.count
    }

    func testDoneArchivesOnceAndASecondTapIsANoOp() throws {
        let (svc, log) = try service()
        let item = try svc.createNote(title: "Delete old website copies", body: "", source: "claude")
        try svc.tagNote(id: item.id, tag: "todo", source: "claude")

        XCTAssertEqual(try TodoDone.markDone(noteID: item.id, service: svc), .archived)
        XCTAssertEqual(try TodoDone.markDone(noteID: item.id, service: svc), .nothingToDo)

        let archived = try XCTUnwrap(svc.getNote(id: item.id))
        XCTAssertTrue(archived.archived)
        XCTAssertEqual(try archiveEvents(log), 1)
    }

    func testDoneWritesNothingForAMissingOrNonTodoNote() throws {
        let (svc, log) = try service()
        let plain = try svc.createNote(title: "Just a note", body: "", source: "claude")

        XCTAssertEqual(try TodoDone.markDone(noteID: plain.id, service: svc), .nothingToDo)
        XCTAssertEqual(try TodoDone.markDone(noteID: UUID(), service: svc), .nothingToDo)
        XCTAssertFalse(try XCTUnwrap(svc.getNote(id: plain.id)).archived)
        XCTAssertEqual(try archiveEvents(log), 0)
    }

    func testDoneThroughAReadExistingStoreWritesToThatLog() throws {
        let (svc, log) = try service()
        let item = try svc.createNote(title: "Rate prompt for Shuttle Vision", body: "", source: "claude")
        try svc.tagNote(id: item.id, tag: "todo", source: "claude")

        // What the widget does: open the existing log without creating anything.
        let widgetSide = NoteService(store: try EventStore(readingExisting: log))
        XCTAssertEqual(try TodoDone.markDone(noteID: item.id, service: widgetSide), .archived)

        svc.rebuild()
        XCTAssertTrue(try XCTUnwrap(svc.getNote(id: item.id)).archived)
    }
}
