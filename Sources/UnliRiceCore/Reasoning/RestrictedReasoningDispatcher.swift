import Foundation

public enum ReasoningOutcome: Sendable, Equatable {
    case applied
    /// Refused by this app, with the reason. The model asked; the answer is no.
    case refused(RefusedAction.Reason)
    /// Understood and permitted, but deliberately not done — already raised,
    /// already true, or previously overruled by hand.
    case skipped(reason: String)
}

public struct ReasoningDispatchReport: Sendable {
    public let results: [(action: ReasoningAction, outcome: ReasoningOutcome)]
    /// Requests that never became actions at all — the ladder refusing to
    /// express them. Reported, never silently dropped.
    public let refusals: [RefusedAction]
    /// Set when the reply could not be read; nothing was applied.
    public let unreadable: String?

    public var applied: [ReasoningAction] { results.filter { $0.outcome == .applied }.map(\.action) }
    public var skipped: [(action: ReasoningAction, reason: String)] {
        results.compactMap { result in
            if case .skipped(let reason) = result.outcome { return (result.action, reason) }
            return nil
        }
    }

    /// Every refusal, however it arose — parse-time or dispatch-time.
    public var allRefusals: [RefusedAction] {
        refusals + results.compactMap { result in
            if case .refused(let reason) = result.outcome {
                return RefusedAction(requested: result.action.name, reason: reason)
            }
            return nil
        }
    }

    public var summary: String {
        let parts = [
            "\(applied.count) applied",
            "\(allRefusals.count) refused",
            "\(skipped.count) skipped"
        ]
        return "model: " + parts.joined(separator: ", ")
    }
}

/// The reasoning provider's hands, and the entire reason plugging one in is safe.
///
/// It calls exactly five `NoteService` methods — `flagForReview`, `createNote`,
/// `appendToNote`, `tagNote`, `untagNote` — and nothing else that writes. It
/// never archives, never unarchives, never resolves a flag, never consolidates,
/// and (as with the rest of this codebase) has no delete available to it at all.
/// That is the same contract `JanitorRunner` holds, widened by exactly the two
/// things the founder decided on 2026-08-09: derived notes the model owns, and
/// tagging.
///
/// The boundary is here, in a type, rather than in the prompt. A prompt is a
/// request; this is a wall. Every structural judgement the model reaches for —
/// merge, dedupe, "these contradict" — can only come out as a `flag_for_review`
/// that waits for a human, because `ReasoningAction` has no other case for it
/// (locked-in decision #3). If you are extending this and find yourself wanting
/// a sixth write method, what you actually want is a flag.
public final class RestrictedReasoningDispatcher {
    /// Attribution is mandatory — locked-in decision #4, and §4 of
    /// docs/BYO_LLM.md. Every write records *which model* made it, so a user
    /// looking at a tag six months later can see a model added it and which
    /// one, and so a bad model's output is revocable in bulk.
    ///
    /// Distinct from bare `"janitor"`, which AGENTS.md reserves for the local
    /// rule-based janitor. `janitor:gpt-5` is not `janitor`.
    public static func sourceIdentity(model: String) -> String {
        let cleaned = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "janitor:unknown-model" : "janitor:\(cleaned)"
    }

    private let service: NoteService
    private let source: String

    public init(service: NoteService, model: String) {
        self.service = service
        self.source = Self.sourceIdentity(model: model)
    }

    /// The source string every write from this dispatcher carries.
    public var sourceIdentity: String { source }

    @discardableResult
    public func apply(_ parsed: ParsedActions) throws -> ReasoningDispatchReport {
        guard parsed.unreadable == nil else {
            return ReasoningDispatchReport(results: [], refusals: parsed.refused, unreadable: parsed.unreadable)
        }

        let notes = try service.listNotes(includeArchived: true)
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let overruledTags = try handRemovedTags()

        var results: [(ReasoningAction, ReasoningOutcome)] = []
        var raisedThisRun: Set<String> = []

        for action in parsed.allowed {
            if let fingerprint = action.fingerprint,
               !raisedThisRun.insert(fingerprint).inserted {
                results.append((action, .skipped(reason: "already handled in this run")))
                continue
            }

            switch action {
            case .flagForReview(let noteID, let reason):
                guard let note = notesByID[noteID] else {
                    results.append((action, .refused(.unknownNote)))
                    continue
                }
                let fingerprint = action.fingerprint ?? ""
                // Includes resolved flags on purpose, the same as
                // `JanitorRunner`: a human who looked at this and said no should
                // not be asked again on the next run.
                if note.flags.contains(where: { JanitorMarker.isStamped($0.reason, with: fingerprint) }) {
                    results.append((action, .skipped(reason: "already raised in a previous run")))
                    continue
                }
                try service.flagForReview(
                    id: noteID,
                    reason: "\(reason) \(JanitorMarker.stamp(fingerprint))",
                    source: source
                )
                results.append((action, .applied))

            case .createOwnedNote(let title, let body):
                // Belt and braces with the parser. The wall must hold whichever
                // door a future caller comes through.
                guard ReasoningAuthority.owns(title: title) else {
                    results.append((action, .refused(.notOwned)))
                    continue
                }
                try service.createNote(title: title, body: body, source: source)
                results.append((action, .applied))

            case .appendToOwnedNote(let noteID, let text):
                guard let note = notesByID[noteID] else {
                    results.append((action, .refused(.unknownNote)))
                    continue
                }
                guard ReasoningAuthority.owns(title: note.title) else {
                    results.append((action, .refused(.notOwned)))
                    continue
                }
                try service.appendToNote(id: noteID, text: text, source: source)
                results.append((action, .applied))

            case .tagNote(let noteID, let tag):
                guard let note = notesByID[noteID] else {
                    results.append((action, .refused(.unknownNote)))
                    continue
                }
                if note.tags.contains(tag) {
                    results.append((action, .skipped(reason: "note already has this tag")))
                } else if overruledTags.contains(TagKey(noteID: noteID, tag: tag)) {
                    // Someone took this tag off by hand. Putting it back would
                    // be a model arguing with its user — the same rule the local
                    // janitor holds, and for the same reason.
                    results.append((action, .skipped(reason: "tag was previously removed by hand")))
                } else {
                    try service.tagNote(id: noteID, tag: tag, source: source)
                    results.append((action, .applied))
                }

            case .untagNote(let noteID, let tag):
                guard let note = notesByID[noteID] else {
                    results.append((action, .refused(.unknownNote)))
                    continue
                }
                guard note.tags.contains(tag) else {
                    results.append((action, .skipped(reason: "note does not have this tag")))
                    continue
                }
                try service.untagNote(id: noteID, tag: tag, source: source)
                results.append((action, .applied))
            }
        }

        return ReasoningDispatchReport(
            results: results.map { (action: $0.0, outcome: $0.1) },
            refusals: parsed.refused,
            unreadable: nil
        )
    }

    // MARK: - Private

    private struct TagKey: Hashable {
        let noteID: UUID
        let tag: String
    }

    /// Every (note, tag) pair a human or another agent has untagged. Read from
    /// the raw event log because the projection only knows the *current* tag
    /// set — the fact that a tag was once removed survives nowhere else.
    /// Machine sources are excluded so two automated passes can't ratchet
    /// against each other.
    private func handRemovedTags() throws -> Set<TagKey> {
        var removed: Set<TagKey> = []
        for event in try service.transactionLog(limit: Int.max) where event.kind == .untagged {
            guard let tag = event.tag else { continue }
            guard event.source != JanitorRunner.sourceIdentity,
                  !event.source.hasPrefix("janitor:")
            else { continue }
            removed.insert(TagKey(noteID: event.noteId, tag: tag))
        }
        return removed
    }
}
