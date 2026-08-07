import Foundation

public final class SharedFolderManager: @unchecked Sendable {
    public static let shared = SharedFolderManager()
    private let bookmarkKey = "UnliRiceSharedFolderBookmark"

    private init() {}

    public func saveBookmark(for url: URL) throws {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }

        let data = try url.bookmarkData(
            options: [],
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
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
