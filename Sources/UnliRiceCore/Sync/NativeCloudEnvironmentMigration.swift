import Foundation
import CryptoKit
import Darwin

public enum NativeCloudEnvironmentMigration {
    public struct Offer {
        fileprivate let source: Data
        fileprivate let eventLogURL: URL
        fileprivate let clientID: String
        fileprivate let target: String
        fileprivate let transitionID: UUID
        fileprivate init(source: Data, eventLogURL: URL, clientID: String) {
            self.source = source; self.eventLogURL = eventLogURL; self.clientID = clientID
            self.target = "Production"; self.transitionID = UUID()
        }
    }

    public static func offer(eventLogURL: URL, isValid: @escaping () -> Bool = { true }) throws -> Offer {
        let provider = try LiveNativeCloudIdentityProvider()
        guard isGUIClient(Bundle.main.bundleIdentifier ?? ""), provider.clientID == Bundle.main.bundleIdentifier else { throw NativeCloudError.unreadable }
        return try offer(eventLogURL: eventLogURL, provider: provider, isValid: isValid)
    }
    public static func migrate(offer: Offer, isValid: @escaping () -> Bool = { true }) throws -> NativeCloudBinding {
        let provider = try LiveNativeCloudIdentityProvider()
        guard isGUIClient(Bundle.main.bundleIdentifier ?? ""), provider.clientID == Bundle.main.bundleIdentifier else { throw NativeCloudError.unreadable }
        return try migrate(offer: offer, provider: provider, isValid: isValid)
    }
    internal static func isGUIClient(_ id: String) -> Bool { LiveNativeCloudIdentityProvider.guiClients.contains(id) }
    internal static func offer(eventLogURL: URL, provider: NativeCloudIdentityProvider, isValid: @escaping () -> Bool = { true }) throws -> Offer {
        guard isGUIClient(provider.clientID), provider.environment == "Production" else { throw NativeCloudError.unreadable }
        guard let token = provider.currentUbiquityToken() else { throw NativeCloudError.signedOut }
        return try CaptureSyncBridge.withLock(eventLogURL: eventLogURL) {
            guard isValid(), token.isEqual(provider.currentUbiquityToken()) else { throw CancellationError() }
            let bytes = try Data(contentsOf: NativeCloudBinding.url(eventLogURL))
            let source = try NativeCloudBinding.decodeCurrent(bytes)
            guard source.version == 2, source.environment == "Development", let archive = source.clientTokenArchives[provider.clientID], NativeCloudBinding.matches(archive, token) else { throw NativeCloudError.unreadable }
            return Offer(source: bytes, eventLogURL: eventLogURL, clientID: provider.clientID)
        }
    }
    internal static func migrate(offer: Offer, provider: NativeCloudIdentityProvider, isValid: @escaping () -> Bool = { true }, beforeRecoveryWrite: (URL) throws -> Void = { _ in }) throws -> NativeCloudBinding {
        guard isGUIClient(provider.clientID), provider.clientID == offer.clientID, provider.environment == offer.target, offer.target == "Production" else { throw NativeCloudError.unreadable }
        guard let token = provider.currentUbiquityToken() else { throw NativeCloudError.signedOut }
        let valid = { isValid() && token.isEqual(provider.currentUbiquityToken()) }
        let original = try NativeCloudBinding.decodeCurrent(offer.source)
        guard original.version == 2, original.environment == "Development", let archive = original.clientTokenArchives[provider.clientID], NativeCloudBinding.matches(archive, token) else { throw NativeCloudError.unreadable }
        let already: NativeCloudBinding? = try CaptureSyncBridge.withLock(eventLogURL: offer.eventLogURL) {
            guard valid() else { throw CancellationError() }
            let currentData = try Data(contentsOf: NativeCloudBinding.url(offer.eventLogURL))
            if currentData == offer.source { return nil }
            let current = try NativeCloudBinding.decodeCurrent(currentData)
            guard current.transition?.id == offer.transitionID, current.bindingID == original.bindingID, current.previousCanonicalIdentity == original.canonicalIdentity, current.clientTokenArchives[provider.clientID] == archive else { throw NativeCloudError.unreadable }
            return current
        }
        if let already { return already }
        let recordName = try provider.canonicalRecordName(isValid: valid)
        guard valid() else { throw CancellationError() }
        guard NativeCloudBinding.validRecord(recordName) else { throw NativeCloudError.unreadable }
        return try CaptureSyncBridge.withLock(eventLogURL: offer.eventLogURL) {
            guard valid() else { throw CancellationError() }
            let sourceData = try Data(contentsOf: NativeCloudBinding.url(offer.eventLogURL))
            if sourceData != offer.source {
                let current = try NativeCloudBinding.decodeCurrent(sourceData)
                guard current.transition?.id == offer.transitionID, current.bindingID == original.bindingID, current.previousCanonicalIdentity == original.canonicalIdentity, current.clientTokenArchives[provider.clientID] == archive else { throw NativeCloudError.unreadable }
                return current
            }
            let eventData = try EventStore(readingExisting: offer.eventLogURL).validatedNativeRawSnapshot()
            let state = try NativeCloudTransport.validatedExistingState(NativeCloudTransport.stateURL(offer.eventLogURL, original), source: eventData)
            let prefsURL = offer.eventLogURL.deletingLastPathComponent().appendingPathComponent("native-sync-preferences.json")
            let prefs: Data?
            if FileManager.default.fileExists(atPath: prefsURL.path) {
                let bytes = try Data(contentsOf: prefsURL)
                guard let value = try? JSONDecoder().decode(NativeSyncPreferences.self, from: bytes), value.version == 1 else { throw NativeSyncPreferences.PreferencesError.unreadable }
                prefs = bytes
            } else { prefs = nil }
            var files = ["binding.json": offer.source, "events.jsonl": eventData]
            if let state { files["state.json"] = state }
            if let prefs { files["preferences.json"] = prefs }
            try writeRecovery(files: files, beside: offer.eventLogURL, id: offer.transitionID, stateAbsent: state == nil, beforeWrite: beforeRecoveryWrite)
            guard valid(), try Data(contentsOf: NativeCloudBinding.url(offer.eventLogURL)) == offer.source else { throw CancellationError() }
            let transition = NativeCloudBinding.EnvironmentTransition(id: offer.transitionID, initiatedByClientID: provider.clientID, fromEnvironment: "Development", toEnvironment: "Production", occurredAt: Date())
            let migrated = NativeCloudBinding(version: 3, bindingID: original.bindingID, containerIdentifier: original.containerIdentifier, environment: "Production", userRecordName: recordName, clientTokenArchives: original.clientTokenArchives, transportNamespaceID: UUID(), verifiedClientIDs: [provider.clientID], previousCanonicalIdentity: original.canonicalIdentity, transition: transition)
            try migrated.validateStructure()
            try migrated.encoded().write(to: NativeCloudBinding.url(offer.eventLogURL), options: .atomic)
            return migrated
        }
    }
    private static func writeRecovery(files: [String: Data], beside log: URL, id: UUID, stateAbsent: Bool, beforeWrite: (URL) throws -> Void) throws {
        let fm = FileManager.default
        let root = log.deletingLastPathComponent().appendingPathComponent("NativeSyncRecovery", isDirectory: true)
        if !fm.fileExists(atPath: root.path) { try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        let attributes = try fm.attributesOfItem(atPath: root.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory, (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else { throw NativeCloudError.unreadable }
        let attemptID = UUID()
        let directory = root.appendingPathComponent("\(id.uuidString)-\(attemptID.uuidString)", isDirectory: true)
        guard Darwin.mkdir(directory.path, 0o700) == 0 else { throw NativeCloudError.unreadable }
        var digests = [String: String]()
        for (name, bytes) in files {
            let url = directory.appendingPathComponent(name)
            try beforeWrite(url)
            try exclusiveWrite(bytes, to: url)
            guard try Data(contentsOf: url) == bytes else { throw NativeCloudError.unreadable }
            digests[name] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let manifest = try JSONSerialization.data(withJSONObject: ["sourceSchema": 2, "transitionID": id.uuidString, "attemptID": attemptID.uuidString, "stateAbsent": stateAbsent, "sha256": digests], options: [.sortedKeys])
        let url = directory.appendingPathComponent("manifest.json")
        try beforeWrite(url); try exclusiveWrite(manifest, to: url)
        guard try Data(contentsOf: url) == manifest else { throw NativeCloudError.unreadable }
        try syncDirectory(directory)
        try syncDirectory(root)
    }
    private static func syncDirectory(_ url: URL) throws {
        let fd = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw NativeCloudError.unreadable }
        defer { Darwin.close(fd) }
        guard Darwin.fsync(fd) == 0 else { throw NativeCloudError.unreadable }
    }
    private static func exclusiveWrite(_ bytes: Data, to url: URL) throws {
        let fd = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NativeCloudError.unreadable }
        defer { Darwin.close(fd) }
        try bytes.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw NativeCloudError.unreadable }
                offset += n
            }
        }
        guard Darwin.fsync(fd) == 0 else { throw NativeCloudError.unreadable }
    }
}
