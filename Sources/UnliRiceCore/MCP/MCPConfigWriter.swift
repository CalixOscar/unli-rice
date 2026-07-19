import Foundation

/// Writes the `unlirice` entry into an MCP client's config, and renders the
/// paste-it-yourself equivalent for the formats it refuses to edit.
///
/// This is the one place in the codebase that modifies a file the user owns and
/// this app did not create. Three rules make that acceptable, and none of them
/// are optional:
///
/// 1. **Never write a file we could not read.** If an existing config doesn't
///    parse as JSON, the write is refused and the user is told to paste
///    instead. A config we can't parse is one we'd be replacing wholesale, and
///    the tool that config belongs to is very often the tool they'd use to fix
///    it.
/// 2. **Back up before changing anything.** Timestamped, alongside the original.
/// 3. **Touch exactly one key.** Every other key at every level is carried
///    through untouched — `claude_desktop_config.json` on a real machine holds
///    `coworkUserFilesPath` and `preferences` next to `mcpServers`, and other
///    MCP servers live inside `mcpServers` itself.
public enum MCPConfigWriter {
    public enum Outcome: Equatable {
        /// The config file didn't exist; we created it.
        case created(URL)
        /// An existing config gained or changed the `unlirice` entry.
        case updated(URL, backup: URL)
        /// The entry was already exactly right — nothing written, no backup.
        case unchanged(URL)
    }

    public enum WriteError: Error, CustomStringConvertible {
        case unreadableJSON(URL)
        case unsupportedFormat(MCPConfigFormat)

        public var description: String {
            switch self {
            case .unreadableJSON(let url):
                return "\(url.lastPathComponent) isn't valid JSON, so it wasn't changed. Copy the block below in by hand instead."
            case .unsupportedFormat(let format):
                return "\(format.rawValue) configs aren't edited automatically — copy the block below in by hand."
            }
        }
    }

    /// Merges `entry` into a JSON `mcpServers` config at `url`.
    public static func merge(
        entry: MCPServerEntry,
        serverKey: String = MCPServerEntry.serverKey,
        intoJSONAt url: URL,
        now: Date = Date()
    ) throws -> Outcome {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path) else {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let fresh: [String: Any] = ["mcpServers": [serverKey: entry.jsonObject]]
            try write(fresh, to: url)
            return .created(url)
        }

        let data = try Data(contentsOf: url)
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Deliberately before any backup or write: a config we can't parse
            // is one we would be destroying, not merging.
            throw WriteError.unreadableJSON(url)
        }

        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        if let existing = servers[serverKey] as? [String: Any],
           NSDictionary(dictionary: existing).isEqual(to: entry.jsonObject) {
            return .unchanged(url)
        }

        let backup = backupURL(for: url, now: now)
        try? fileManager.removeItem(at: backup)
        try fileManager.copyItem(at: url, to: backup)

        servers[serverKey] = entry.jsonObject
        root["mcpServers"] = servers
        try write(root, to: url)
        return .updated(url, backup: backup)
    }

    static func backupURL(for url: URL, now: Date) -> URL {
        let stamp = DateFormatter.backupStamp.string(from: now)
        return url.appendingPathExtension("unlirice-backup-\(stamp)")
    }

    private static func write(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object,
            // sortedKeys keeps rewrites diff-stable; withoutEscapingSlashes
            // keeps filesystem paths readable rather than `\/`-escaped, since a
            // human may well need to read this file afterward.
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Paste-it-yourself rendering

    /// The block to show for a format we don't write, or after a refused write.
    public static func snippet(for format: MCPConfigFormat, entry: MCPServerEntry, serverKey: String = MCPServerEntry.serverKey) -> String {
        switch format {
        case .mcpServersJSON: return jsonSnippet(entry: entry, serverKey: serverKey)
        case .codexTOML: return tomlSnippet(entry: entry, serverKey: serverKey)
        }
    }

    static func jsonSnippet(entry: MCPServerEntry, serverKey: String = MCPServerEntry.serverKey) -> String {
        let object: [String: Any] = ["mcpServers": [serverKey: entry.jsonObject]]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Matches the table-and-array layout a real `~/.codex/config.toml` already
    /// uses for its other servers, so a pasted block doesn't look foreign next
    /// to them.
    static func tomlSnippet(entry: MCPServerEntry, serverKey: String = MCPServerEntry.serverKey) -> String {
        var lines = ["[mcp_servers.\(serverKey)]"]
        lines.append("command = \(tomlString(entry.command))")
        lines.append("args = [")
        for arg in entry.args {
            lines.append("    \(tomlString(arg)),")
        }
        lines.append("]")
        if !entry.env.isEmpty {
            lines.append("")
            lines.append("[mcp_servers.\(serverKey).env]")
            for key in entry.env.keys.sorted() {
                lines.append("\(key) = \(tomlString(entry.env[key] ?? ""))")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// TOML basic strings escape backslash and quote. Paths with either are
    /// rare but entirely legal on macOS, and a silently malformed config is
    /// exactly the failure that's hardest to diagnose from the tool's side.
    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

private extension DateFormatter {
    static let backupStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}
