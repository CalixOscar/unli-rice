import Foundation
import CloudKit


public enum NativeCloudError: Error, LocalizedError {
    case signedOut, differentAccount, unreadable, unsupportedVersion(Int), containerUnavailable, upgradeRequired
    case environmentMismatch(source: String, destination: String)
    public var errorDescription: String? {
        switch self {
        case .environmentMismatch(let source, let destination): return "This iCloud link uses \(source); the app uses \(destination)."
        case .signedOut: return "Sign in to iCloud to sync your notes."
        case .differentAccount: return "These notes are linked to a different iCloud account. Sign in to the original account to resume."
        case .unreadable: return "The iCloud account link could not be read. Sync is paused."
        case .unsupportedVersion(let version): return "Unsupported native sync binding version \(version)."
        case .containerUnavailable: return "The iCloud container is unavailable."
        case .upgradeRequired: return "Open the app that originally linked these notes to finish upgrading the iCloud connection."
        }
    }
}
public struct NativeCloudBinding: Codable, Equatable, Sendable {
    public let version: Int
    public let bindingID: UUID
    public let containerIdentifier: String
    public let environment: String
    public let userRecordName: String
    public var clientTokenArchives: [String: Data]
    public struct CanonicalIdentity: Codable, Equatable, Sendable {
        public let containerIdentifier: String
        public let environment: String
        public let userRecordName: String
    }
    public struct EnvironmentTransition: Codable, Equatable, Sendable {
        public let id: UUID
        public let initiatedByClientID: String
        public let fromEnvironment: String
        public let toEnvironment: String
        public let occurredAt: Date
    }
    public var transportNamespaceID: UUID? = nil
    public var verifiedClientIDs: Set<String>? = nil
    public var previousCanonicalIdentity: CanonicalIdentity? = nil
    public var transition: EnvironmentTransition? = nil
    public var transportStateID: UUID { transportNamespaceID ?? bindingID }
    internal var canonicalIdentity: CanonicalIdentity { .init(containerIdentifier: containerIdentifier, environment: environment, userRecordName: userRecordName) }
    internal static func validRecord(_ name: String) -> Bool { !name.isEmpty && name != CKCurrentUserDefaultName }
    private struct Legacy: Codable { let version: Int; let bindingID: UUID; let tokenArchive: Data }
    private enum Stored { case missing, legacy(Legacy), current(NativeCloudBinding) }
    internal static func url(_ log: URL) -> URL { log.deletingLastPathComponent().appendingPathComponent("native-cloud-binding.json") }
    public static func exists(besideEventLog log: URL) -> Bool { FileManager.default.fileExists(atPath: url(log).path) }
    internal static func matches(_ archive: Data, _ token: NSObject) -> Bool {
        guard let stored = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archive) as? NSObject else { return false }
        return stored.isEqual(token)
    }
    private static func read(_ log: URL, environment: String) throws -> Stored {
        guard exists(besideEventLog: log) else { return .missing }
        guard let data = try? Data(contentsOf: url(log)), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["version"] as? Int else { throw NativeCloudError.unreadable }
        if version == 1 {
            guard let value = try? JSONDecoder().decode(Legacy.self, from: data), (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(value.tokenArchive) as? NSObject) != nil else { throw NativeCloudError.unreadable }
            return .legacy(value)
        }
        guard version == 2 || version == 3 else { throw NativeCloudError.unsupportedVersion(version) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(Self.self, from: data) else { throw NativeCloudError.unreadable }
        try value.validateStructure()
        guard value.environment == environment else { throw NativeCloudError.environmentMismatch(source: value.environment, destination: environment) }
        return .current(value)
    }
    internal static func decodeCurrent(_ data: Data) throws -> Self {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["version"] as? Int else { throw NativeCloudError.unreadable }
        guard version == 2 || version == 3 else { throw NativeCloudError.unsupportedVersion(version) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let value = try? decoder.decode(Self.self, from: data) else { throw NativeCloudError.unreadable }
        try value.validateStructure()
        return value
    }
    internal func validateStructure() throws {
        guard containerIdentifier == NativeCloudSession.containerIdentifier, ["Development", "Production"].contains(environment), Self.validRecord(userRecordName), !clientTokenArchives.isEmpty,
              clientTokenArchives.allSatisfy({ !$0.key.isEmpty && (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData($0.value) as? NSObject) != nil }) else { throw NativeCloudError.unreadable }
        if version == 2 {
            guard transportNamespaceID == nil, verifiedClientIDs == nil, previousCanonicalIdentity == nil, transition == nil else { throw NativeCloudError.unreadable }
        } else if version == 3 {
            guard let transportNamespaceID, transportNamespaceID != bindingID, let verified = verifiedClientIDs, !verified.isEmpty, verified.isSubset(of: Set(clientTokenArchives.keys)),
                  let previous = previousCanonicalIdentity, previous.containerIdentifier == containerIdentifier, previous.environment == "Development", Self.validRecord(previous.userRecordName), environment == "Production",
                  let transition, transition.fromEnvironment == previous.environment, transition.toEnvironment == environment,
                  LiveNativeCloudIdentityProvider.guiClients.contains(transition.initiatedByClientID), verified.contains(transition.initiatedByClientID) else { throw NativeCloudError.unreadable }
        } else { throw NativeCloudError.unsupportedVersion(version) }
    }
    internal func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
    public static func open(eventLogURL: URL, provider: NativeCloudIdentityProvider, allowCreate: Bool, isValid: @escaping () -> Bool = { true }) throws -> Self {
        guard isValid() else { throw CancellationError() }
        guard !provider.clientID.isEmpty, ["Development", "Production"].contains(provider.environment) else { throw NativeCloudError.unreadable }
        guard let token = provider.currentUbiquityToken() else { throw NativeCloudError.signedOut }
        let valid = { isValid() && token.isEqual(provider.currentUbiquityToken()) }
        let initial = try CaptureSyncBridge.withLock(eventLogURL: eventLogURL) { () -> Stored in
            guard valid() else { throw CancellationError() }
            let stored = try read(eventLogURL, environment: provider.environment)
            switch stored {
            case .missing:
                guard allowCreate else { throw NativeCloudError.unreadable }
                try EventStore(readingExisting: eventLogURL).validateNativeHistory()
            case .legacy(let legacy):
                guard matches(legacy.tokenArchive, token) else { throw NativeCloudError.upgradeRequired }
            case .current(let binding):
                if let archive = binding.clientTokenArchives[provider.clientID], !matches(archive, token) { throw NativeCloudError.differentAccount }
            }
            return stored
        }
        if case .current(let binding) = initial, binding.clientTokenArchives[provider.clientID] != nil, binding.version == 2 || binding.verifiedClientIDs?.contains(provider.clientID) == true { return binding }
        let recordName = try provider.canonicalRecordName(isValid: valid)
        guard valid() else { throw CancellationError() }
        guard !recordName.isEmpty, recordName != CKCurrentUserDefaultName else { throw NativeCloudError.unreadable }
        let archive = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: false)
        return try CaptureSyncBridge.withLock(eventLogURL: eventLogURL) {
            guard valid() else { throw CancellationError() }
            let latest = try read(eventLogURL, environment: provider.environment)
            // A lookup may race another enrollment, but must never authorize a
            // replacement of the binding that was checked before the lookup.
            switch (initial, latest) {
            case (.missing, .missing): break
            case (.missing, .current(let current)):
                guard current.userRecordName == recordName else { throw NativeCloudError.differentAccount }
            case (.legacy(let old), .legacy(let current)):
                guard old.bindingID == current.bindingID, old.tokenArchive == current.tokenArchive else { throw NativeCloudError.unreadable }
            case (.legacy(let old), .current(let current)):
                guard old.bindingID == current.bindingID, current.userRecordName == recordName else { throw NativeCloudError.unreadable }
            case (.current(let old), .current(let current)):
                guard old.bindingID == current.bindingID, old.containerIdentifier == current.containerIdentifier,
                      old.environment == current.environment, old.userRecordName == current.userRecordName, old.version == current.version, old.transportNamespaceID == current.transportNamespaceID, old.previousCanonicalIdentity == current.previousCanonicalIdentity, old.transition == current.transition else { throw NativeCloudError.unreadable }
            default: throw NativeCloudError.unreadable
            }
            var binding: Self
            switch latest {
            case .missing:
                guard case .missing = initial, allowCreate else { throw NativeCloudError.unreadable }
                try EventStore(readingExisting: eventLogURL).validateNativeHistory()
                binding = Self(version: 2, bindingID: UUID(), containerIdentifier: NativeCloudSession.containerIdentifier, environment: provider.environment, userRecordName: recordName, clientTokenArchives: [:])
            case .legacy(let legacy):
                guard matches(legacy.tokenArchive, token) else { throw NativeCloudError.upgradeRequired }
                binding = Self(version: 2, bindingID: legacy.bindingID, containerIdentifier: NativeCloudSession.containerIdentifier, environment: provider.environment, userRecordName: recordName, clientTokenArchives: [:])
            case .current(let existing):
                guard existing.userRecordName == recordName else { throw NativeCloudError.differentAccount }
                if let existingArchive = existing.clientTokenArchives[provider.clientID] {
                    guard matches(existingArchive, token) else { throw NativeCloudError.differentAccount }
                    if existing.version == 2 || existing.verifiedClientIDs?.contains(provider.clientID) == true { return existing }
                }
                binding = existing
            }
            if binding.clientTokenArchives[provider.clientID] == nil { binding.clientTokenArchives[provider.clientID] = archive }
            if binding.version == 3 { binding.verifiedClientIDs?.insert(provider.clientID) }
            guard valid() else { throw CancellationError() }
            try binding.encoded().write(to: url(eventLogURL), options: .atomic)
            return binding
        }
    }
}
public struct NativeCloudSession {
    public static let containerIdentifier = "iCloud.com.calmdownoscar.unlirice"
    public let binding: NativeCloudBinding
    public let rootURL: URL
    private let approvedToken: NSObject
    private let provider: NativeCloudIdentityProvider
    private let isValid: () -> Bool
    private let eventLogURL: URL
    internal init(binding: NativeCloudBinding, rootURL: URL, approvedToken: NSObject, provider: NativeCloudIdentityProvider, isValid: @escaping () -> Bool, eventLogURL: URL) {
        self.binding = binding; self.rootURL = rootURL; self.approvedToken = approvedToken
        self.provider = provider; self.isValid = isValid; self.eventLogURL = eventLogURL
    }
    public static func resolve(eventLogURL: URL, allowCreate: Bool, isValid: @escaping () -> Bool = { true }) throws -> Self {
        guard ProcessInfo.processInfo.environment["UNLIRICE_DATA_PATH"].map({ $0.isEmpty }) ?? true else { throw NativeCloudError.unreadable }
        let provider = try LiveNativeCloudIdentityProvider()
        guard let token = provider.currentUbiquityToken() else { throw NativeCloudError.signedOut }
        let valid = { isValid() && token.isEqual(provider.currentUbiquityToken()) }
        let binding = try NativeCloudBinding.open(eventLogURL: eventLogURL, provider: provider, allowCreate: allowCreate, isValid: valid)
        guard valid() else { throw CancellationError() }
        guard let container = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else { throw NativeCloudError.containerUnavailable }
        guard valid() else { throw CancellationError() }
        let root = container.appendingPathComponent("NativeSync-v1", isDirectory: true)
        guard persistedReferenceMatches(binding: binding, eventLogURL: eventLogURL), valid() else { throw CancellationError() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard valid() else { throw CancellationError() }
        return Self(binding: binding, rootURL: root, approvedToken: token, provider: provider, isValid: isValid, eventLogURL: eventLogURL)
    }
    public func isCurrentAccount() -> Bool {
        isValid() && approvedToken.isEqual(provider.currentUbiquityToken()) && Self.persistedReferenceMatches(binding: binding, eventLogURL: eventLogURL)
    }
    private struct PersistedReference: Decodable {
        let version: Int
        let bindingID: UUID
        let containerIdentifier: String
        let environment: String
        let userRecordName: String
        let transportNamespaceID: UUID?
    }
    private static func persistedReferenceMatches(binding: NativeCloudBinding, eventLogURL: URL) -> Bool {
        guard let data = try? Data(contentsOf: NativeCloudBinding.url(eventLogURL)), let current = try? JSONDecoder().decode(PersistedReference.self, from: data) else { return false }
        return current.version == binding.version && current.bindingID == binding.bindingID && current.containerIdentifier == binding.containerIdentifier && current.environment == binding.environment && current.userRecordName == binding.userRecordName && current.transportNamespaceID == binding.transportNamespaceID
    }
}
