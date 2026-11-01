import XCTest
@testable import UnliRiceCore
final class NativeCloudTransportTests: XCTestCase {
    func testRelayAndDedupAndAccountGate() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cloud = root.appendingPathComponent("cloud"), a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        for dir in [cloud, a, b] { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        let logA = a.appendingPathComponent("events.jsonl"), logB = b.appendingPathComponent("events.jsonl")
        let storeA = try EventStore(fileURL: logA), storeB = try EventStore(fileURL: logB)
        _ = try NoteService(store: storeA, deviceLabel: "iPhone").createNote(title: "Idea", body: "Hi", source: "human")
        let bindingA = try NativeCloudBinding.open(eventLogURL: logA, provider: NativeCloudIdentityFixture(token: "same" as NSString), allowCreate: true)
        let bindingB = try NativeCloudBinding.open(eventLogURL: logB, provider: NativeCloudIdentityFixture(token: "same" as NSString), allowCreate: true)
        XCTAssertEqual(try NativeCloudTransport.synchronize(eventLogURL: logA, rootURL: cloud, binding: bindingA, deviceID: "a", accountIsCurrent: { true }).eventsPublished, 2)
        XCTAssertEqual(try NativeCloudTransport.synchronize(eventLogURL: logB, rootURL: cloud, binding: bindingB, deviceID: "b", accountIsCurrent: { true }).eventsImported, 2)
        XCTAssertEqual(try NativeCloudTransport.synchronize(eventLogURL: logB, rootURL: cloud, binding: bindingB, deviceID: "b", accountIsCurrent: { true }).eventsImported, 0)
        XCTAssertEqual(try storeB.readAll().count, 2)
        XCTAssertEqual(try NoteService(store: storeB).listNotes().map(\.title), ["Idea"])
        XCTAssertThrowsError(try NativeCloudTransport.synchronize(eventLogURL: logB, rootURL: cloud, binding: bindingB, deviceID: "b", accountIsCurrent: { false }))
    }
}

extension NativeCloudTransportTests {
    private func fixture() throws -> (URL, URL, URL, NativeCloudBinding) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cloud = root.appendingPathComponent("cloud"), local = root.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let log = local.appendingPathComponent("events.jsonl")
        _ = try EventStore(fileURL: log)
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "test" as NSString), allowCreate: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (root, cloud, log, binding)
    }
    private func encoded(_ event: Event) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event); data.append(10); return data
    }
    private func sync(_ log: URL, _ cloud: URL, _ binding: NativeCloudBinding) throws -> NativeCloudTransport.Result {
        try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: "device", accountIsCurrent: { true })
    }
    func testCorruptAndFutureStateNeverReset() throws {
        let (_, cloud, log, binding) = try fixture()
        let state = log.deletingLastPathComponent().appendingPathComponent("native-cloud-state-\(binding.bindingID.uuidString).json")
        for text in ["broken", #"{"version":2,"exportedOffset":0,"imported":[]}"#] {
            let data = Data(text.utf8); try data.write(to: state)
            XCTAssertThrowsError(try sync(log, cloud, binding))
            XCTAssertEqual(try Data(contentsOf: state), data)
        }
    }
    func testMissingAndShrunkSourceRefused() throws {
        let (_, cloud, log, binding) = try fixture()
        let store = try EventStore(fileURL: log)
        _ = try NoteService(store: store).createNote(title: "a", body: "b", source: "human")
        _ = try sync(log, cloud, binding)
        try Data().write(to: log)
        XCTAssertThrowsError(try sync(log, cloud, binding))
        try FileManager.default.removeItem(at: log)
        XCTAssertThrowsError(try sync(log, cloud, binding))
    }
    func testMalformedBatchDoesNotImportPartialAndUnknownBytesSurvive() throws {
        let (_, cloud, log, binding) = try fixture()
        let id = UUID()
        let event = Event(noteId: id, source: "human", kind: .created, title: "known", causalParents: [])
        let batch = cloud.appendingPathComponent("events-remote-1.jsonl")
        var bad = try encoded(event); bad.append(Data("invalid\n".utf8)); try bad.write(to: batch)
        XCTAssertThrowsError(try sync(log, cloud, binding))
        XCTAssertEqual(try EventStore(fileURL: log).readAll().count, 0)
        var unknown = String(decoding: try encoded(event), as: UTF8.self)
        unknown = unknown.replacingOccurrences(of: "\"created\"", with: "\"futureKind\",\"futureField\":{\"nested\":true}")
        try Data(unknown.utf8).write(to: batch)
        XCTAssertEqual(try sync(log, cloud, binding).eventsImported, 1)
        XCTAssertEqual(try Data(contentsOf: log), Data(unknown.utf8))
    }
    func testProcessedFilesCannotStarvePending() throws {
        let (_, cloud, log, binding) = try fixture()
        let names = (0..<1001).map { String(format: "events-old-%04d.jsonl", $0) }
        for name in names { try Data("bad\n".utf8).write(to: cloud.appendingPathComponent(name)) }
        let state = log.deletingLastPathComponent().appendingPathComponent("native-cloud-state-\(binding.bindingID.uuidString).json")
        let json: [String: Any] = ["version": 1, "exportedOffset": 0, "imported": names]
        try JSONSerialization.data(withJSONObject: json).write(to: state)
        let event = Event(noteId: UUID(), source: "human", kind: .created, title: "pending", causalParents: [])
        try encoded(event).write(to: cloud.appendingPathComponent("events-z-new.jsonl"))
        XCTAssertEqual(try sync(log, cloud, binding).eventsImported, 1)
    }
    func testBatchBoundsAndIncompleteSource() throws {
        let (_, cloud, log, binding) = try fixture()
        let store = try EventStore(fileURL: log)
        for _ in 0..<501 { try store.append(Event(noteId: UUID(), source: "human", kind: .created, title: "x")) }
        let first = try sync(log, cloud, binding)
        XCTAssertEqual(first.eventsPublished, 500); XCTAssertFalse(first.issues.isEmpty)
        XCTAssertEqual(try sync(log, cloud, binding).eventsPublished, 1)
        let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd(); try handle.write(contentsOf: Data("partial".utf8)); try handle.close()
        XCTAssertThrowsError(try sync(log, cloud, binding))
    }
    func testNewestOverviewAndOlderWrite() throws {
        let (_, cloud, _, _) = try fixture()
        let newer = StudioOverviewFile(generatedAt: Date(timeIntervalSince1970: 200), deviceLabel: "new", projects: [])
        let older = StudioOverviewFile(generatedAt: Date(timeIntervalSince1970: 100), deviceLabel: "old", projects: [])
        try NativeCloudTransport.publishOverview(newer, rootURL: cloud, deviceID: "a", accountIsCurrent: { true })
        try NativeCloudTransport.publishOverview(older, rootURL: cloud, deviceID: "a", accountIsCurrent: { true })
        try NativeCloudTransport.publishOverview(older, rootURL: cloud, deviceID: "b", accountIsCurrent: { true })
        XCTAssertEqual(try NativeCloudTransport.latestOverview(rootURL: cloud, accountIsCurrent: { true }).overview?.deviceLabel, "new")
    }
    func testAccountChangeBeforeCommitLeavesCursorRetryable() throws {
        let (_, cloud, log, binding) = try fixture()
        _ = try NoteService(store: EventStore(fileURL: log)).createNote(title: "a", body: "b", source: "human")
        var calls = 0
        XCTAssertThrowsError(try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: "a", accountIsCurrent: { calls += 1; return calls < 4 }))
        XCTAssertEqual(try sync(log, cloud, binding).eventsPublished, 1)
        XCTAssertEqual(try EventStore(fileURL: log).readAll().count, 1)
    }
}

extension NativeCloudTransportTests {
    func testByteLimitAndTwoPhonesWithSameDeviceLabel() throws {
        let (_, cloud, log, binding) = try fixture()
        let store = try EventStore(fileURL: log)
        let phone = NoteService(store: store, deviceLabel: "iPhone")
        _ = try phone.createNote(title: "first", body: String(repeating: "x", count: 700_000), source: "human")
        _ = try phone.createNote(title: "second", body: String(repeating: "x", count: 700_000), source: "human")
        _ = try phone.createNote(title: "third", body: String(repeating: "x", count: 700_000), source: "human")
        let first = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: "phone-one", accountIsCurrent: { true })
        XCTAssertEqual(first.eventsPublished, 2); XCTAssertFalse(first.issues.isEmpty)
        let second = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: "phone-two", accountIsCurrent: { true })
        XCTAssertEqual(second.eventsPublished, 1)
        let oversized = cloud.appendingPathComponent("events-bad-large.jsonl")
        try Data(repeating: 65, count: 2 * 1024 * 1024 + 1).write(to: oversized)
        XCTAssertThrowsError(try sync(log, cloud, binding))
    }
    func testConcurrentExportsAndImportsDeduplicate() throws {
        let (_, cloud, log, binding) = try fixture()
        _ = try NoteService(store: EventStore(fileURL: log), deviceLabel: "iPhone").createNote(title: "A", body: "B", source: "human")
        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            do { _ = try self.sync(log, cloud, binding) } catch { XCTFail("Concurrent sync failed: \(error)") }
        }
        _ = try sync(log, cloud, binding)
        XCTAssertEqual(try EventStore(fileURL: log).readAll().count, 1)
    }
}

extension NativeCloudTransportTests {
    func testLegacyWindowCarriesDeclarationsAndCursorTracksOnlySource() throws {
        let (_, cloud, log, _) = try fixture()
        try FileManager.default.removeItem(at: log.deletingLastPathComponent().appendingPathComponent("native-cloud-binding.json"))
        let store = try EventStore(fileURL: log)
        let note = try NoteService(store: store).createNote(title: "legacy", body: "body", source: "human")
        let originalBytes = try Data(contentsOf: log)
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "test" as NSString), allowCreate: true)
        let result = try sync(log, cloud, binding)
        XCTAssertEqual(result.eventsPublished, 2)
        let batchURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: cloud, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("events-") })
        let batch = try String(contentsOf: batchURL, encoding: .utf8)
        XCTAssertTrue(batch.contains("causalOrder")); XCTAssertTrue(batch.contains(note.id.uuidString))
        XCTAssertTrue(try Data(contentsOf: log).starts(with: originalBytes))
        XCTAssertEqual(try sync(log, cloud, binding).eventsPublished, 0)
        XCTAssertEqual(try NoteService(store: store).getNote(id: note.id)?.title, "legacy")
    }
    func testMissingDeclarationRejectedAndDeclarationOnlyAccepted() throws {
        let (_, cloud, log, binding) = try fixture()
        let note = UUID(), event = Event(noteId: note, source: "human", kind: .created, title: "legacy")
        let target = cloud.appendingPathComponent("events-a.jsonl")
        try encoded(event).write(to: target)
        XCTAssertThrowsError(try sync(log, cloud, binding))
        XCTAssertTrue(try EventStore(fileURL: log).readAll().isEmpty)
        let declaration = Event(noteId: note, source: "unlirice", kind: .causalOrder, relatedEventId: event.id, causalParents: [])
        try encoded(declaration).write(to: target)
        XCTAssertEqual(try sync(log, cloud, binding).eventsImported, 1)
        XCTAssertTrue(try NoteService(store: EventStore(fileURL: log)).listNotes().isEmpty)
    }
    func testStageLimitLeavesRemainingBatchForNextPass() throws {
        let (_, cloud, log, binding) = try fixture()
        for i in 0..<33 {
            let event = Event(noteId: UUID(), source: "human", kind: .created, title: "\(i)", causalParents: [])
            try encoded(event).write(to: cloud.appendingPathComponent(String(format: "events-remote-%02d.jsonl", i)))
        }
        let first = try sync(log, cloud, binding)
        XCTAssertEqual(first.eventsImported, 32)
        XCTAssertTrue(first.issues.contains("More cloud batches remain to be checked."))
        XCTAssertEqual(try sync(log, cloud, binding).eventsImported, 1)
        XCTAssertEqual(try NoteService(store: EventStore(fileURL: log)).listNotes().count, 33)
    }
}

extension NativeCloudTransportTests {
    func testReversedArrivalWaitsForParentThenProjects() throws {
        let (_, cloud, log, binding) = try fixture()
        let note = UUID(), parent = Event(noteId: note, source: "human", kind: .created, title: "later", causalParents: [])
        let child = Event(noteId: note, source: "human", kind: .tagged, tag: "todo", causalParents: [parent.id])
        try encoded(child).write(to: cloud.appendingPathComponent("events-child.jsonl"))
        XCTAssertEqual(try sync(log, cloud, binding).eventsImported, 1)
        XCTAssertTrue(try NoteService(store: EventStore(fileURL: log)).listNotes().isEmpty)
        try encoded(parent).write(to: cloud.appendingPathComponent("events-parent.jsonl"))
        _ = try sync(log, cloud, binding)
        XCTAssertTrue(try XCTUnwrap(NoteService(store: EventStore(fileURL: log)).getNote(id: note)).tags.contains("todo"))
    }
    func testLegacyDeclarationExtrasRespectCountLimit() throws {
        let (_, cloud, log, _) = try fixture()
        try FileManager.default.removeItem(at: log.deletingLastPathComponent().appendingPathComponent("native-cloud-binding.json"))
        let store = try EventStore(fileURL: log)
        for _ in 0..<251 { try store.append(Event(noteId: UUID(), source: "human", kind: .created, title: "legacy")) }
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "test" as NSString), allowCreate: true)
        let first = try sync(log, cloud, binding)
        XCTAssertEqual(first.eventsPublished, 500)
        XCTAssertTrue(first.issues.contains("More local events remain to be published."))
        let second = try sync(log, cloud, binding)
        XCTAssertGreaterThan(second.eventsPublished, 0)
        XCTAssertEqual(try NoteService(store: store).listNotes().count, 251)
    }
}

extension NativeCloudTransportTests {
    func testStageByteBudgetDefersReadyBatches() throws {
        let (_, cloud, log, binding) = try fixture()
        for i in 0..<9 {
            let a = Event(noteId: UUID(), source: "human", kind: .created, title: "a", text: String(repeating: "x", count: 950_000), causalParents: [])
            let b = Event(noteId: UUID(), source: "human", kind: .created, title: "b", text: String(repeating: "x", count: 950_000), causalParents: [])
            var data = try encoded(a); data.append(try encoded(b))
            try data.write(to: cloud.appendingPathComponent(String(format: "events-byte-%02d.jsonl", i)))
        }
        let first = try sync(log, cloud, binding)
        XCTAssertEqual(first.eventsImported, 16)
        XCTAssertTrue(first.issues.contains("More cloud batches remain to be checked."))
        let second = try sync(log, cloud, binding)
        XCTAssertEqual(second.eventsImported, 2)
        XCTAssertEqual(try NoteService(store: EventStore(fileURL: log)).listNotes().count, 18)
    }
}

extension NativeCloudTransportTests {
    func testPlaceholderOnlyTruncationDoesNotRequestImmediateRetry() throws {
        let (_, cloud, log, binding) = try fixture()
        let placeholders = (0..<1001).map { cloud.appendingPathComponent(String(format: ".events-placeholder-%04d.jsonl.icloud", $0)) }
        let result = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: "device", accountIsCurrent: { true }, discoveredURLs: placeholders)
        XCTAssertTrue(result.waitingForDownloads)
        XCTAssertFalse(result.hasMoreWork)
        XCTAssertEqual(result.eventsImported, 0)
    }
    func testDuplicateOnlyReadyFilesContinueUntilDrained() throws {
        let (_, cloud, log, binding) = try fixture()
        let event = Event(noteId: UUID(), source: "human", kind: .created, title: "once", causalParents: [])
        let bytes = try encoded(event)
        for index in 0..<65 {
            try bytes.write(to: cloud.appendingPathComponent(String(format: "events-duplicate-%02d.jsonl", index)))
        }
        let first = try sync(log, cloud, binding)
        XCTAssertEqual(first.eventsImported, 1); XCTAssertTrue(first.hasMoreWork)
        let second = try sync(log, cloud, binding)
        XCTAssertEqual(second.eventsImported, 0); XCTAssertTrue(second.hasMoreWork)
        let third = try sync(log, cloud, binding)
        XCTAssertEqual(third.eventsImported, 0); XCTAssertFalse(third.hasMoreWork)
        XCTAssertEqual(try NoteService(store: EventStore(fileURL: log)).listNotes().count, 1)
    }
}

extension NativeCloudTransportTests {
    func testOwnOverviewRecoveryAndFutureProtection() throws {
        let (_, cloud, _, _) = try fixture()
        let target = cloud.appendingPathComponent("studio-overview-device.json")
        let overview = StudioOverviewFile(generatedAt: Date(timeIntervalSince1970: 200), deviceLabel: "valid", projects: [])
        try Data("broken".utf8).write(to: target)
        try NativeCloudTransport.publishOverview(overview, rootURL: cloud, deviceID: "device", accountIsCurrent: { true })
        XCTAssertEqual(try StudioOverviewFile.read(fromFolder: cloud, filename: target.lastPathComponent).deviceLabel, "valid")
        let future = Data(#"{"version":999}"#.utf8); try future.write(to: target)
        XCTAssertThrowsError(try NativeCloudTransport.publishOverview(overview, rootURL: cloud, deviceID: "device", accountIsCurrent: { true }))
        XCTAssertEqual(try Data(contentsOf: target), future)
        try FileManager.default.removeItem(at: target)
        let placeholder = cloud.appendingPathComponent(".studio-overview-device.json.icloud")
        try Data("placeholder".utf8).write(to: placeholder)
        XCTAssertThrowsError(try NativeCloudTransport.publishOverview(overview, rootURL: cloud, deviceID: "device", accountIsCurrent: { true })) { error in
            XCTAssertEqual(error.localizedDescription, "Waiting for the previous iCloud project overview to download.")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: placeholder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
    func testUnsafeDeviceIDsAreRejectedWithoutCollisions() throws {
        let (_, cloud, log, binding) = try fixture()
        let overview = StudioOverviewFile(deviceLabel: "Mac", projects: [])
        for id in ["", "a/b", "a b", "é"] {
            XCTAssertThrowsError(try NativeCloudTransport.publishOverview(overview, rootURL: cloud, deviceID: id, accountIsCurrent: { true }))
            XCTAssertThrowsError(try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: binding, deviceID: id, accountIsCurrent: { true }))
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: cloud.path).isEmpty)
    }
}
