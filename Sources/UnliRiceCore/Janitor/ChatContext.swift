import Foundation

/// Turns notes and the review queue into bounded prompt text for the chat
/// panel. Pure string formatting — no MLX dependency, no network, testable on
/// its own — because the part worth getting right (what the model is allowed
/// to see, how much, and what it's told about its own authority) has nothing
/// to do with which model reads it.
///
/// The one rule every function here follows: state the boundary before the
/// content. A small local model asked to "help organize notes" with no framing
/// will cheerfully suggest deleting or merging things; asked with `preamble`
/// prepended, the worst case is a bad *suggestion*, never an action, because
/// nothing downstream of the model's text output can write to the event log —
/// see `UnliRiceMLX/JanitorChat.swift`.
public enum ChatContext {
    /// Prepended to every prompt sent to the model. Restates the app's actual
    /// permission boundary (decisions #2 and #3, PROJECT_NOTES.md) in plain
    /// language, because a 1–3B instruct model has no other way to know it.
    public static let preamble = """
    You are a notes assistant inside Unli Rice, a local note-taking app. You \
    can only describe, explain, and suggest — you have no ability to edit, \
    merge, tag, delete, or archive anything, and nothing you say is applied \
    automatically. The person you're talking to reviews every suggestion \
    themselves before anything changes. Be concise. If you're not confident, \
    say so instead of guessing.
    """

    /// A bounded snapshot of the corpus for free-form questions — not the whole
    /// corpus, so a large note collection doesn't blow the context window of a
    /// small local model or make every answer slow.
    public static func corpusBrief(
        notes: [Note],
        pendingClusters: [ReviewCluster],
        maxNotes: Int = 20,
        maxBodyChars: Int = 220
    ) -> String {
        let recent = notes
            .filter { !$0.archived }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxNotes)

        var lines = ["Recent notes (\(recent.count) of \(notes.count) total):"]
        for note in recent {
            let tags = note.tags.isEmpty ? "" : " [\(note.tags.sorted().joined(separator: ", "))]"
            lines.append("- \"\(note.title)\"\(tags): \(truncate(note.body, to: maxBodyChars))")
        }

        if !pendingClusters.isEmpty {
            lines.append("")
            lines.append("Pending in the review queue (\(pendingClusters.count) item(s)):")
            for cluster in pendingClusters {
                let titles = cluster.notes.map(\.title).joined(separator: "\", \"")
                lines.append("- [\"\(titles)\"]: \(cluster.summary)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Full-ish context for one duplicate cluster — the "which of these is the
    /// keeper?" question, where the model actually needs the bodies, not just
    /// titles. Still bounded per note: a handful of session logs is fine, a
    /// handful of 10,000-word notes is not.
    public static func clusterBrief(_ cluster: ReviewCluster, maxBodyChars: Int = 800) -> String {
        var lines = ["\(cluster.notes.count) notes flagged as possible duplicates:"]
        for (index, note) in cluster.notes.enumerated() {
            lines.append("")
            lines.append("Note \(index + 1): \"\(note.title)\" (created \(note.createdAt.formatted()))")
            lines.append(truncate(note.body, to: maxBodyChars))
        }
        return lines.joined(separator: "\n")
    }

    /// The question asked for a duplicate cluster's recommendation. Separate
    /// from free-form chat so the phrasing can ask for exactly one thing: which
    /// note (if any) looks like the keeper, and why.
    public static func clusterRecommendationPrompt(_ cluster: ReviewCluster) -> String {
        """
        \(preamble)

        \(clusterBrief(cluster))

        These were flagged because their titles are nearly identical. Based on \
        the content above: do these look like true duplicates of the same \
        thing? If so, which one note looks like the best one to keep (most \
        complete, most recent, or otherwise clearly the "real" one), and what \
        should happen to the others — merged into it, or are they actually \
        different enough to both stay? Answer in 3-4 sentences. Remember: this \
        is a suggestion for a human to accept or reject, not something you can \
        do yourself.
        """
    }

    /// A free-form question, with corpus context prepended. Chat history isn't
    /// kept by the model between calls (see `JanitorChat` for why), so the
    /// caller folds any prior turns worth keeping into `priorTurns` itself.
    public static func questionPrompt(
        _ question: String,
        notes: [Note],
        pendingClusters: [ReviewCluster],
        priorTurns: [(question: String, answer: String)] = []
    ) -> String {
        var sections = [preamble, corpusBrief(notes: notes, pendingClusters: pendingClusters)]
        if !priorTurns.isEmpty {
            let history = priorTurns.suffix(4).map { "Q: \($0.question)\nA: \($0.answer)" }
            sections.append("Earlier in this conversation:\n" + history.joined(separator: "\n\n"))
        }
        sections.append("Question: \(question)")
        return sections.joined(separator: "\n\n")
    }

    /// Removes a leading `<think>...</think>` block from a model's raw output.
    ///
    /// Qwen3's chat template defaults to emitting an internal-reasoning block
    /// before the real answer. `JanitorChat.ask` already primes the prompt with
    /// `enable_thinking: false`, which should stop the model from generating
    /// one at all — this is the second, independent layer for when that
    /// doesn't hold (a template change, a different model swapped in later).
    /// Without it, the panel shows the model arguing with itself instead of a
    /// 3-4 sentence answer — this was caught by actually running the app, not
    /// anticipated up front.
    ///
    /// Only strips a block at the very start of the response. A `<think>` tag
    /// appearing mid-answer is a stranger failure this isn't trying to cover.
    public static func stripThinkingBlock(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("<think>"),
              let close = trimmed.range(of: "</think>")
        else { return trimmed }
        return String(trimmed[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func truncate(_ text: String, to limit: Int) -> String {
        let collapsed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard collapsed.count > limit else { return collapsed.isEmpty ? "(empty)" : collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
