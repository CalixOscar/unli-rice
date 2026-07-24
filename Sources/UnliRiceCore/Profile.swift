import Foundation

/// Represents a Profile, which corresponds 1:1 with a named Vault folder.
public struct Profile: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var folderPath: String
    public var isMaster: Bool
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        isMaster: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.isMaster = isMaster
        self.createdAt = createdAt
    }

    public var folderURL: URL {
        URL(fileURLWithPath: folderPath, isDirectory: true)
    }
}

/// Registry managing profiles and active profile selection.
/// Saved to Application Support (`profiles.json`).
public final class ProfileRegistry: ObservableObject, @unchecked Sendable {
    @Published public private(set) var profiles: [Profile] = []
    @Published public private(set) var activeProfileID: UUID?

    private let storageURL: URL

    public init(storageURL: URL = ProfileRegistry.defaultStorageURL) {
        self.storageURL = storageURL
        load()
    }

    public static var defaultStorageURL: URL {
        DataLocation.supportDirectory().appendingPathComponent("profiles.json")
    }

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    public var masterProfile: Profile? {
        profiles.first { $0.isMaster }
    }

    public func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode(ProfileRegistryEnvelope.self, from: data)
        else {
            // Default profile setup if none exists
            let defaultFolder = DataLocation.defaultEventLogURL().deletingLastPathComponent().path
            let defaultProfile = Profile(name: "Default Profile", folderPath: defaultFolder, isMaster: true)
            profiles = [defaultProfile]
            activeProfileID = defaultProfile.id
            save()
            return
        }
        profiles = decoded.profiles
        activeProfileID = decoded.activeProfileID ?? decoded.profiles.first?.id
    }

    public func save() {
        let envelope = ProfileRegistryEnvelope(profiles: profiles, activeProfileID: activeProfileID)
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("unlirice: failed to save profile registry: \(error)\n".utf8))
        }
    }

    @discardableResult
    public func createProfile(name: String, folderPath: String, isMaster: Bool = false) -> Profile {
        var updatedProfiles = profiles
        if isMaster {
            updatedProfiles = updatedProfiles.map {
                Profile(id: $0.id, name: $0.name, folderPath: $0.folderPath, isMaster: false, createdAt: $0.createdAt)
            }
        }
        let profile = Profile(name: name, folderPath: folderPath, isMaster: isMaster)
        updatedProfiles.append(profile)
        profiles = updatedProfiles
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
        save()
        return profile
    }

    public func switchActiveProfile(to id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        save()
    }

    public func setMasterProfile(id: UUID) {
        profiles = profiles.map {
            Profile(id: $0.id, name: $0.name, folderPath: $0.folderPath, isMaster: $0.id == id, createdAt: $0.createdAt)
        }
        save()
    }

    public func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
        save()
    }
}

private struct ProfileRegistryEnvelope: Codable {
    let profiles: [Profile]
    let activeProfileID: UUID?
}
