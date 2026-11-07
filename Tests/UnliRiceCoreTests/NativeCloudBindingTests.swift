import XCTest
import CloudKit
@testable import UnliRiceCore
final class NativeCloudBindingTests: XCTestCase {
    func testCancelledOpenDoesNotCreateBinding() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "account" as NSString), allowCreate: true, isValid: { false }))
        XCTAssertFalse(NativeCloudBinding.exists(besideEventLog: log))
    }
    func testBindingNeverRebindsAndBlocksPurge() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: log)
        let note = try NoteService(store: store).createNote(title: "A", body: "B", source: "human")
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "account-a" as NSString), allowCreate: true)
        XCTAssertNotNil(binding.clientTokenArchives["test.client"])
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "account-b" as NSString), allowCreate: true))
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: nil), allowCreate: true))
        XCTAssertThrowsError(try TrashService.purge(noteIDs: [note.id], logURL: log))
        try Data("bad".utf8).write(to: dir.appendingPathComponent("native-cloud-binding.json"))
        XCTAssertTrue(NativeCloudBinding.exists(besideEventLog: log))
        XCTAssertThrowsError(try TrashService.purge(noteIDs: [note.id], logURL: log))
        XCTAssertEqual(try store.readAll().count, 1)
    }

    private func directory() throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("events.jsonl")
        try Data().write(to: log)
        return (dir, log)
    }

    func testDistinctClientsAndKnownChangedTokenNeverFetches() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = NativeCloudIdentityFixture(clientID: "a", token: "a-token" as NSString)
        let b = NativeCloudIdentityFixture(clientID: "b", token: "b-token" as NSString)
        let first = try NativeCloudBinding.open(eventLogURL: log, provider: a, allowCreate: true)
        let second = try NativeCloudBinding.open(eventLogURL: log, provider: b, allowCreate: false)
        XCTAssertEqual(first.bindingID, second.bindingID)
        XCTAssertEqual(Set(second.clientTokenArchives.keys), Set(["a", "b"]))
        var fetched = false
        let changed = NativeCloudIdentityFixture(clientID: "a", token: "changed" as NSString, onLookup: { fetched = true })
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: changed, allowCreate: false))
        XCTAssertFalse(fetched)
        let known = NativeCloudIdentityFixture(clientID: "a", token: "a-token" as NSString, onLookup: { fetched = true })
        _ = try NativeCloudBinding.open(eventLogURL: log, provider: known, allowCreate: false)
        XCTAssertFalse(fetched)
    }

    func testMismatchesAndConsentLeaveBindingUnchanged() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("native-cloud-binding.json")
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        _ = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: true)
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(clientID: "other", recordName: "wrong"), allowCreate: false))
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(environment: "Production"), allowCreate: false))
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: nil), allowCreate: false))
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testLegacyMigrationPreservesIDAndWrongTokenDoesNotWrite() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("native-cloud-binding.json"), id = UUID()
        let archive = try NSKeyedArchiver.archivedData(withRootObject: "original" as NSString, requiringSecureCoding: false)
        let legacy = try JSONSerialization.data(withJSONObject: ["version": 1, "bindingID": id.uuidString, "tokenArchive": archive.base64EncodedString()])
        try legacy.write(to: file)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "wrong" as NSString), allowCreate: false))
        XCTAssertEqual(try Data(contentsOf: file), legacy)
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(token: "original" as NSString), allowCreate: false)
        XCTAssertEqual(binding.bindingID, id)
        XCTAssertEqual(binding.version, 2)
    }

    func testCorruptFutureAndPlaceholderFailClosed() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("native-cloud-binding.json")
        for data in [Data("broken".utf8), Data("{\"version\":99}".utf8)] {
            try data.write(to: file)
            XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: true))
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
        try FileManager.default.removeItem(at: file)
        _ = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object["userRecordName"] = CKCurrentUserDefaultName
        let placeholder = try JSONSerialization.data(withJSONObject: object)
        try placeholder.write(to: file)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: false))
        XCTAssertEqual(try Data(contentsOf: file), placeholder)
    }

    func testCancellationAfterLookupAndReplacementDoNotWrite() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("native-cloud-binding.json")
        var valid = true
        let cancelled = NativeCloudIdentityFixture(onLookup: { valid = false })
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: cancelled, allowCreate: true, isValid: { valid }))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        _ = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: true)
        var replacement = Data()
        let client = NativeCloudIdentityFixture(clientID: "other", onLookup: {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            object["bindingID"] = UUID().uuidString
            replacement = try JSONSerialization.data(withJSONObject: object)
            try replacement.write(to: file)
        })
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: client, allowCreate: false))
        XCTAssertEqual(try Data(contentsOf: file), replacement)
    }

    func testConcurrentEnrollmentMerges() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: true)
        let barrier = DispatchSemaphore(value: 0), ready = DispatchSemaphore(value: 0)
        let group = DispatchGroup(), lock = NSLock()
        var errors = [Error]()
        for id in ["a", "b"] {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                let provider = NativeCloudIdentityFixture(clientID: id, onLookup: { ready.signal(); barrier.wait() })
                do { _ = try NativeCloudBinding.open(eventLogURL: log, provider: provider, allowCreate: false) }
                catch { lock.lock(); errors.append(error); lock.unlock() }
            }
        }
        XCTAssertEqual(ready.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(ready.wait(timeout: .now() + 3), .success)
        barrier.signal(); barrier.signal()
        XCTAssertEqual(group.wait(timeout: .now() + 3), .success)
        XCTAssertTrue(errors.isEmpty)
        let result = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(), allowCreate: false)
        XCTAssertEqual(Set(result.clientTokenArchives.keys), Set(["test.client", "a", "b"]))
    }

    func testLookupTimeoutLateCallbackAndCancellation() throws {
        var callback: ((Result<String, Error>) -> Void)?
        let start = ContinuousClock.now
        XCTAssertThrowsError(try NativeCloudIdentityLookup.fetch(timeout: .milliseconds(30), isValid: { true }) { callback = $0 })
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
        callback?(.success("late"))
        XCTAssertThrowsError(try NativeCloudIdentityLookup.fetch(timeout: .seconds(1), isValid: { false }) { _ in XCTFail("must not start") })
        var valid = true
        XCTAssertThrowsError(try NativeCloudIdentityLookup.fetch(timeout: .seconds(1), isValid: { valid }) { _ in valid = false })
        XCTAssertEqual(try NativeCloudIdentityLookup.fetch(timeout: .seconds(1), isValid: { true }) { $0(.success("ok")) }, "ok")
    }

    func testProductionResolveRejectsOverride() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let previous = getenv("UNLIRICE_DATA_PATH").map { String(cString: $0) }
        setenv("UNLIRICE_DATA_PATH", "fixture", 1)
        defer { if let previous { setenv("UNLIRICE_DATA_PATH", previous, 1) } else { unsetenv("UNLIRICE_DATA_PATH") } }
        XCTAssertThrowsError(try NativeCloudSession.resolve(eventLogURL: log, allowCreate: true)) { error in
            guard case NativeCloudError.unreadable = error else { return XCTFail("unexpected error: \(error)") }
        }
        XCTAssertFalse(NativeCloudBinding.exists(besideEventLog: log))
    }

    func testConcurrentFirstCreationAndLegacyReplacement() throws {
        let (dir, log) = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("native-cloud-binding.json")
        let other = NativeCloudIdentityFixture(clientID: "other", token: "other" as NSString)
        let first = NativeCloudIdentityFixture(onLookup: {
            _ = try NativeCloudBinding.open(eventLogURL: log, provider: other, allowCreate: true)
        })
        let merged = try NativeCloudBinding.open(eventLogURL: log, provider: first, allowCreate: true)
        XCTAssertEqual(Set(merged.clientTokenArchives.keys), Set(["test.client", "other"]))
        let archive = try NSKeyedArchiver.archivedData(withRootObject: "token" as NSString, requiringSecureCoding: false)
        let legacy: (UUID) throws -> Data = { id in
            try JSONSerialization.data(withJSONObject: ["version": 1, "bindingID": id.uuidString, "tokenArchive": archive.base64EncodedString()])
        }
        try legacy(UUID()).write(to: file)
        var replacement = Data()
        let provider = NativeCloudIdentityFixture(onLookup: {
            replacement = try legacy(UUID())
            try replacement.write(to: file)
        })
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: provider, allowCreate: false))
        XCTAssertEqual(try Data(contentsOf: file), replacement)
    }
}
