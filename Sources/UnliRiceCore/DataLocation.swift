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

    /// Runtime check shared by the GUI and helper executables. Plain persisted
    /// paths remain useful to source builds, but a sandboxed process must never
    /// treat one as authority without a security-scoped bookmark.
    public static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Resolves the event-log path, migrating a pre-rename log into place the
    /// first time if one exists.
    public static func eventLogURL() -> URL {
        eventLogURL(persistedFolderPath: nil)
    }

    /// As above, honouring a folder the user has pointed the app at.
    ///
    /// `persistedFolderPath` is passed in rather than read here so this stays
    /// free of `UserDefaults`. The GUI and helpers resolve their shared
    /// security-scoped bookmark through `AgentSettings`; tests and source-only
    /// workflows can still use `UNLIRICE_DATA_PATH` explicitly.
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

    /// The directory where foreign device event shards live (`shards/` beside the event log).
    public static func shardDirectory(besideEventLog eventLog: URL) -> URL {
        eventLog.deletingLastPathComponent().appendingPathComponent("shards", isDirectory: true)
    }

    /// The shard URL for a specific device identifier beside the event log.
    public static func shardURL(id: String, besideEventLog eventLog: URL) -> URL {
        shardDirectory(besideEventLog: eventLog).appendingPathComponent("events-\(id).jsonl")
    }

    /// The path without the env override or the migration side-effect — for
    /// tools that want to name the real log without opening it.
    public static func defaultEventLogURL() -> URL {
        supportDirectory().appendingPathComponent("events.jsonl")
    }

    /// The App Group container's `Unli Rice` directory (falling back to
    /// Application Support for unsigned source builds). This is the app's own
    /// directory, as opposed to whichever folder the corpus currently lives
    /// in — the two are the same by default but need not be.
    ///
    /// Anything here must be app-scoped rather than corpus-scoped, because it
    /// stays put when the user points the app at a different vault.
    /// `AgentSettings` qualifies (it *names* the corpus, so it can't live inside
    /// one); routine state and notices do not, and live beside the event log.
    public static func supportDirectory() -> URL {
        if let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.calmdownoscar.unlirice") {
            return sharedURL.appendingPathComponent(directoryName, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Every location this app has ever used as its default event log, newest
    /// predecessor first. Adoption walks this list when the current default is
    /// absent.
    ///
    /// This exists because the default has moved twice, and only the first move
    /// was handled. `SecondBrain` -> `Application Support/Unli Rice` was the
    /// rename; `Application Support/Unli Rice` -> the App Group container was
    /// the sandboxing change made for the Mac App Store build. The second move
    /// still consulted only the *rename* predecessor, so a machine that had
    /// been running the app between those two changes silently started from the
    /// pre-rename log and orphaned everything written in between.
    public static func predecessorEventLogURLs(
        fileManager: FileManager = .default
    ) -> [URL] {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return [
            support.appendingPathComponent(directoryName, isDirectory: true),
            support.appendingPathComponent(legacyDirectoryName, isDirectory: true)
        ].map { $0.appendingPathComponent("events.jsonl") }
    }

    /// Picks which predecessor log to adopt: the one holding the most events.
    ///
    /// Deliberately *not* "the first that exists". When the default moved into
    /// the App Group container both predecessors existed, and order alone
    /// picked the 150-event pre-rename log over the 724-event one that was
    /// actually in use the day before. Size is the property that actually
    /// distinguishes a live corpus from a stale one, so it is what decides.
    ///
    /// Pure and injectable so the choice can be asserted without touching the
    /// real filesystem.
    public static func storeToAdopt(
        from candidates: [URL],
        eventCount: (URL) -> Int?
    ) -> URL? {
        candidates
            .compactMap { url -> (URL, Int)? in
                guard let count = eventCount(url), count > 0 else { return nil }
                return (url, count)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// Number of events in a log, or nil if it cannot be read.
    ///
    /// Counts newlines rather than parsing: this runs on the launch path, the
    /// only question being asked is "which of these is bigger", and a malformed
    /// tail should not make a real corpus look empty.
    public static func eventCount(atPath url: URL) -> Int? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var count = 0
        while let chunk = try? handle.read(upToCount: 1 << 16), !chunk.isEmpty {
            count += chunk.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
        }
        return count
    }

    /// The set of note ids a log has ever created.
    ///
    /// Used to answer "does this other log hold notes mine doesn't", which is
    /// the only question that reliably identifies a corpus left behind. Event
    /// *count* cannot: after a large ingest the live log outgrows a stranded one
    /// while the stranded notes are still missing from it.
    ///
    /// Tolerant by design — a malformed line is skipped, not fatal. This runs on
    /// the launch path to produce a warning, and a diagnostic that throws is a
    /// diagnostic that gets wrapped in `try?` and silently disabled.
    public static func createdNoteIDs(inLogAt url: URL) -> Set<String>? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.readToEnd() else { return nil }

        var ids: Set<String> = []
        for line in data.split(separator: 0x0A) {
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  object["kind"] as? String == "created",
                  let noteID = object["noteId"] as? String
            else { continue }
            ids.insert(noteID)
        }
        return ids
    }

    /// Carries a log written at a previous default location across to the
    /// current one.
    ///
    /// Copies rather than moves, and only when the destination doesn't exist
    /// yet. The old file is left exactly where it was: this codebase destroys
    /// no note history (decision #2), and that applies to a relocation as much
    /// as to a delete. Worst case the user is left with a harmless stale copy;
    /// the failure mode of a move is losing the only copy of the corpus.
    ///
    /// Note this only ever runs for a *fresh* destination. It cannot reunite a
    /// fork that has already happened — once both logs have real writes, that
    /// is a merge, and a merge is a structural change this codebase proposes
    /// rather than applies.
    static func migrateLegacyStoreIfNeeded(to destination: URL) {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let candidates = predecessorEventLogURLs(fileManager: fileManager)
        guard let source = storeToAdopt(from: candidates, eventCount: eventCount(atPath:)) else { return }

        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            // Non-fatal: EventStore will create an empty log at the new path.
            // The source file is still untouched on disk either way.
            FileHandle.standardError.write(
                Data("unlirice: could not migrate event log from \(source.path): \(error)\n".utf8)
            )
        }
    }
}
