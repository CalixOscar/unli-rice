import Foundation

public enum UnwrittenClients {

    /// Source attribution is self-reported. This maps the identifiers this studio's own tools
    /// actually use; it does not authenticate that a client is who it says it is, and nothing
    /// here should be read as proof of identity.
    public static func canonicalKey(for name: String) -> String {
        let lower = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let stripped = lower.replacingOccurrences(of: "-", with: "")
                            .replacingOccurrences(of: "_", with: "")
                            .replacingOccurrences(of: " ", with: "")
        if stripped == "claudecode" || stripped == "claude" {
            return "claude"
        }
        return stripped
    }

    public static func matches(clientName: String, writerSource: String) -> Bool {
        canonicalKey(for: clientName) == canonicalKey(for: writerSource)
    }

    /// Clients that connected and have no evidence of a write.
    ///
    /// Two things count as evidence, and a plain tool call is neither: an Event
    /// in the log whose source matches this client, or an observed write-tool
    /// call. A search is not a write — suppressing the warning on one is what
    /// let unli-009 (an agent that read the vault and never wrote back) pass.
    ///
    /// Takes ALL records for a client, not the newest. See below.
    public static func firstUnwritten(
        among activities: [MCPConnectionActivity],
        knownWriterSources: Set<String>
    ) -> MCPConnectionActivity? {
        var groups: [String: [MCPConnectionActivity]] = [:]
        for act in activities {
            let key = canonicalKey(for: act.clientName)
            groups[key, default: []].append(act)
        }

        let sortedGroups = groups.values.sorted { g1, g2 in
            let max1 = g1.map(\.lastSeenAt).max() ?? Date.distantPast
            let max2 = g2.map(\.lastSeenAt).max() ?? Date.distantPast
            return max1 > max2
        }

        for group in sortedGroups {
            guard let representative = group.sorted(by: { $0.lastSeenAt > $1.lastSeenAt }).first else {
                continue
            }

            let hasObservedWrite = group.contains { $0.lastWriteAt != nil }
            let hasEventSource = knownWriterSources.contains { source in
                matches(clientName: representative.clientName, writerSource: source)
            }

            if !hasObservedWrite && !hasEventSource {
                return representative
            }
        }

        return nil
    }
}
