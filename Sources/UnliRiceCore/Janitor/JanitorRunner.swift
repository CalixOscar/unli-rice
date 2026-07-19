import Foundation

public enum JanitorOutcome: Sendable, Equatable {
    /// A cosmetic proposal the janitor applied itself.
    case applied
    /// A structural proposal handed to the human via the review queue.
    case queued
    /// Deliberately not acted on. `reason` says why, for the run report.
    case skipped(reason: String)
}

public struct JanitorRunReport: Sendable {
    public let results: [(proposal: JanitorProposal, outcome: JanitorOutcome)]

    public var applied: [JanitorProposal] { results.filter { $0.outcome == .applied }.map(\.proposal) }
    public var queued: [JanitorProposal] { results.filter { $0.outcome == .queued }.map(\.proposal) }
    public var skipped: [(proposal: JanitorProposal, reason: String)] {
        results.compactMap { result in
            if case .skipped(let reason) = result.outcome { return (result.proposal, reason) }
            return nil
        }
    }

    public var summary: String {
        "janitor: \(applied.count) applied, \(queued.count) queued for review, \(skipped.count) skipped"
    }
}

/// The janitor's hands, and the entire reason the janitor is safe to run
/// unattended.
///
/// It calls exactly three `NoteService` methods — `tagNote`, `flagForReview`,
/// and nothing else that writes. It never archives, never untags, never
/// resolves a flag, never appends to a body it didn't author, and (as with the
/// rest of this codebase) has no delete available to it at all. If you are
/// adding a rule and find yourself wanting a fourth write method here, that
/// rule is a `flagForReview` instead — see decisions #2 and #3 in
/// PROJECT_NOTES.md.
public final class JanitorRunner {
    /// Every write the janitor makes is attributed to this, distinct from
    /// `"human"` and from any agent's name, so the transaction log can always
    /// answer "did I do that, or did the janitor?".
    public static let sourceIdentity = "janitor"

    private let service: NoteService
    private let similarity: SimilarityProvider

    public init(service: NoteService, similarity: SimilarityProvider = TokenOverlapSimilarity()) {
        self.service = service
        self.similarity = similarity
    }

    /// Scans and acts. Safe to call repeatedly: a conclusion already raised
    /// once — or already overruled by a human — is skipped rather than
    /// re-raised.
    @discardableResult
    public func run(config: JanitorConfig) throws -> JanitorRunReport {
        let notes = try service.listNotes(includeArchived: false)
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        // Best-first, so a tight budget is spent on the most confident
        // conclusions instead of whichever rule happened to run first.
        let proposals = Janitor.scan(notes: notes, config: config, similarity: similarity)
            .sorted { ($0.confidence, $0.fingerprint) > ($1.confidence, $1.fingerprint) }
        let overruledTags = try humanRemovedTags()

        var results: [(JanitorProposal, JanitorOutcome)] = []
        var raisedThisRun: Set<String> = []
        var cosmeticSpent = 0
        var structuralSpent = 0

        for proposal in proposals {
            guard let note = notesByID[proposal.noteID] else { continue }

            // The same duplicate pair can surface from either side; only act once.
            guard raisedThisRun.insert(proposal.fingerprint).inserted else {
                results.append((proposal, .skipped(reason: "already handled in this run")))
                continue
            }

            // Includes resolved flags on purpose. A human who looked at this and
            // said no should not be asked again next scan.
            if note.flags.contains(where: { JanitorMarker.isStamped($0.reason, with: proposal.fingerprint) }) {
                results.append((proposal, .skipped(reason: "already raised in a previous scan")))
                continue
            }

            switch proposal.kind {
            case .addTag(let tag):
                if note.tags.contains(tag) {
                    results.append((proposal, .skipped(reason: "note already has this tag")))
                } else if overruledTags.contains(TagKey(noteID: note.id, tag: tag)) {
                    // Someone took this tag off this note. Putting it back would
                    // be the janitor arguing with its user.
                    results.append((proposal, .skipped(reason: "tag was previously removed by hand")))
                } else if cosmeticSpent >= config.cosmeticBudget {
                    // Not dropped, just deferred — the next run picks it up.
                    results.append((proposal, .skipped(reason: "cosmetic budget for this run is spent")))
                } else {
                    try service.tagNote(id: note.id, tag: tag, source: Self.sourceIdentity)
                    cosmeticSpent += 1
                    results.append((proposal, .applied))
                }

            case .possibleDuplicate, .likelyMistypedLink, .orphaned:
                // Structural: propose, never apply. There is no branch here that
                // writes anything but a flag, and there must never be one.
                guard structuralSpent < config.structuralBudget else {
                    results.append((proposal, .skipped(reason: "review-queue budget for this run is spent")))
                    continue
                }
                try service.flagForReview(
                    id: note.id,
                    reason: "\(proposal.rationale) \(JanitorMarker.stamp(proposal.fingerprint))",
                    source: Self.sourceIdentity
                )
                structuralSpent += 1
                results.append((proposal, .queued))
            }
        }

        return JanitorRunReport(results: results.map { (proposal: $0.0, outcome: $0.1) })
    }

    /// Preview a scan without touching anything — what the janitor *would* do at
    /// this autonomy level. Useful for the GUI and for anyone who wants to see
    /// the rules' output before letting them run.
    public func preview(config: JanitorConfig) throws -> [JanitorProposal] {
        Janitor.scan(
            notes: try service.listNotes(includeArchived: false),
            config: config,
            similarity: similarity
        )
    }

    // MARK: - Private

    private struct TagKey: Hashable {
        let noteID: UUID
        let tag: String
    }

    /// Every (note, tag) pair anyone has ever untagged. Read from the raw event
    /// log because the projection only knows the *current* tag set — the fact
    /// that a tag was once removed survives nowhere else, and it's exactly the
    /// signal needed to stop the janitor re-adding it forever.
    private func humanRemovedTags() throws -> Set<TagKey> {
        var removed: Set<TagKey> = []
        for event in try service.transactionLog(limit: Int.max) where event.kind == .untagged {
            guard event.source != Self.sourceIdentity, let tag = event.tag else { continue }
            removed.insert(TagKey(noteID: event.noteId, tag: tag))
        }
        return removed
    }
}
