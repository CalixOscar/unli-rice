import Foundation

public enum TodoWording {
    /// "claude" → "Claude", "chatgpt" → "ChatGPT", "gemini" → "Gemini", "kimi" → "Kimi",
    /// "codex" → "Codex", "antigravity" → "Antigravity", "human" → "you".
    /// Anything else: as written, first letter capitalised.
    public static func assistantName(forSource source: String) -> String {
        switch source.lowercased() {
        case "claude": return "Claude"
        case "chatgpt": return "ChatGPT"
        case "gemini": return "Gemini"
        case "kimi": return "Kimi"
        case "codex": return "Codex"
        case "antigravity": return "Antigravity"
        case "human": return "you"
        default:
            guard let first = source.first else { return "" }
            return first.uppercased() + source.dropFirst()
        }
    }

    /// "Suggested by Claude · 2 days ago · CalmdownOscar"
    public static func subtitle(
        creator: String,
        createdAt: Date,
        projects: [String],
        now: Date = Date()
    ) -> String {
        let assistant = assistantName(forSource: creator)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        let relativeTime = formatter.localizedString(for: createdAt, relativeTo: now)
        let projectText = projects.isEmpty ? "no project" : projects.joined(separator: ", ")
        return "Suggested by \(assistant) · \(relativeTime) · \(projectText)"
    }
}
