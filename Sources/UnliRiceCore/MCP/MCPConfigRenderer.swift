import Foundation

/// Renders the configuration block a user pastes into an MCP client.
///
/// The App Store build never reads or modifies another app's configuration.
/// Keeping this type render-only makes that boundary explicit in the compiled
/// core instead of merely relying on the UI not to call old write methods.
public enum MCPConfigRenderer {
    public static func snippet(
        for format: MCPConfigFormat,
        entry: MCPServerEntry,
        serverKey: String = MCPServerEntry.serverKey
    ) -> String {
        switch format {
        case .mcpServersJSON:
            return jsonSnippet(entry: entry, serverKey: serverKey)
        case .codexTOML:
            return tomlSnippet(entry: entry, serverKey: serverKey)
        }
    }

    static func jsonSnippet(
        entry: MCPServerEntry,
        serverKey: String = MCPServerEntry.serverKey
    ) -> String {
        let object: [String: Any] = ["mcpServers": [serverKey: entry.jsonObject]]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ), let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    /// Matches the table-and-array layout used by a real Codex config.
    static func tomlSnippet(
        entry: MCPServerEntry,
        serverKey: String = MCPServerEntry.serverKey
    ) -> String {
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

    private static func tomlString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
