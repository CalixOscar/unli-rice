import Foundation

/// Hard ceilings on one run. Defaulted low, on purpose: this is the user's
/// money, and the first thing anyone wants from a feature that spends it is a
/// number they set themselves.
public struct ReasoningCaps: Sendable, Equatable, Codable {
    /// How many notes' titles and bodies may go in one request.
    public var maxNotesPerRun: Int
    /// Estimated input tokens for the whole request. Nothing is truncated to
    /// fit — whole notes are deferred to the next run and counted out loud.
    public var maxInputTokensPerRun: Int
    /// What the provider is told it may spend answering.
    public var maxOutputTokens: Int

    public init(maxNotesPerRun: Int = 25, maxInputTokensPerRun: Int = 12_000, maxOutputTokens: Int = 1_500) {
        self.maxNotesPerRun = maxNotesPerRun
        self.maxInputTokensPerRun = maxInputTokensPerRun
        self.maxOutputTokens = maxOutputTokens
    }

    public static let `default` = ReasoningCaps()
}

/// Which slice of the vault a dispatched prompt is about.
///
/// The clipboard prompts each describe a job over a specific pile; when the same
/// sentence goes down the provider transport instead, that pile has to be
/// gathered here rather than by an agent calling `list_notes` for itself.
public enum ReasoningScope: String, Sendable, Equatable, Codable {
    /// Notes the rule-based janitor put on a shortlist. The default for the
    /// janitor path — rules filter, the model judges (§5).
    case janitorShortlist
    /// Notes written by the `ingest` pipelines.
    case ingested
    /// Notes carrying an unresolved flag.
    case pendingReviews
    case archived
    case all
}

/// What a run would send, computed before anything leaves the machine.
///
/// This is what `previewJanitor()` shows for the provider path: the exact note
/// count, the exact estimate, and — when a cap says no — the reason, in a
/// sentence, with nothing sent.
public struct ReasoningPlan: Sendable {
    /// Why nothing can be sent. Always a stated reason, never a silent no-op.
    public enum Blocked: Sendable, Equatable {
        case noProvider
        case nothingChanged(consideredNotes: Int)
        case nothingInScope
        /// One note is bigger than the whole per-run token cap, so no
        /// combination of whole notes fits. Truncating it would change what the
        /// model sees without saying which half it lost.
        case singleNoteExceedsTokenCap(estimatedTokens: Int, cap: Int)

        public var explanation: String {
            switch self {
            case .noProvider:
                return "No provider is configured, so nothing was sent."
            case .nothingChanged(let considered):
                return "All \(considered) note\(considered == 1 ? "" : "s") in scope are unchanged since the last run. Nothing was sent."
            case .nothingInScope:
                return "Nothing is in scope for this task. Nothing was sent."
            case .singleNoteExceedsTokenCap(let estimated, let cap):
                return "One note alone is about \(estimated) tokens, over the \(cap)-token cap for a run. Nothing was sent — raise the cap rather than have half a note judged."
            }
        }
    }

    public let host: String?
    public let model: String
    public let request: JudgementRequest?
    /// The notes this request carries. Held so the cursor can be advanced
    /// against exactly what was judged, and for nothing else.
    public let notes: [Note]
    /// Unchanged since the last run, so not re-judged and not paid for again.
    public let skippedUnchanged: Int
    /// In scope and changed, but over a cap. Deferred to the next run, not
    /// dropped — the same semantics as `JanitorConfig`'s budgets.
    public let deferredByCaps: Int
    public let blocked: Blocked?

    public var noteCount: Int { notes.count }
    public var estimatedInputTokens: Int { request?.estimatedInputTokens ?? 0 }
    public var canSend: Bool { request != nil && blocked == nil }

    /// The sentence shown before anything is sent. Says the host by name,
    /// because "an endpoint" is not informed consent.
    public var disclosure: String {
        if let blocked { return blocked.explanation }
        guard let host else { return "No provider is configured." }
        return """
        \(noteCount) note\(noteCount == 1 ? "" : "s") — titles and bodies — would be sent to \
        \(host) as \(model). Roughly \(estimatedInputTokens) input tokens (an estimate: \
        characters ÷ 4), plus up to \(request?.maxOutputTokens ?? 0) in reply.
        """
    }
}

/// Builds the request. Pure: it holds no service, opens no file, and sends
/// nothing — the same shape as `Janitor.scan`, and for the same reason.
public enum ReasoningRun {
    /// The contract the model is asked to answer in.
    ///
    /// Worth being explicit about what this is and isn't: it is a *request*, so
    /// the model spends its output on something usable. It is **not** the
    /// capability boundary. Every sentence here is enforced independently by
    /// `ReasoningActionParser` and `RestrictedReasoningDispatcher`, which is
    /// what makes it safe to plug in a model that ignores all of it.
    public static func systemPrompt(task: String) -> String {
        """
        You are judging notes in Unli Rice, a personal append-only memory store, on \
        behalf of its owner.

        \(task)

        You have no tools. Reply with exactly one JSON object and nothing else — no \
        prose before it, no code fence around it:

        {"actions": [ ... ]}

        Every element must be one of these five, and there are no others:

        {"action": "flag_for_review", "note_id": "<uuid>", "reason": "<a sentence or two>"}
        {"action": "tag_note",        "note_id": "<uuid>", "tag": "<tag>"}
        {"action": "untag_note",      "note_id": "<uuid>", "tag": "<tag>"}
        {"action": "create_note",     "title": "<title>", "body": "<body>"}
        {"action": "append_to_note",  "note_id": "<uuid>", "text": "<text>"}

        \(ReasoningAuthority.ladderDescription)

        There is no archive, no delete, no merge, no rename, and no way to resolve a \
        flag. If two notes are the same idea, or contradict each other, or one is \
        stale — that is a flag_for_review and the owner decides. Always. Anything \
        else you ask for will be refused and shown to them as a refusal.

        An empty actions array is a good answer when there is nothing worth doing. \
        Never invent a tag the store doesn't already use.
        """
    }

    /// Assembles a plan, applying the cursor and then the caps.
    ///
    /// Order matters: incremental first (don't pay twice for the same note),
    /// then caps (don't pay too much at once).
    public static func plan(
        task: String,
        host: String?,
        model: String,
        candidates: [Note],
        preferred: [UUID] = [],
        pairs: [(older: Note, newer: Note, similarity: Double)] = [],
        establishedTags: Set<String> = [],
        cursor: ReasoningCursor,
        caps: ReasoningCaps
    ) -> ReasoningPlan {
        guard let host else {
            return ReasoningPlan(
                host: nil, model: model, request: nil, notes: [],
                skippedUnchanged: 0, deferredByCaps: 0, blocked: .noProvider
            )
        }
        guard !candidates.isEmpty else {
            return ReasoningPlan(
                host: host, model: model, request: nil, notes: [],
                skippedUnchanged: 0, deferredByCaps: 0, blocked: .nothingInScope
            )
        }

        let changed = candidates.filter { cursor.needsJudgement($0) }
        let skippedUnchanged = candidates.count - changed.count
        guard !changed.isEmpty else {
            return ReasoningPlan(
                host: host, model: model, request: nil, notes: [],
                skippedUnchanged: skippedUnchanged, deferredByCaps: 0,
                blocked: .nothingChanged(consideredNotes: candidates.count)
            )
        }

        // Notes the rules already have a reason to care about go first, so a
        // tight cap is spent on the shortlist rather than on whatever happened
        // to be edited most recently.
        let rank = Dictionary(preferred.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: min)
        let ordered = changed.sorted { left, right in
            let leftRank = rank[left.id] ?? Int.max
            let rightRank = rank[right.id] ?? Int.max
            if leftRank != rightRank { return leftRank < rightRank }
            return (left.updatedAt, left.id.uuidString) > (right.updatedAt, right.id.uuidString)
        }

        var selected = Array(ordered.prefix(caps.maxNotesPerRun))
        var deferred = ordered.count - selected.count

        // Fit whole notes only. A body cut in half is a different note, and the
        // model would have no way to know it was reading one.
        let system = systemPrompt(task: task)
        let selectedIDs = Set(selected.map(\.id))
        let visiblePairs = pairs.filter { selectedIDs.contains($0.older.id) && selectedIDs.contains($0.newer.id) }
        var overhead = (system.count + preamble(pairs: visiblePairs, establishedTags: establishedTags).count + 3) / 4

        while let last = selected.last {
            let total = overhead + selected.reduce(0) { $0 + tokenEstimate(digest(for: $1)) }
            if total <= caps.maxInputTokensPerRun { break }
            if selected.count == 1 {
                return ReasoningPlan(
                    host: host, model: model, request: nil, notes: [],
                    skippedUnchanged: skippedUnchanged, deferredByCaps: deferred + 1,
                    blocked: .singleNoteExceedsTokenCap(
                        estimatedTokens: overhead + tokenEstimate(digest(for: last)),
                        cap: caps.maxInputTokensPerRun
                    )
                )
            }
            selected.removeLast()
            deferred += 1
            // Dropping a note can orphan a pair; recompute rather than leave a
            // pair pointing at a note the model can no longer see.
            let ids = Set(selected.map(\.id))
            let stillVisible = pairs.filter { ids.contains($0.older.id) && ids.contains($0.newer.id) }
            overhead = (system.count + preamble(pairs: stillVisible, establishedTags: establishedTags).count + 3) / 4
        }

        let finalIDs = Set(selected.map(\.id))
        let finalPairs = pairs.filter { finalIDs.contains($0.older.id) && finalIDs.contains($0.newer.id) }
        let user = preamble(pairs: finalPairs, establishedTags: establishedTags)
            + "\n\n### Notes\n\n"
            + selected.map(digest(for:)).joined(separator: "\n\n")

        return ReasoningPlan(
            host: host,
            model: model,
            request: JudgementRequest(system: system, user: user, maxOutputTokens: caps.maxOutputTokens),
            notes: selected,
            skippedUnchanged: skippedUnchanged,
            deferredByCaps: deferred,
            blocked: nil
        )
    }

    // MARK: - Wire text

    static func tokenEstimate(_ text: String) -> Int { (text.count + 3) / 4 }

    /// Titles and bodies, which is exactly what the disclosure sheet says will
    /// be sent. No flag reasons, no event history, no file paths — a note's own
    /// content and the identifiers needed to act on it.
    static func digest(for note: Note) -> String {
        let tags = note.tags.sorted().joined(separator: ", ")
        return """
        --- \(note.id.uuidString)
        Title: \(note.title)
        Tags: \(tags.isEmpty ? "(none)" : tags)
        Body:
        \(note.body)
        """
    }

    static func preamble(
        pairs: [(older: Note, newer: Note, similarity: Double)],
        establishedTags: Set<String>
    ) -> String {
        var text = ""
        if !pairs.isEmpty {
            text += """
            ### Candidate duplicate pairs

            The local rules matched these on title wording alone, which is a weak \
            signal — deciding whether they are actually the same idea is the job. \
            For each pair that really is a duplicate, raise one flag_for_review on \
            either note saying so. Say nothing about the ones that aren't.


            """
            for pair in pairs {
                let pct = Int((pair.similarity * 100).rounded())
                text += "- \(pair.older.id.uuidString) \"\(pair.older.title)\""
                text += "  ~  \(pair.newer.id.uuidString) \"\(pair.newer.title)\"  (\(pct)% title overlap)\n"
            }
            text += "\n"
        }
        if !establishedTags.isEmpty {
            text += """
            ### Tags this store already uses

            \(establishedTags.sorted().joined(separator: ", "))

            Reuse these. Do not invent synonyms for them, and do not tag a note just \
            because a word appears in its text.

            """
        }
        return text
    }
}
