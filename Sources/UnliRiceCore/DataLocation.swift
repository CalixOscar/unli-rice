import Foundation

/// Where the event log lives, and the one place that decides it.
///
/// The GUI and the MCP server are peers over the same file (see
/// PROJECT_NOTES.md) — that only holds if they agree on the path, so both call
/// here rather than each computing it. Every caller gets the same answer,
/// including the `UNLIRICE_DATA_PATH` override tests and smoke runs use to stay
/// off real data.
public enum DataLocation {
    static let directoryName = "Unli Rice"

    /// The pre-rename directory. Only read from, never written to — see
    /// `migrateLegacyStoreIfNeeded`.
    static let legacyDirectoryName = "SecondBrain"

    /// Resolves the event-log path, migrating a pre-rename log into place the
    /// first time if one exists.
    public static func eventLogURL() -> URL {
        eventLogURL(persistedFolderPath: nil)
    }

    /// As above, honouring a folder the user has pointed the app at.
    ///
    /// `persistedFolderPath` is passed in rather than read here so this stays
    /// free of `UserDefaults` — `unlirice-mcp` links this same file and has no
    /// business reading the GUI's preferences. The GUI supplies it; the server
    /// gets its equivalent through `UNLIRICE_DATA_PATH`, which the Get Started
    /// wizard writes into the MCP config block it generates.
    public static func eventLogURL(persistedFolderPath: String?) -> URL {
        let url = resolvedEventLogURL(
            environment: ProcessInfo.processInfo.environment,
            persistedFolderPath: persistedFolderPath
        )
        // Only the default location can inherit a pre-rename log. A user who
        // has pointed the app somewhere else is asking for that corpus, not for
        // an old one to be copied into it.
        if url == defaultEventLogURL() {
            migrateLegacyStoreIfNeeded(to: url)
        }
        return url
    }

    /// The precedence rule, as a pure function so it can be tested without
    /// touching real defaults or the real environment.
    ///
    /// `UNLIRICE_DATA_PATH` wins over a persisted folder deliberately: it's what
    /// tests and smoke runs use to stay off real data, and a persisted
    /// preference silently overriding it would let a test write into whatever
    /// vault the user last opened.
    public static func resolvedEventLogURL(
        environment: [String: String],
        persistedFolderPath: String?,
        defaultURL: URL? = nil
    ) -> URL {
        if let override = environment["UNLIRICE_DATA_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        if let folder = persistedFolderPath, !folder.isEmpty {
            return eventLogURL(inFolder: URL(fileURLWithPath: folder, isDirectory: true))
        }
        return defaultURL ?? defaultEventLogURL()
    }

    /// The log file inside a folder the user chose. One place decides the
    /// filename so the GUI, the generated MCP config, and any future importer
    /// can't disagree about it.
    public static func eventLogURL(inFolder folder: URL) -> URL {
        folder.appendingPathComponent("events.jsonl")
    }

    /// The path without the env override or the migration side-effect — for
    /// tools that want to name the real log without opening it.
    public static func defaultEventLogURL() -> URL {
        supportDirectory().appendingPathComponent("events.jsonl")
    }

    /// `~/Library/Application Support/Unli Rice`. The app's own directory, as
    /// opposed to whichever folder the corpus currently lives in — the two are
    /// the same by default but need not be.
    ///
    /// Anything here must be app-scoped rather than corpus-scoped, because it
    /// stays put when the user points the app at a different vault.
    /// `AgentSettings` qualifies (it *names* the corpus, so it can't live inside
    /// one); routine state and notices do not, and live beside the event log.
    public static func supportDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Carries a log written under the old app name across to the new location.
    ///
    /// Copies rather than moves, and only when the destination doesn't exist
    /// yet. The old file is left exactly where it was: this codebase destroys
    /// no note history (decision #2), and that applies to a rename as much as
    /// to a delete. Worst case the user is left with a harmless stale copy;
    /// the failure mode of a move is losing the only copy of 150 events.
    static func migrateLegacyStoreIfNeeded(to destination: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support
            .appendingPathComponent(legacyDirectoryName, isDirectory: true)
            .appendingPathComponent("events.jsonl")
        guard fileManager.fileExists(atPath: legacy.path) else { return }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: legacy, to: destination)
        } catch {
            // Non-fatal: EventStore will create an empty log at the new path.
            // The legacy file is still untouched on disk either way.
            FileHandle.standardError.write(
                Data("unlirice: could not migrate legacy event log: \(error)\n".utf8)
            )
        }
    }
}
