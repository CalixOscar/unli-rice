import Foundation
import CloudKit

public protocol NativeCloudIdentityProvider {
    var clientID: String { get }
    var environment: String { get }
    func currentUbiquityToken() -> NSObject?
    func canonicalRecordName(isValid: @escaping () -> Bool) throws -> String
}

public struct LiveNativeCloudIdentityProvider: NativeCloudIdentityProvider {
    internal static let guiClients: Set<String> = ["com.calmdownoscar.unlirice", "com.calmdownoscar.unlirice.capture"]
    public static let allowedClients: Set<String> = ["com.calmdownoscar.unlirice", "com.calmdownoscar.unlirice.mcp", "com.calmdownoscar.unlirice.capture"]
    public let clientID: String
    public let environment: String
    public init() throws {
        let id = Bundle.main.bundleIdentifier ?? ""
        guard Self.allowedClients.contains(id) else { throw NativeCloudError.unreadable }
        guard let environment = Bundle.main.object(forInfoDictionaryKey: "NativeCloudEnvironment") as? String,
              ["Development", "Production"].contains(environment) else { throw NativeCloudError.unreadable }
        self.clientID = id; self.environment = environment
    }
    public func currentUbiquityToken() -> NSObject? { FileManager.default.ubiquityIdentityToken as? NSObject }
    public func canonicalRecordName(isValid: @escaping () -> Bool) throws -> String {
        try NativeCloudIdentityLookup.fetch(isValid: isValid) { complete in
            CKContainer(identifier: NativeCloudSession.containerIdentifier).fetchUserRecordID { record, error in
                if let record { complete(.success(record.recordName)) }
                else { complete(.failure(error ?? NativeCloudError.unreadable)) }
            }
        }
    }
}

internal enum NativeCloudIdentityLookup {
    private final class Box {
        private let lock = NSLock()
        private var result: Result<String, Error>?
        private var closed = false
        func receive(_ value: Result<String, Error>) {
            lock.lock(); defer { lock.unlock() }
            guard !closed, result == nil else { return }
            result = value
        }
        func take() -> Result<String, Error>? {
            lock.lock(); defer { lock.unlock() }
            guard let result else { return nil }
            closed = true
            return result
        }
        func close() { lock.lock(); closed = true; lock.unlock() }
    }
    static func fetch(timeout: Duration = .seconds(15), isValid: @escaping () -> Bool,
                      startCallback: (@escaping (Result<String, Error>) -> Void) -> Void) throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let box = Box()
        defer { box.close() }
        guard isValid() else { throw CancellationError() }
        startCallback { box.receive($0) }
        while clock.now < deadline {
            guard isValid() else { throw CancellationError() }
            if let result = box.take() { return try result.get() }
            Thread.sleep(forTimeInterval: 0.01)
        }
        throw NativeCloudError.unreadable
    }
}
