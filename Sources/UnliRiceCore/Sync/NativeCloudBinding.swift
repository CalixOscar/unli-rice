import Foundation
import CloudKit


public enum NativeCloudError: Error, LocalizedError {
    case signedOut, differentAccount, unreadable, unsupportedVersion(Int), containerUnavailable, upgradeRequired
    public var errorDescription: String? {
        switch self {
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
    private struct Legacy: Codable { let version: Int; let bindingID: UUID; let tokenArchive: Data }
    private enum Stored { case missing, legacy(Legacy), current(NativeCloudBinding) }
    private static func url(_ log: URL) -> URL { log.deletingLastPathComponent().appendingPathComponent("native-cloud-binding.json") }
    public static func exists(besideEventLog log: URL) -> Bool { FileManager.default.fileExists(atPath: url(log).path) }
    private static func matches(_ archive: Data, _ token: NSObject) -> Bool {
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
        guard version == 2 else { throw NativeCloudError.unsupportedVersion(version) }
        guard let value = try? JSONDecoder().decode(Self.self, from: data), value.containerIdentifier == NativeCloudSession.containerIdentifier, value.environment == environment, !value.userRecordName.isEmpty, value.userRecordName != CKCurrentUserDefaultName, !value.clientTokenArchives.isEmpty,
              value.clientTokenArchives.allSatisfy({ !$0.key.isEmpty && (try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData($0.value) as? NSObject) != nil }) else { throw NativeCloudError.unreadable }
        return .current(value)
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
        if case .current(let binding) = initial, binding.clientTokenArchives[provider.clientID] != nil { return binding }
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
                      old.environment == current.environment, old.userRecordName == current.userRecordName else { throw NativeCloudError.unreadable }
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
                    return existing
                }
                binding = existing
            }
            binding.clientTokenArchives[provider.clientID] = archive
            guard valid() else { throw CancellationError() }
            try JSONEncoder().encode(binding).write(to: url(eventLogURL), options: .atomic)
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
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard valid() else { throw CancellationError() }
        return Self(binding: binding, rootURL: root, approvedToken: token, provider: provider, isValid: isValid)
    }
    public func isCurrentAccount() -> Bool { isValid() && approvedToken.isEqual(provider.currentUbiquityToken()) }
}
