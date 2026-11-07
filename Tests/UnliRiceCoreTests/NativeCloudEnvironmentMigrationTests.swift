import XCTest
@testable import UnliRiceCore

final class NativeCloudEnvironmentMigrationTests: XCTestCase {
    let gui = "com.calmdownoscar.unlirice.capture"
    let mac = "com.calmdownoscar.unlirice"
    func fixture() throws -> (URL, URL, NativeCloudBinding) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("events.jsonl")
        let store = try EventStore(fileURL: log)
        _ = try NoteService(store: store).createNote(title: "Synthetic", body: "Fixture", source: "human")
        let binding = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(clientID: gui), allowCreate: true)
        return (dir, log, binding)
    }
    func target(_ id: String? = nil, token: NSObject? = "token" as NSString, onLookup: (() throws -> Void)? = nil) -> NativeCloudIdentityFixture {
        NativeCloudIdentityFixture(clientID: id ?? gui, environment: "Production", token: token, recordName: "production-record", onLookup: onLookup)
    }
    func testAuthorizationAndTypedMismatch() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(NativeCloudEnvironmentMigration.isGUIClient(gui))
        XCTAssertFalse(NativeCloudEnvironmentMigration.isGUIClient("com.calmdownoscar.unlirice.mcp"))
        for provider in [target("com.calmdownoscar.unlirice.mcp"), target(mac), target(token: "changed" as NSString), NativeCloudIdentityFixture(clientID: gui)] {
            XCTAssertThrowsError(try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: provider))
        }
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: target(), allowCreate: false)) { error in
            guard case NativeCloudError.environmentMismatch(source: "Development", destination: "Production") = error else { return XCTFail("\(error)") }
        }
        let bindingURL = NativeCloudBinding.url(log)
        let malformed = try JSONSerialization.data(withJSONObject: ["version": 2, "environment": "Development"])
        try malformed.write(to: bindingURL)
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: target(), allowCreate: false)) { error in
            guard case NativeCloudError.unreadable = error else { return XCTFail("\(error)") }
        }
    }
    func testSnapshotAndEnrollmentPreserveBytesAndIdempotency() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let oldMac = NativeCloudIdentityFixture(clientID: mac, token: "mac-token" as NSString)
        let old = try NativeCloudBinding.open(eventLogURL: log, provider: oldMac, allowCreate: false)
        let oldBinding = try Data(contentsOf: NativeCloudBinding.url(log)), events = try Data(contentsOf: log)
        let stateURL = NativeCloudTransport.stateURL(log, old)
        let state = try JSONSerialization.data(withJSONObject: ["version": 1, "exportedOffset": 0, "imported": []])
        try state.write(to: stateURL)
        let prefs = NativeSyncPreferences(mode: .iCloud); try prefs.save(besideEventLog: log)
        let prefsData = try Data(contentsOf: dir.appendingPathComponent("native-sync-preferences.json"))
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        let migrated = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        XCTAssertEqual(migrated.version, 3); XCTAssertEqual(migrated.bindingID, old.bindingID)
        XCTAssertNotEqual(migrated.transportStateID, old.bindingID)
        XCTAssertEqual(migrated.clientTokenArchives, old.clientTokenArchives)
        XCTAssertEqual(migrated.verifiedClientIDs, [gui])
        XCTAssertEqual(try Data(contentsOf: log), events); XCTAssertEqual(try Data(contentsOf: stateURL), state)
        let root = dir.appendingPathComponent("NativeSyncRecovery")
        let transitionID = try XCTUnwrap(migrated.transition?.id).uuidString
        let childName = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.hasPrefix(transitionID + "-") })
        let child = root.appendingPathComponent(childName)
        for url in [root, child] { XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o700) }
        for (name, data) in ["binding.json": oldBinding, "events.jsonl": events, "state.json": state, "preferences.json": prefsData] {
            let url = child.appendingPathComponent(name)
            XCTAssertEqual(try Data(contentsOf: url), data)
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
        XCTAssertEqual(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target()).transportStateID, migrated.transportStateID)
        var fetched = false
        XCTAssertThrowsError(try NativeCloudBinding.open(eventLogURL: log, provider: target(mac, token: "changed" as NSString, onLookup: { fetched = true }), allowCreate: false))
        XCTAssertFalse(fetched)
        let enrolled = try NativeCloudBinding.open(eventLogURL: log, provider: target(mac, token: "mac-token" as NSString), allowCreate: false)
        XCTAssertEqual(enrolled.verifiedClientIDs, [gui, mac]); XCTAssertEqual(enrolled.clientTokenArchives[mac], old.clientTokenArchives[mac])
        let unknown = try NativeCloudBinding.open(eventLogURL: log, provider: target("new-client"), allowCreate: false)
        XCTAssertTrue(try XCTUnwrap(unknown.verifiedClientIDs).contains("new-client"))
    }
    func testCancellationFailureAndConcurrentReplacementNeverCommit() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let path = NativeCloudBinding.url(log), before = try Data(contentsOf: path)
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target(), isValid: { false }))
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(), isValid: { false }))
        var valid = true
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(onLookup: { valid = false }), isValid: { valid }))
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(onLookup: { throw NativeCloudError.unreadable })))
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(), beforeRecoveryWrite: { _ in throw NativeCloudError.unreadable }))
        XCTAssertEqual(try Data(contentsOf: path), before)
        let replacementOffer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: replacementOffer, provider: target(onLookup: {
            _ = try NativeCloudBinding.open(eventLogURL: log, provider: NativeCloudIdentityFixture(clientID: "concurrent"), allowCreate: false)
        })))
        XCTAssertNotEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(try NativeCloudBinding.decodeCurrent(Data(contentsOf: path)).version, 2)
    }
    func testInvalidStateAndPreferencesFailClosed() throws {
        let (dir, log, old) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let before = try Data(contentsOf: NativeCloudBinding.url(log)), state = NativeCloudTransport.stateURL(log, old)
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        for offset in [1, 999999] {
            try JSONSerialization.data(withJSONObject: ["version": 1, "exportedOffset": offset, "imported": []]).write(to: state)
            XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target()))
            XCTAssertEqual(try Data(contentsOf: NativeCloudBinding.url(log)), before)
        }
        try FileManager.default.removeItem(at: state)
        try Data("bad".utf8).write(to: dir.appendingPathComponent("native-sync-preferences.json"))
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target()))
        XCTAssertEqual(try Data(contentsOf: NativeCloudBinding.url(log)), before)
    }
    func testOldSessionRejectsPersistedTransition() throws {
        let (dir, log, old) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let provider = NativeCloudIdentityFixture(clientID: gui)
        let session = NativeCloudSession(binding: old, rootURL: dir, approvedToken: "token" as NSString, provider: provider, isValid: { true }, eventLogURL: log)
        XCTAssertTrue(session.isCurrentAccount())
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        _ = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        XCTAssertFalse(session.isCurrentAccount())
    }
    func testNewNamespaceReplaysWithoutDuplicatingEvents() throws {
        let (dir, log, old) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let cloud = dir.appendingPathComponent("cloud")
        try FileManager.default.createDirectory(at: cloud, withIntermediateDirectories: true)
        _ = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: old, deviceID: "test", accountIsCurrent: { true })
        let stateURL = NativeCloudTransport.stateURL(log, old), oldState = try Data(contentsOf: stateURL)
        let beforeEvents = try EventStore(readingExisting: log).readAll().count
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        let migrated = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        XCTAssertFalse(FileManager.default.fileExists(atPath: NativeCloudTransport.stateURL(log, migrated).path))
        let pass = try NativeCloudTransport.synchronize(eventLogURL: log, rootURL: cloud, binding: migrated, deviceID: "test", accountIsCurrent: { true })
        XCTAssertGreaterThan(pass.eventsPublished, 0)
        XCTAssertEqual(pass.eventsImported, 0)
        XCTAssertEqual(try EventStore(readingExisting: log).readAll().count, beforeEvents)
        XCTAssertEqual(try Data(contentsOf: stateURL), oldState)
    }

    func testV3StructuralValidationFailsClosed() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        _ = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        let path = NativeCloudBinding.url(log), good = try Data(contentsOf: path)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: good) as? [String: Any])
        for key in ["transportNamespaceID", "verifiedClientIDs", "previousCanonicalIdentity", "transition"] {
            var altered = original; altered.removeValue(forKey: key)
            XCTAssertThrowsError(try NativeCloudBinding.decodeCurrent(JSONSerialization.data(withJSONObject: altered)))
        }
        var altered = original; altered["verifiedClientIDs"] = ["unknown-client"]
        XCTAssertThrowsError(try NativeCloudBinding.decodeCurrent(JSONSerialization.data(withJSONObject: altered)))
        altered = original; altered["environment"] = "Development"
        XCTAssertThrowsError(try NativeCloudBinding.decodeCurrent(JSONSerialization.data(withJSONObject: altered)))
        altered = original; altered["version"] = 2
        XCTAssertThrowsError(try NativeCloudBinding.decodeCurrent(JSONSerialization.data(withJSONObject: altered)))
        XCTAssertEqual(try Data(contentsOf: path), good)
    }

    func testEverySnapshotWriteFailureCanRetrySameOffer() throws {
        for failureIndex in 1...5 {
            let (dir, log, old) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
            let oldState = NativeCloudTransport.stateURL(log, old)
            try Data("{\"version\":1,\"exportedOffset\":0,\"imported\":[]}".utf8).write(to: oldState)
            try NativeSyncPreferences(mode: .iCloud).save(besideEventLog: log)
            let before = try Data(contentsOf: NativeCloudBinding.url(log))
            let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
            var calls = 0
            XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(), beforeRecoveryWrite: { _ in
                calls += 1; if calls == failureIndex { throw NativeCloudError.unreadable }
            }))
            XCTAssertEqual(try Data(contentsOf: NativeCloudBinding.url(log)), before)
            let recovery = dir.appendingPathComponent("NativeSyncRecovery")
            let partial = try FileManager.default.contentsOfDirectory(atPath: recovery.path)
            XCTAssertEqual(partial.count, 1)
            let migrated = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
            let attempts = try FileManager.default.contentsOfDirectory(atPath: recovery.path)
            XCTAssertEqual(attempts.count, 2); XCTAssertTrue(attempts.contains(partial[0]))
            let complete = try XCTUnwrap(attempts.first { $0 != partial[0] })
            let manifestData = try Data(contentsOf: recovery.appendingPathComponent(complete).appendingPathComponent("manifest.json"))
            let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
            XCTAssertEqual(manifest["transitionID"] as? String, migrated.transition?.id.uuidString)
            XCTAssertEqual(complete, "\(try XCTUnwrap(manifest["transitionID"] as? String))-\(try XCTUnwrap(manifest["attemptID"] as? String))")
            XCTAssertEqual(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target()).transportStateID, migrated.transportStateID)
        }
    }
    func testHelperCannotConsumeGUIOfferAndCancellationCanRetry() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let before = try Data(contentsOf: NativeCloudBinding.url(log))
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target("com.calmdownoscar.unlirice.mcp")))
        var valid = true
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(), isValid: { valid }, beforeRecoveryWrite: { url in
            if url.lastPathComponent == "manifest.json" { valid = false }
        }))
        XCTAssertEqual(try Data(contentsOf: NativeCloudBinding.url(log)), before)
        valid = true
        XCTAssertEqual(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target(), isValid: { valid }).version, 3)
    }
    final class MutableProvider: NativeCloudIdentityProvider {
        var clientID = "com.calmdownoscar.unlirice.capture"
        var environment = "Production"
        var token: NSObject? = "token" as NSString
        func currentUbiquityToken() -> NSObject? { token }
        func canonicalRecordName(isValid: @escaping () -> Bool) throws -> String { token = "different" as NSString; return "production-record" }
    }
    func testTokenChangeDuringLookupCannotCommit() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let before = try Data(contentsOf: NativeCloudBinding.url(log)), provider = MutableProvider()
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: provider)
        XCTAssertThrowsError(try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: provider))
        XCTAssertEqual(try Data(contentsOf: NativeCloudBinding.url(log)), before)
    }
    func testAppendsAfterOfferAreIncludedInRecovery() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        _ = try NoteService(store: EventStore(readingExisting: log)).createNote(title: "Later synthetic", body: "Fixture", source: "human")
        let events = try Data(contentsOf: log)
        let migrated = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        let root = dir.appendingPathComponent("NativeSyncRecovery")
        let child = try XCTUnwrap(FileManager.default.contentsOfDirectory(atPath: root.path).first { $0.hasPrefix(migrated.transition!.id.uuidString + "-") })
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(child).appendingPathComponent("events.jsonl")), events)
    }
    func testNamespaceCannotAliasBindingID() throws {
        let (dir, log, _) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let offer = try NativeCloudEnvironmentMigration.offer(eventLogURL: log, provider: target())
        _ = try NativeCloudEnvironmentMigration.migrate(offer: offer, provider: target())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: NativeCloudBinding.url(log))) as? [String: Any])
        object["transportNamespaceID"] = object["bindingID"]
        XCTAssertThrowsError(try NativeCloudBinding.decodeCurrent(JSONSerialization.data(withJSONObject: object)))
    }
    func testStateValidationAcceptsDataWithNonzeroStartIndex() throws {
        let (dir, log, old) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let events = try Data(contentsOf: log)
        var padded = Data([42]); padded.append(events)
        let slice = padded.dropFirst()
        XCTAssertNotEqual(slice.startIndex, 0)
        let state = NativeCloudTransport.stateURL(log, old)
        let bytes = try JSONSerialization.data(withJSONObject: ["version": 1, "exportedOffset": events.count, "imported": []])
        try bytes.write(to: state)
        XCTAssertEqual(try NativeCloudTransport.validatedExistingState(state, source: slice), bytes)
    }

}
