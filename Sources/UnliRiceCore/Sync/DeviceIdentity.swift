import Foundation

/// Persistent device identity for tagging event origins without altering agent source.
public struct DeviceIdentity: Codable, Equatable, Sendable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }

    private static let filename = "device-identity.json"

    /// Loads or initializes the stable device identity for this installation.
    public static func current(inDirectory directory: URL = DataLocation.supportDirectory()) -> DeviceIdentity {
        let fileURL = directory.appendingPathComponent(filename)
        if let data = try? Data(contentsOf: fileURL),
           let identity = try? JSONDecoder().decode(DeviceIdentity.self, from: data) {
            return identity
        }

        let newIdentity = DeviceIdentity(
            id: UUID().uuidString,
            label: Host.current().localizedName ?? "Mac"
        )
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(newIdentity) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return newIdentity
    }
}
