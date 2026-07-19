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
        if let override = ProcessInfo.processInfo.environment["UNLIRICE_DATA_PATH"] {
            return URL(fileURLWithPath: override)
        }
        let url = defaultEventLogURL()
        migrateLegacyStoreIfNeeded(to: url)
        return url
    }

    /// The path without the env override or the migration side-effect — for
    /// tools that want to name the real log without opening it.
    public static func defaultEventLogURL() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("events.jsonl")
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
