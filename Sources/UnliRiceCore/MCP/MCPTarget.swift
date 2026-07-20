import Foundation

/// The shapes an MCP client's config actually takes.
///
/// There is no single "MCP config format" — this is the whole reason the setup
/// flow is a table of targets rather than one copy-paste block. Verified against
/// real files on a working machine, not from memory: `~/.codex/config.toml` uses
/// TOML tables, everything else here uses a JSON `mcpServers` object.
public enum MCPConfigFormat: Equatable, Sendable {
    /// `{"mcpServers": {"unlirice": {"command": …, "args": […]}}}`
    case mcpServersJSON

    /// `[mcp_servers.unlirice]` with `command` / `args` keys, and a nested
    /// `[mcp_servers.unlirice.env]` table for environment variables.
    case codexTOML

}

/// One MCP client the user can connect Unli Rice to.
public struct MCPTarget: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    /// Shown under the name so the user knows where to paste the copied block.
    public let detail: String
    public let format: MCPConfigFormat

    public init(
        id: String,
        displayName: String,
        detail: String,
        format: MCPConfigFormat
    ) {
        self.id = id
        self.displayName = displayName
        self.detail = detail
        self.format = format
    }

    /// The lowercase source identifier used by the agent (e.g. "claude", "cursor").
    public var agentSource: String {
        switch id {
        case "claude-code", "claude-desktop":
            return "claude"
        case "cursor":
            return "cursor"
        case "antigravity":
            return "antigravity"
        case "codex":
            return "codex"
        default:
            if id.hasPrefix("custom:") {
                let sanitized = displayName.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }
                    .joined(separator: "-")
                return sanitized.isEmpty ? "assistant" : sanitized
            }
            return "assistant"
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
            format: .mcpServersJSON
        ),
        MCPTarget(
            id: "claude-desktop",
            displayName: "Claude Desktop",
            detail: "~/Library/Application Support/Claude/claude_desktop_config.json",
            format: .mcpServersJSON
        ),
        MCPTarget(
            id: "cursor",
            displayName: "Cursor",
            detail: "~/.cursor/mcp.json",
            format: .mcpServersJSON
        ),
        MCPTarget(
            id: "antigravity",
            displayName: "Antigravity",
            detail: ".agents/mcp_config.json in a project folder you choose",
            format: .mcpServersJSON
        ),
        MCPTarget(
            id: "codex",
            displayName: "Codex / ChatGPT",
            detail: "~/.codex/config.toml — copy & paste, not edited for you",
            format: .codexTOML
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
            format: isTOML ? .codexTOML : .mcpServersJSON
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

    /// The entry shipped by the installed app.
    ///
    /// App Store customers do not have this source package (and should not
    /// need Swift installed), so a production config must point at the MCP
    /// helper embedded in the app bundle. The helper reads the shared app-group
    /// settings to find the selected corpus; no external filesystem path is
    /// smuggled through an environment variable.
    public static func forInstalledApp(at appBundleURL: URL) -> MCPServerEntry {
        MCPServerEntry(
            command: appBundleURL
                .appendingPathComponent("Contents/MacOS/unlirice-mcp")
                .path,
            args: []
        )
    }

    /// The JSON object body, as it appears under `mcpServers.unlirice`.
    public var jsonObject: [String: Any] {
        var object: [String: Any] = ["command": command, "args": args]
        if !env.isEmpty { object["env"] = env }
        return object
    }
}
