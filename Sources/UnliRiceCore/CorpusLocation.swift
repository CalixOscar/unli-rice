import Foundation

/// Which event log is open, and — just as importantly — *why that one*.
///
/// `DataLocation` answers "what path should this be". This answers "what path
/// did we actually get, and did the user get what they asked for". The
/// difference is the whole point: the app previously resolved a corpus by
/// falling through a chain of `if let`s, and the branch where a chosen folder
/// failed to open had no `else`. The app silently opened the default store
/// instead, kept reporting the chosen folder in the UI, and started writing
/// notes into a corpus the user had never picked.
///
/// Every executable resolves through here — GUI, MCP server, background agent
/// and CLI — because `DataLocation`'s contract is that they are peers over the
/// same file, and four hand-rolled copies of this logic is exactly how they
/// stopped being peers. The sandboxed GUI ignored a plain path while the
/// unsandboxed MCP server honoured it, so a stale bookmark pointed the two at
/// different corpora.
public struct CorpusLocation: Equatable, Sendable {
    /// Why a chosen folder could not be opened. Carried, not swallowed: this is
    /// the text the user needs in order to fix it.
    public enum FolderFailure: Equatable, Sendable {
        /// A folder is remembered but its security-scoped bookmark is gone —
        /// typically settings restored from a backup, or a build that predates
        /// bookmarks being stored at all.
        case noBookmark(path: String?)
        /// The bookmark exists but no longer names a reachable folder: renamed,
        /// moved, deleted, or on a volume that isn't mounted.
        case unresolvable(path: String?)
        /// The bookmark resolved but the system refused access. An unmounted
        /// network share and a revoked permission both land here.
        case accessRefused(path: String)

        public var path: String? {
            switch self {
            case .noBookmark(let path), .unresolvable(let path): return path
            case .accessRefused(let path): return path
            }
        }

        /// Plain language, no jargon — this is shown to someone who has just
        /// opened the app and found their notes missing.
        public var plainReason: String {
            switch self {
            case .noBookmark:
                return "Unli Rice no longer has permission to open it."
            case .unresolvable:
                return "It looks like it was moved, renamed, or deleted."
            case .accessRefused:
                return "The system wouldn't grant access — if it's on an external or network drive, connect that drive first."
            }
        }
    }

    public enum Source: Equatable, Sendable {
        /// `UNLIRICE_DATA_PATH`. Tests and smoke runs.
        case environmentOverride
        /// The folder the user chose, opened successfully.
        case chosenFolder(URL)
        /// The default location, because no folder was ever chosen. Normal.
        case defaultLocation
        /// The default location *despite* a folder having been chosen. Never
        /// normal, and the case this type exists for.
        case defaultAfterFolderFailed(FolderFailure)
    }

    public let url: URL
    public let source: Source

    /// A security-scoped resource the caller must stop accessing when done.
    /// Non-nil only when access was actually started.
    public let scopedFolder: URL?

    /// True when the user asked for a folder and did not get it. The signal the
    /// UI and the notices key off.
    public var didFallBack: Bool {
        if case .defaultAfterFolderFailed = source { return true }
        return false
    }

    /// Whether the *opened* corpus is the default one. Deliberately derived
    /// from what was opened rather than from the saved preference: the old
    /// `usingDefaultDataFolder` read the preference, so during a fallback it
    /// reported the chosen folder while the app was demonstrably reading the
    /// default. An indicator that lies in exactly the situation it exists to
    /// describe is worse than none.
    public var isDefaultLocation: Bool {
        switch source {
        case .chosenFolder: return false
        case .environmentOverride: return false
        case .defaultLocation, .defaultAfterFolderFailed: return true
        }
    }

    public init(url: URL, source: Source, scopedFolder: URL? = nil) {
        self.url = url
        self.source = source
        self.scopedFolder = scopedFolder
    }
}

extension CorpusLocation {
    /// Resolves the corpus, reporting how it got there.
    ///
    /// The bookmark and access calls are injected so the decision table can be
    /// tested without a real security-scoped bookmark, which cannot be
    /// constructed in a unit test.
    ///
    /// A plain path is honoured only outside the sandbox. Inside one it is not
    /// authority — opening it would fail anyway — but it is still *reported*,
    /// because "the folder you chose is X and we couldn't open it" needs X.
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        folderBookmark: Data?,
        folderPath: String?,
        isSandboxed: Bool = DataLocation.isSandboxed,
        defaultURL: URL = DataLocation.defaultEventLogURL(),
        resolveBookmark: (Data) -> URL? = CorpusLocation.resolveSecurityScopedBookmark,
        startAccess: (URL) -> Bool = { $0.startAccessingSecurityScopedResource() }
    ) -> CorpusLocation {
        if let override = environment["UNLIRICE_DATA_PATH"], !override.isEmpty {
            return CorpusLocation(
                url: URL(fileURLWithPath: override),
                source: .environmentOverride
            )
        }

        let trimmedPath = (folderPath?.isEmpty == false) ? folderPath : nil

        if let bookmark = folderBookmark {
            guard let folder = resolveBookmark(bookmark) else {
                return fallback(defaultURL, .unresolvable(path: trimmedPath))
            }
            guard startAccess(folder) else {
                return fallback(defaultURL, .accessRefused(path: folder.path))
            }
            return CorpusLocation(
                url: DataLocation.eventLogURL(inFolder: folder),
                source: .chosenFolder(folder),
                scopedFolder: folder
            )
        }

        // A remembered path with no bookmark. Outside the sandbox this still
        // works and is the long-standing behaviour for source builds; inside
        // one it cannot, and pretending otherwise produced the silent fallback.
        if let path = trimmedPath {
            guard !isSandboxed else {
                return fallback(defaultURL, .noBookmark(path: path))
            }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            return CorpusLocation(
                url: DataLocation.eventLogURL(inFolder: folder),
                source: .chosenFolder(folder)
            )
        }

        return CorpusLocation(url: defaultURL, source: .defaultLocation)
    }

    private static func fallback(_ defaultURL: URL, _ failure: FolderFailure) -> CorpusLocation {
        CorpusLocation(url: defaultURL, source: .defaultAfterFolderFailed(failure))
    }

    public static func resolveSecurityScopedBookmark(_ data: Data) -> URL? {
        var isStale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = .withSecurityScope
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        return try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    /// Convenience for the helper executables, which all read `AgentSettings`.
    public static func resolve(
        settings: AgentSettings,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> CorpusLocation {
        resolve(
            environment: environment,
            folderBookmark: settings.dataFolderBookmark,
            folderPath: settings.dataFolderPath
        )
    }
}
