import Foundation

/// The shapes an MCP client's config actually takes.
///
/// There is no single "MCP config format" — this is the whole reason the setup
/// flow is a table of targets rather than one copy-paste block. Verified against
/// real files on a working machine, not from memory: `~/.codex/config.toml` uses
/// TOML tables, everything else here uses a JSON `mcpServers` object.
public enum MCPConfigFormat: String, Equatable, Sendable {
    /// `{"mcpServers": {"unlirice": {"command": …, "args": […]}}}`
    case mcpServersJSON

    /// `[mcp_servers.unlirice]` with `command` / `args` keys, and a nested
    /// `[mcp_servers.unlirice.env]` table for environment variables.
    case codexTOML

    /// Whether Autopilot may edit this format in place.
    ///
    /// JSON round-trips losslessly through `JSONSerialization`, so merging one
    /// key into someone's config is safe and reversible. TOML does not: writing
    /// it correctly means either a dependency or a hand-rolled parser, and the
    /// file it would be editing (a real `config.toml`) carries plugin tables and
    /// several other servers. Getting that wrong breaks tooling the user relies
    /// on to fix it. Paste is the honest option there.
    public var supportsAutomaticWrite: Bool { self == .mcpServersJSON }
}

/// One MCP client the user can connect Unli Rice to.
public struct MCPTarget: Identifiable, Equatable, Sendable {
    /// Where the config lives, and therefore whether we need the user to tell
    /// us which project they mean.
    public enum Location: Equatable, Sendable {
        /// Relative to the user's home directory — one config for the whole tool.
        case userFile(String)
        /// Relative to a project folder the user picks. Claude Code and
        /// Antigravity both scope MCP servers per project, so there is no
        /// correct path to guess here; the user has to say which project.
        case projectFile(String)
    }

    public let id: String
    public let displayName: String
    /// Shown under the name in the picker, so the user knows what will be
    /// touched before they agree to it.
    public let detail: String
    public let format: MCPConfigFormat
    public let location: Location

    public init(
        id: String, displayName: String, detail: String,
        format: MCPConfigFormat, location: Location
    ) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.format = format
        self.location = location
    }

    public var requiresProjectFolder: Bool {
        if case .projectFile = location { return true }
        return false
    }

    /// True only when the format is writable *and* we know the destination.
    public var supportsAutomaticWrite: Bool { format.supportsAutomaticWrite }

    /// Resolves the config file, given a project folder for project-scoped
    /// targets. Returns nil when a project-scoped target has no folder yet —
    /// the picker uses that to block "Connect" until one is chosen.
    public func configURL(
        projectFolder: URL?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        switch location {
        case .userFile(let relative):
            return homeDirectory.appendingPathComponent(relative)
        case .projectFile(let relative):
            return projectFolder?.appendingPathComponent(relative)
        }
    }

    // MARK: - The catalog

    /// Every target ships only because its format was confirmed against a real
    /// config file or against this repo's own checked-in configs. Tools whose
    /// format would have been written from memory (Grok, OpenCode) are covered
    /// by `custom(name:fileURL:)` instead — a wrong format produces a config
    /// that silently never connects, which is worse than not listing the tool.
    public static let builtIn: [MCPTarget] = [
        MCPTarget(
            id: "claude-code",
            displayName: "Claude Code",
            detail: ".mcp.json in a project folder you choose",
            format: .mcpServersJSON,
            location: .projectFile(".mcp.json")
        ),
        MCPTarget(
            id: "claude-desktop",
            displayName: "Claude Desktop",
            detail: "~/Library/Application Support/Claude/claude_desktop_config.json",
            format: .mcpServersJSON,
            location: .userFile("Library/Application Support/Claude/claude_desktop_config.json")
        ),
        MCPTarget(
            id: "cursor",
            displayName: "Cursor",
            detail: "~/.cursor/mcp.json",
            format: .mcpServersJSON,
            location: .userFile(".cursor/mcp.json")
        ),
        MCPTarget(
            id: "antigravity",
            displayName: "Antigravity",
            detail: ".agents/mcp_config.json in a project folder you choose",
            format: .mcpServersJSON,
            location: .projectFile(".agents/mcp_config.json")
        ),
        MCPTarget(
            id: "codex",
            displayName: "Codex / ChatGPT",
            detail: "~/.codex/config.toml — copy & paste, not edited for you",
            format: .codexTOML,
            location: .userFile(".codex/config.toml")
        )
    ]

    /// A tool not in the catalog. Format is inferred from the file extension,
    /// which is the only signal available without knowing the tool.
    public static func custom(name: String, fileURL: URL) -> MCPTarget {
        let isTOML = fileURL.pathExtension.lowercased() == "toml"
        return MCPTarget(
            id: "custom:\(fileURL.path)",
            displayName: name,
            detail: fileURL.path,
            format: isTOML ? .codexTOML : .mcpServersJSON,
            location: .userFile(fileURL.path)
        )
    }
}

/// The `unlirice` server entry itself, independent of which file it lands in.
public struct MCPServerEntry: Equatable, Sendable {
    public static let serverKey = "unlirice"

    public let command: String
    public let args: [String]
    public let env: [String: String]

    public init(command: String, args: [String], env: [String: String] = [:]) {
        self.command = command
        self.args = args
        self.env = env
    }

    /// The entry for this installation.
    ///
    /// `dataPathOverride` is only ever non-nil when the user has deliberately
    /// pointed the app at a folder — see `AppStore.mcpDataPathOverride`. It must
    /// not carry a path that merely happened to be set by `UNLIRICE_DATA_PATH`
    /// for one run, or a throwaway test path gets baked into a config the user
    /// keeps. (That exact leak showed up in a real run of the previous design.)
    public static func forPackage(at packagePath: URL?, dataPathOverride: URL? = nil) -> MCPServerEntry {
        MCPServerEntry(
            command: "swift",
            args: [
                "run", "--package-path",
                packagePath?.path ?? Autopilot.packagePathPlaceholder,
                "--quiet", "unlirice-mcp"
            ],
            env: dataPathOverride.map { ["UNLIRICE_DATA_PATH": $0.path] } ?? [:]
        )
    }

    /// The JSON object body, as it appears under `mcpServers.unlirice`.
    public var jsonObject: [String: Any] {
        var object: [String: Any] = ["command": command, "args": args]
        if !env.isEmpty { object["env"] = env }
        return object
    }
}
