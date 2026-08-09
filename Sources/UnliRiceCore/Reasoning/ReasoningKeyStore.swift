import Foundation
import Security

/// Where the user's API key lives.
///
/// A protocol rather than a bare Keychain call for one reason: the test suite
/// must never touch the real login keychain, and the app must never be able to
/// fall back to something weaker. `InMemoryReasoningKeyStore` is the test seam;
/// `KeychainReasoningKeyStore` is the only thing the app constructs.
public protocol ReasoningKeyStore: Sendable {
    func key(forHost host: String) throws -> String?
    func setKey(_ key: String, forHost host: String) throws
    func removeKey(forHost host: String) throws
}

/// `kSecClassGenericPassword`, one item per provider host.
///
/// There is no Keychain usage anywhere else in this codebase, so this is
/// greenfield — and it deliberately follows neither existing storage pattern:
///
/// - **Not `UserDefaults`.** Readable by anything running as this user, and
///   every other setting in `AppStore` lives there. A key must not.
/// - **Not `AgentSettings`.** That is a plain JSON file at a fixed path whose
///   own doc comment invites someone to `cat` it to debug the daemon. A key
///   there is a key on disk in plaintext.
///
/// Keyed by host so a user with keys at two providers keeps both, and so the
/// disclosure sheet's "your key for `api.example.com`" is literally true.
///
/// Phase 1 keeps this in the main app only — no `keychain-access-groups`
/// entitlement, nothing shared with `unlirice-agent`. Unattended operation is
/// Phase 2 and needs that decision made deliberately, because it is a real App
/// Store review surface (see §8 of docs/BYO_LLM.md).
public struct KeychainReasoningKeyStore: ReasoningKeyStore {
    public enum Failure: Error, CustomStringConvertible {
        case keychain(OSStatus)

        public var description: String {
            switch self {
            case .keychain(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
                return "The keychain refused: \(detail)"
            }
        }
    }

    /// Stable across releases — changing it would orphan every stored key.
    public static let service = "com.calmdownoscar.unlirice.reasoning"

    private let service: String

    public init(service: String = KeychainReasoningKeyStore.service) {
        self.service = service
    }

    public func key(forHost host: String) throws -> String? {
        var query = baseQuery(host)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw Failure.keychain(status) }
        guard let data = item as? Data, let key = String(data: data, encoding: .utf8) else { return nil }
        return key
    }

    public func setKey(_ key: String, forHost host: String) throws {
        let data = Data(key.utf8)
        let query = baseQuery(host)

        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw Failure.keychain(update) }

        var insert = query
        insert[kSecValueData as String] = data
        // The key is useless without this Mac unlocked, and never needs reading
        // while it is locked — nothing here runs unattended in Phase 1.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    public func removeKey(forHost host: String) throws {
        let status = SecItemDelete(baseQuery(host) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Failure.keychain(status)
        }
    }

    private func baseQuery(_ host: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host.lowercased()
        ]
    }
}

/// Test-only. Never constructed by the app — the real store is the only thing
/// `AppStore` reaches for, so there is no path by which a key ends up somewhere
/// weaker than the keychain in a shipped build.
public final class InMemoryReasoningKeyStore: ReasoningKeyStore, @unchecked Sendable {
    private var keys: [String: String] = [:]
    private let lock = NSLock()

    public init(keys: [String: String] = [:]) { self.keys = keys }

    public func key(forHost host: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return keys[host.lowercased()]
    }

    public func setKey(_ key: String, forHost host: String) throws {
        lock.lock(); defer { lock.unlock() }
        keys[host.lowercased()] = key
    }

    public func removeKey(forHost host: String) throws {
        lock.lock(); defer { lock.unlock() }
        keys[host.lowercased()] = nil
    }
}
