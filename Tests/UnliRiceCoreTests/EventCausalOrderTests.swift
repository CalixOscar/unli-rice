import XCTest
@testable import UnliRiceCore
final class EventCausalOrderTests: XCTestCase {
    func testMissingParentOrphanAndCycle() {
        let note = UUID(), missing = UUID(), aID = UUID(), bID = UUID()
        let orphan = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: UUID(), causalParents: [missing])
        let pending = Event(noteId: note, source: "human", kind: .tagged, tag: "x", causalParents: [missing])
        let a = Event(id: aID, noteId: note, source: "human", kind: .tagged, tag: "a", causalParents: [bID, missing])
        let b = Event(id: bID, noteId: note, source: "human", kind: .tagged, tag: "b", causalParents: [aID])
        let result = EventCausalOrder.order([orphan, pending, a, b])
        XCTAssertTrue(result.pending.contains(pending.id))
        XCTAssertFalse(result.pending.contains(orphan.id))
        XCTAssertEqual(result.conflictedNoteIDs, [note])
    }
    func testBoundWritesMigrateAndWarmCacheRebuilds() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), first = try EventStore(fileURL: url)
        let service = NoteService(store: first)
        let note = try service.createNote(title: "a", body: "b", source: "human")
        let prefix = try Data(contentsOf: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        try first.prepareNativeCausalHistory()
        let once = try Data(contentsOf: url)
        XCTAssertTrue(once.starts(with: prefix))
        try first.prepareNativeCausalHistory()
        XCTAssertEqual(try Data(contentsOf: url), once)
        _ = try service.tagNote(id: note.id, tag: "x", source: "human")
        let other = NoteService(store: try EventStore(fileURL: url))
        _ = try other.untagNote(id: note.id, tag: "x", source: "human")
        XCTAssertFalse(try XCTUnwrap(service.getNote(id: note.id)).tags.contains("x"))
        XCTAssertEqual(try service.getNote(id: note.id), Projector.project(try first.readAll())[note.id])
    }
}

extension EventCausalOrderTests {
    func testSameSecondMutationsPreserveCausality() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        let service = NoteService(store: store)
        let note = try service.createNote(title: "n", body: "start", source: "human")
        _ = try service.tagNote(id: note.id, tag: "x", source: "human")
        _ = try service.untagNote(id: note.id, tag: "x", source: "human")
        _ = try service.archiveNote(id: note.id, reason: "x", source: "human")
        _ = try service.unarchiveNote(id: note.id, source: "human")
        let flag = try service.flagForReview(id: note.id, reason: "check", source: "human")
        _ = try service.resolveReview(id: note.id, flagId: flag.flags[0].id, source: "human")
        _ = try service.appendToNote(id: note.id, text: "one", source: "human")
        let final = try service.appendToNote(id: note.id, text: "two", source: "human")
        XCTAssertFalse(final.tags.contains("x")); XCTAssertFalse(final.archived)
        XCTAssertTrue(final.flags[0].resolved); XCTAssertTrue(final.body.hasSuffix("one\n\n---\ntwo"))
        XCTAssertEqual(final, Projector.project(try store.readAll())[note.id])
    }
    func testJoiningHeadsAndRawBatchDeclarationFirst() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        let note = UUID(), root = Event(noteId: note, source: "human", kind: .created, title: "n", causalParents: [])
        let a = Event(noteId: note, source: "human", kind: .tagged, tag: "a", causalParents: [root.id])
        let b = Event(noteId: note, source: "human", kind: .tagged, tag: "b", causalParents: [root.id])
        let legacy = Event(noteId: UUID(), source: "human", kind: .created, title: "legacy")
        let declaration = Event(noteId: legacy.noteId, source: "unlirice", kind: .causalOrder, relatedEventId: legacy.id, causalParents: [])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try store.appendRawBatch(try [root, a, b, legacy, declaration].map { try enc.encode($0) })
        let records = try store.readAll()
        XCTAssertEqual(records.first?.kind, .causalOrder)
        try store.append(Event(noteId: note, source: "human", kind: .tagged, tag: "joined"))
        XCTAssertEqual(Set(try XCTUnwrap(store.readAll().last?.causalParents)), Set([a.id, b.id]))
    }
    func testConcurrentBoundWritersKeepAllHeads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        let note = try NoteService(store: store).createNote(title: "n", body: "", source: "human")
        DispatchQueue.concurrentPerform(iterations: 12) { i in
            do { try EventStore(fileURL: url).append(Event(noteId: note.id, source: "human", kind: .tagged, tag: "\(i)")) }
            catch { XCTFail("Writer failed: \(error)") }
        }
        XCTAssertEqual(Projector.project(try store.readAll())[note.id]?.tags.count, 12)
    }
}

extension EventCausalOrderTests {
    func testDamagedHistoryCannotBindOrBeSilentlyRepaired() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), broken = Data("{partial".utf8)
        try broken.write(to: url)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true))
        XCTAssertFalse(NativeCloudBinding.exists(besideEventLog: url))
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }
    func testPartiallyMigratedPrefixIsIdempotent() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url), id = UUID()
        let first = Event(noteId: id, source: "human", kind: .created, title: "n")
        let second = Event(noteId: id, source: "human", kind: .tagged, tag: "x")
        try store.append(first); try store.append(second)
        let old = try Data(contentsOf: url)
        try store.append(Event(noteId: id, source: "unlirice", kind: .causalOrder, relatedEventId: first.id, causalParents: []))
        try store.prepareNativeCausalHistory()
        let records = try store.readAll(), declarations = records.filter { $0.kind == .causalOrder }
        XCTAssertEqual(declarations.count, 2)
        XCTAssertEqual(declarations.first(where: { $0.relatedEventId == second.id })?.causalParents, [first.id])
        XCTAssertTrue(try Data(contentsOf: url).starts(with: old))
        let snapshot = try Data(contentsOf: url); try store.prepareNativeCausalHistory(); XCTAssertEqual(try Data(contentsOf: url), snapshot)
    }
}

extension EventCausalOrderTests {
    func testBoundRawWritesRefuseTornHistory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "t" as NSString), allowCreate: true)
        let torn = Data("{partial".utf8); try torn.write(to: url)
        XCTAssertThrowsError(try store.appendRaw(Data("{}".utf8)))
        XCTAssertThrowsError(try store.appendRawBatch([Data("{}".utf8)]))
        XCTAssertEqual(try Data(contentsOf: url), torn)
    }
    func testCrossNoteAndMalformedDeclarationsReportConflicts() throws {
        let aID = UUID(), bID = UUID(), missing = UUID()
        let a = Event(noteId: aID, source: "human", kind: .created, title: "a", causalParents: [])
        let b = Event(noteId: bID, source: "human", kind: .created, title: "b", causalParents: [a.id])
        let other = Event(noteId: bID, source: "human", kind: .tagged, tag: "x", causalParents: [missing])
        let orphan = Event(noteId: aID, source: "unlirice", kind: .causalOrder, relatedEventId: UUID(), causalParents: nil)
        let result = Projector.projectResult([a, b, other, orphan])
        XCTAssertEqual(result.conflictedNoteIDs, [bID])
        XCTAssertTrue(result.pendingEventIDs.contains(other.id))
        XCTAssertFalse(result.pendingEventIDs.contains(orphan.id))
        XCTAssertTrue(NoteServiceError.orderingConflict(noteIDs: [bID]).localizedDescription.contains(bID.uuidString))
        let mismatch = Event(noteId: bID, source: "unlirice", kind: .causalOrder, relatedEventId: a.id, causalParents: [])
        XCTAssertEqual(Projector.projectResult([a, mismatch]).conflictedNoteIDs, [aID, bID])
        let malformed = Event(noteId: aID, source: "unlirice", kind: .causalOrder, relatedEventId: a.id)
        XCTAssertEqual(Projector.projectResult([a, malformed]).conflictedNoteIDs, [aID])
    }
    func testStrictPreflightRejectsOversizedParentList() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        let event = Event(noteId: UUID(), source: "human", kind: .created, title: "x", causalParents: (0..<1025).map { _ in UUID() })
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try store.appendRaw(encoder.encode(event))
        XCTAssertThrowsError(try store.validateNativeHistory())
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "t" as NSString), allowCreate: true))
        XCTAssertFalse(NativeCloudBinding.exists(besideEventLog: url))
    }
}

extension EventCausalOrderTests {
    func testDeclarationsUnionAllConstraints() {
        let note = UUID(), first = Event(noteId: UUID(), source: "human", kind: .created, title: "unused", causalParents: [])
        let root = Event(noteId: note, source: "human", kind: .created, title: "n", causalParents: [])
        let a = Event(noteId: note, source: "human", kind: .tagged, tag: "a", causalParents: [root.id])
        let b = Event(noteId: note, source: "human", kind: .tagged, tag: "b", causalParents: [root.id])
        let target = Event(noteId: note, source: "human", kind: .appended, text: "joined")
        let d1 = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: target.id, causalParents: [a.id])
        let d2 = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: target.id, causalParents: [b.id])
        let order = EventCausalOrder.order([first, target, d1, b, d2, a, root]).ordered.map(\.id)
        XCTAssertLessThan(order.firstIndex(of: a.id)!, order.firstIndex(of: target.id)!)
        XCTAssertLessThan(order.firstIndex(of: b.id)!, order.firstIndex(of: target.id)!)
    }
}

extension EventCausalOrderTests {
    func testSnapshotIncludesMigrationWithoutChangingLegacyPrefix() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        try store.append(Event(noteId: UUID(), source: "human", kind: .created, title: "n"))
        let prefix = try Data(contentsOf: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "token" as NSString), allowCreate: true)
        let snapshot = try store.nativeCausalSnapshot()
        XCTAssertTrue(snapshot.starts(with: prefix))
        XCTAssertEqual(snapshot, try Data(contentsOf: url))
        XCTAssertEqual(try store.readAll().filter { $0.kind == .causalOrder }.count, 1)
        XCTAssertEqual(try store.nativeCausalSnapshot(), snapshot)
    }
}

extension EventCausalOrderTests {
    func testOrphanAndMixedLegacyNotesRemainVisible() {
        let legacyID = UUID(), modernID = UUID(), missingID = UUID()
        let old = Event(noteId: legacyID, source: "human", kind: .created, title: "old")
        let orphan = Event(noteId: legacyID, source: "unlirice", kind: .causalOrder, relatedEventId: UUID(), causalParents: [missingID])
        XCTAssertEqual(Projector.project([old, orphan])[legacyID]?.title, "old")
        let modern = Event(noteId: modernID, source: "human", kind: .created, title: "modern", causalParents: [])
        let undeclared = Event(noteId: modernID, source: "human", kind: .tagged, tag: "pending")
        let result = Projector.projectResult([modern, old, orphan, undeclared])
        XCTAssertEqual(result.notes[legacyID]?.title, "old")
        XCTAssertEqual(result.notes[modernID]?.title, "modern")
        XCTAssertFalse(result.notes[modernID]!.tags.contains("pending"))
        XCTAssertTrue(result.pendingEventIDs.contains(undeclared.id))
    }
}

extension EventCausalOrderTests {
    func testOversizedLegacyRecordRemainsWritableButCannotBind() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        let event = Event(noteId: UUID(), source: "human", kind: .created, title: "legacy", text: String(repeating: "x", count: EventStore.maxNativeLineBytes + 1))
        try store.append(event)
        let original = try Data(contentsOf: url)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "t" as NSString), allowCreate: true)) { error in
            XCTAssertEqual(error.localizedDescription, "This note change exceeds the iCloud sync limit.")
        }
        XCTAssertFalse(NativeCloudBinding.exists(besideEventLog: url))
        XCTAssertEqual(try Data(contentsOf: url), original)
        try store.append(Event(noteId: UUID(), source: "human", kind: .created, title: "still writable"))
        XCTAssertTrue(try Data(contentsOf: url).starts(with: original))
    }
    func testOversizedBoundWritesLeaveLogUnchanged() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "t" as NSString), allowCreate: true)
        let note = try NoteService(store: store).createNote(title: "n", body: "", source: "human")
        let original = try Data(contentsOf: url)
        let large = Event(noteId: note.id, source: "human", kind: .appended, text: String(repeating: "x", count: EventStore.maxNativeLineBytes + 1), causalParents: [])
        XCTAssertThrowsError(try store.append(large))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let raw = try encoder.encode(large)
        XCTAssertThrowsError(try store.appendRaw(raw))
        XCTAssertThrowsError(try store.appendRawBatch([raw]))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
}

extension EventCausalOrderTests {
    func testRawBatchValidatesCausalCompletenessAtomically() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("events.jsonl"), store = try EventStore(fileURL: url)
        _ = try NativeCloudBinding.open(eventLogURL: url, provider: NativeCloudIdentityFixture(token: "t" as NSString), allowCreate: true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let note = UUID(), legacy = Event(noteId: note, source: "human", kind: .created, title: "legacy")
        let before = try Data(contentsOf: url)
        XCTAssertThrowsError(try store.appendRawBatch([encoder.encode(legacy)]))
        XCTAssertEqual(try Data(contentsOf: url), before)
        let declaration = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: legacy.id, causalParents: [])
        try store.appendRawBatch([encoder.encode(declaration)])
        try store.appendRawBatch([encoder.encode(legacy)])
        XCTAssertEqual(try NoteService(store: store).getNote(id: note)?.title, "legacy")
        let other = Event(noteId: UUID(), source: "human", kind: .created, title: "other", causalParents: [])
        let bad = Event(noteId: note, source: "human", kind: .tagged, tag: "bad", causalParents: [other.id])
        let snapshot = try Data(contentsOf: url)
        let mismatch = Event(noteId: UUID(), source: "unlirice", kind: .causalOrder, relatedEventId: legacy.id, causalParents: [])
        XCTAssertThrowsError(try store.appendRawBatch([encoder.encode(mismatch)]))
        XCTAssertThrowsError(try store.appendRawBatch([encoder.encode(other), encoder.encode(bad)]))
        XCTAssertEqual(try Data(contentsOf: url), snapshot)
        let orphan = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: UUID(), causalParents: [UUID()])
        try store.appendRawBatch([encoder.encode(orphan)])
        XCTAssertEqual(try NoteService(store: store).getNote(id: note)?.title, "legacy")
    }
}
