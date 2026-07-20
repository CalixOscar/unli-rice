import Foundation

/// Pulls local Claude Code session history into the data lake.
///
/// This is the highest-signal pipeline and the reason it's the one built first:
/// the transcripts are already on disk, already structured, and are a record of
/// decisions the user actually made rather than content they merely saved.
///
/// **The format here was read off real files on this machine, not recalled.**
/// A `~/.claude/projects/<slugified-cwd>/<session-uuid>.jsonl` holds one JSON
/// object per line, of mixed `type`. What matters:
///
/// | `type` | carries |
/// | --- | --- |
/// | `custom-title` | `customTitle` — a title the user typed. Wins. |
/// | `ai-title` | `aiTitle` — a generated title. Appears repeatedly; last wins. |
/// | `last-prompt` | `lastPrompt` — truncated, used only as a fallback |
/// | `user` / `assistant` | `message.content`, a String *or* an array of blocks |
///
/// 186 of 191 session files carried one of the two title records, which is why
/// the title is taken from the file rather than generated: a title someone wrote
/// or approved beats anything this importer could compose, and titles here are
/// permanent.
public struct ClaudeSessionImporter: ResourceImporter {
    public let identifier = "claude-session"
    public let displayName = "Claude Code sessions"

    private let projectsDirectory: URL
    private let fileManager: FileManager
    /// Sessions shorter than this are skipped. A two-message session is almost
    /// always an abandoned start, and a data lake full of those is noise that
    /// makes the useful entries harder to find.
    private let minimumMessages: Int

    public init(
        projectsDirectory: URL = ClaudeSessionImporter.defaultProjectsDirectory(),
        minimumMessages: Int = 4,
        fileManager: FileManager = .default
    ) {
        self.projectsDirectory = projectsDirectory
        self.minimumMessages = minimumMessages
        self.fileManager = fileManager
    }

    public static func defaultProjectsDirectory() -> URL {
        fileURLHome().appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private static func fileURLHome() -> URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public func discover() throws -> [DiscoveredResource] {
        guard let walker = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        // Keyed by session id, because the same session genuinely appears more
        // than once: a git worktree gets its own `~/.claude/projects` directory
        // but shares the parent's session ids, so two diverged copies of one
        // conversation are on disk. They are one session and must become one
        // note — keep whichever copy saw more of it.
        var richest: [String: (session: ParsedSession, url: URL)] = [:]
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            // One unreadable or half-written session must not abort a bulk run
            // over three hundred of them.
            guard let session = try? parse(url), session.messageCount >= minimumMessages else { continue }
            if let existing = richest[session.sessionID], existing.session.messageCount >= session.messageCount {
                continue
            }
            richest[session.sessionID] = (session, url)
        }

        return richest.values
            .map { $0.session.asResource(sourceURL: $0.url) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    // MARK: - Parsing

    struct ParsedSession {
        var sessionID: String
        var customTitle: String?
        var aiTitle: String?
        var lastPrompt: String?
        var firstUserMessage: String?
        var workingDirectory: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?
        var userMessages = 0
        var assistantMessages = 0

        var messageCount: Int { userMessages + assistantMessages }

        /// Permanent, and also the key `IngestRunner` matches on to recognise
        /// this session on a later run — so it must be derived only from things
        /// that don't change. The session UUID prefix is what guarantees
        /// uniqueness: two sessions can genuinely share a generated title, and
        /// a collision would mean `[[…]]` linking to whichever one won.
        var noteTitle: String {
            let stem = customTitle ?? aiTitle ?? lastPrompt ?? firstUserMessage
            let base = stem.map { ImporterText.condense(ImporterText.sanitizeTitle($0), limit: 90) } ?? ""
            let shortID = String(sessionID.prefix(8))
            guard !base.isEmpty else { return "Session \(shortID)" }
            return "Session: \(base) (\(shortID))"
        }

        func asResource(sourceURL: URL) -> DiscoveredResource {
            var lines: [String] = []
            if let cwd = workingDirectory {
                lines.append("**Project:** `\(cwd)`")
            }
            if let first = firstTimestamp {
                let day = ImporterText.dayFormatter.string(from: first)
                let span = lastTimestamp.map { last -> String in
                    let minutes = Int(last.timeIntervalSince(first) / 60)
                    return minutes >= 1 ? ", \(minutes) min" : ""
                } ?? ""
                lines.append("**When:** \(day)\(span)")
            }
            lines.append("**Size:** \(userMessages) user / \(assistantMessages) assistant messages")
            lines.append("**Session:** `\(sessionID)`")

            if let opening = firstUserMessage, !opening.isEmpty {
                lines.append("")
                lines.append("**Opened with:**")
                lines.append("> " + ImporterText.condense(opening, limit: 500))
            }

            return DiscoveredResource(
                sourceURL: sourceURL,
                // The session id, not the title. `ai-title` is regenerated as a
                // session grows, so a title-keyed match would mint a brand-new
                // permanent note every time a conversation continued.
                key: sessionID,
                title: noteTitle,
                summary: lines.joined(separator: "\n"),
                tags: ["claude-session", "ingested"],
                occurredAt: lastTimestamp ?? firstTimestamp ?? Date()
            )
        }
    }

    func parse(_ url: URL) throws -> ParsedSession {
        var session = ParsedSession(sessionID: url.deletingPathExtension().lastPathComponent)
        let contents = try String(contentsOf: url, encoding: .utf8)

        for line in contents.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            if let sessionID = object["sessionId"] as? String, !sessionID.isEmpty {
                session.sessionID = sessionID
            }

            switch object["type"] as? String {
            case "custom-title":
                session.customTitle = object["customTitle"] as? String
            case "ai-title":
                // Regenerated as a session grows; the last one saw the most.
                session.aiTitle = object["aiTitle"] as? String
            case "last-prompt":
                session.lastPrompt = object["lastPrompt"] as? String
            case "user":
                session.userMessages += 1
                if session.firstUserMessage == nil {
                    session.firstUserMessage = Self.text(fromMessageIn: object)
                }
                if session.workingDirectory == nil {
                    session.workingDirectory = object["cwd"] as? String
                }
            case "assistant":
                session.assistantMessages += 1
            default:
                break
            }

            if let stamp = object["timestamp"] as? String, let date = Self.date(from: stamp) {
                if session.firstTimestamp == nil { session.firstTimestamp = date }
                session.lastTimestamp = date
            }
        }
        return session
    }

    /// `message.content` is a plain String on some user records and an array of
    /// typed blocks on others — both shapes appear in the same file, so handling
    /// only one silently loses the opening prompt of most sessions.
    static func text(fromMessageIn object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any] else { return nil }
        if let text = message["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let blocks = message["content"] as? [[String: Any]] else { return nil }
        let text = blocks
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    static func date(from string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFraction.date(from: string)
    }
}
