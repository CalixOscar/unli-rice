import Foundation

public enum NativeSyncMode: String, Codable, Sendable {
    case privateDevice = "private", iCloud = "icloud", folder = "folder"
}

public struct NativeSyncPreferences: Codable, Equatable, Sendable {
    public let version: Int
    public let mode: NativeSyncMode
    public init(mode: NativeSyncMode) { self.version = 1; self.mode = mode }
    public enum PreferencesError: Error, LocalizedError {
        case unreadable, unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .unreadable: return "Native sync preferences could not be read."
            case .unsupportedVersion(let version): return "Unsupported native sync preferences version \(version)."
            }
        }
    }
    private static func url(_ log: URL) -> URL { log.deletingLastPathComponent().appendingPathComponent("native-sync-preferences.json") }
    public static func load(besideEventLog log: URL, legacyFolderChosen: Bool) throws -> Self {
        let file = url(log)
        guard FileManager.default.fileExists(atPath: file.path) else { return .init(mode: legacyFolderChosen ? .folder : .privateDevice) }
        let data: Data
        do { data = try Data(contentsOf: file) } catch { throw PreferencesError.unreadable }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let version = object["version"] as? Int else { throw PreferencesError.unreadable }
        guard version == 1 else { throw PreferencesError.unsupportedVersion(version) }
        guard let value = try? JSONDecoder().decode(Self.self, from: data) else { throw PreferencesError.unreadable }
        return value
    }
    public func save(besideEventLog log: URL) throws {
        try JSONEncoder().encode(self).write(to: Self.url(log), options: .atomic)
    }
}
