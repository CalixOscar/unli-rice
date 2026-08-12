import Foundation

public final class SharedFolderManager: @unchecked Sendable {
    public static let shared = SharedFolderManager()
    private let bookmarkKey = "UnliRiceSharedFolderBookmark"
    private let choiceMadeKey = "UnliRiceSharedFolderChoiceMade"

    private init() {}

    /// Whether the user has been asked where captures should go.
    ///
    /// Distinct from "is a folder set", and the distinction is the whole point:
    /// no bookmark can mean *not asked yet* or *asked, and said no folder*. One
    /// should be prompted, the other must never be prompted again — a private-by-
    /// choice user re-asked on every launch is being nagged toward sharing.
    public var hasChosen: Bool {
        UserDefaults.standard.bool(forKey: choiceMadeKey)
    }

    /// Records that the user wants nothing leaving the phone.
    public func chooseNoFolder() {
        clearBookmark()
        UserDefaults.standard.set(true, forKey: choiceMadeKey)
    }

    /// Lets the prompt appear again — for "change this later" from settings.
    public func resetChoice() {
        UserDefaults.standard.removeObject(forKey: choiceMadeKey)
    }

    public func saveBookmark(for url: URL) throws {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        let data = try url.bookmarkData(
            options: [],
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(true, forKey: choiceMadeKey)
    }

    public func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        if isStale {
            try? saveBookmark(for: url)
        }

        return url
    }

    public func clearBookmark() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
