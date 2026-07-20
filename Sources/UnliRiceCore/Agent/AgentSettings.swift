import Foundation

/// The settings the background agent needs, in a file both it and the GUI can
/// read.
///
/// **Why a file rather than `UserDefaults`.** The GUI keeps its preferences in
/// `UserDefaults`, whose domain is derived from the running binary's bundle
/// identifier — and `unlirice-agent` is a different binary, launched by launchd,
/// with a different identity. It would read an empty domain and conclude
/// routines were off, forever, while the GUI's toggle sat on. A plain JSON file
/// at a fixed path has no such ambiguity, and it is also inspectable: someone
/// wondering why the daemon isn't doing anything can `cat` it.
///
/// The GUI is the only writer. The agent only reads — it must never be able to
/// change what it is allowed to do.
public struct AgentSettings: Codable, Equatable, Sendable {
    /// Mirrors `AppStore.routinesEnabled`. Off by default here too: an agent
    /// installed but not enabled does nothing, which is the correct behaviour
    /// for something that reads the user's own files.
    public var routinesEnabled: Bool

    /// Mirrors the autonomy slider's raw value (0 Eco / 1 Balanced / 2
    /// Aggressive). Don't renumber these — see PROJECT_NOTES.md.
    public var autonomyLevel: Int

    /// The corpus folder the user pointed the app at, or nil for the default
    /// location. The agent resolves its event log through `DataLocation` with
    /// this, exactly as the GUI does, so the two can never work on different
    /// files while believing they're peers.
    public var dataFolderPath: String?

    /// Folders nominated for `LocalFileImporter`. Empty means that pipeline
    /// finds nothing — there is deliberately no default root.
    public var scanRootPaths: [String]

    /// Whether the agent may leave a "your month is ready" notice. Separate from
    /// `routinesEnabled` because it is a different kind of thing: routines do
    /// work to the corpus, this only leaves a message.
    public var monthlyReviewEnabled: Bool

    public init(
        routinesEnabled: Bool = false,
        autonomyLevel: Int = 1,
        dataFolderPath: String? = nil,
        scanRootPaths: [String] = [],
        monthlyReviewEnabled: Bool = true
    ) {
        self.routinesEnabled = routinesEnabled
        self.autonomyLevel = autonomyLevel
        self.dataFolderPath = dataFolderPath
        self.scanRootPaths = scanRootPaths
        self.monthlyReviewEnabled = monthlyReviewEnabled
    }

    public var scanRoots: [URL] {
        scanRootPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public var autonomy: JanitorAutonomy {
        JanitorAutonomy(rawValue: autonomyLevel) ?? .balanced
    }

    // MARK: - Persistence

    /// Fixed location, independent of which corpus is open — the agent has to
    /// find this before it knows where the corpus is.
    ///
    /// `UNLIRICE_AGENT_SETTINGS` overrides it, for the same reason
    /// `UNLIRICE_DATA_PATH` exists: smoke-running the daemon with routines
    /// switched on must be possible without switching them on for real.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let override = environment["UNLIRICE_AGENT_SETTINGS"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return DataLocation.supportDirectory().appendingPathComponent("agent.json")
    }

    /// Reads settings, or the defaults if the file is missing or unreadable.
    ///
    /// A malformed file yields defaults (routines **off**) rather than throwing:
    /// the failure mode of guessing here is an agent that does work nobody asked
    /// for, so the safe answer is the one that does nothing.
    public static func load(from url: URL = AgentSettings.defaultURL()) -> AgentSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AgentSettings.self, from: data)
        else { return AgentSettings() }
        return settings
    }

    public func save(to url: URL = AgentSettings.defaultURL()) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
