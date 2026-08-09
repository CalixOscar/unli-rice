import Foundation

public struct ReasoningRunReport: Sendable {
    public let plan: ReasoningPlan
    /// Nil when nothing was sent.
    public let dispatch: ReasoningDispatchReport?
    public let call: OutboundCall
    /// Set when the provider itself failed. The cursor is not advanced in that
    /// case — a network blip must not mean those notes are never looked at.
    public let failure: String?

    public var summary: String {
        if let failure { return "Nothing was applied: \(failure)" }
        guard let dispatch else { return plan.blocked?.explanation ?? "Nothing was sent." }
        if let unreadable = dispatch.unreadable {
            return "The model's reply couldn't be read (\(unreadable)), so nothing was applied."
        }
        var text = dispatch.summary
        if plan.skippedUnchanged > 0 { text += " · \(plan.skippedUnchanged) unchanged, not re-sent" }
        if plan.deferredByCaps > 0 { text += " · \(plan.deferredByCaps) held back by the caps for the next run" }
        return text
    }
}

/// The on-demand path: rules filter, the model judges, the dispatcher decides
/// what may happen, and every call leaves a metadata-only receipt.
///
/// Phase 1 only. Nothing here is reachable from `RoutineDriver`, the routine
/// tick, or `unlirice-agent` — running unattended is a different promise from
/// running while the user watches, and it needs a keychain-access-groups
/// decision that touches App Store review (§8 of docs/BYO_LLM.md).
public final class ReasoningRunner {
    private let service: NoteService
    private let provider: ReasoningProvider
    private let log: OutboundCallLog?
    private let cursorURL: URL?

    public init(
        service: NoteService,
        provider: ReasoningProvider,
        log: OutboundCallLog? = nil,
        cursorURL: URL? = nil
    ) {
        self.service = service
        self.provider = provider
        self.log = log
        self.cursorURL = cursorURL
    }

    public var isConfigured: Bool { provider.isConfigured }

    /// What a run would send. Writes nothing, sends nothing, and is what the
    /// "Preview" button shows — the janitor's contract has always been that you
    /// can see what it would do first, and that matters more, not less, once
    /// seeing it costs money.
    public func plan(
        scope: ReasoningScope,
        task: String,
        config: JanitorConfig = JanitorConfig(autonomy: .balanced),
        caps: ReasoningCaps = .default,
        similarity: SimilarityProvider = TokenOverlapSimilarity()
    ) throws -> ReasoningPlan {
        let all = try service.listNotes(includeArchived: true)
        let live = all.filter { !$0.archived }
        let cursor = cursorURL.map { ReasoningCursor.load(from: $0) } ?? ReasoningCursor()
        let established = Janitor.establishedTags(live, config: config)

        switch scope {
        case .janitorShortlist:
            // §5, the single most important decision here: never send the
            // corpus. `Janitor.scan` already produces candidates cheaply and
            // locally; the model adjudicates that shortlist and nothing else.
            let proposals = Janitor.scan(notes: live, config: config, similarity: similarity)
                .sorted { ($0.confidence, $0.fingerprint) > ($1.confidence, $1.fingerprint) }
            let byID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })

            var preferred: [UUID] = []
            var pairs: [(older: Note, newer: Note, similarity: Double)] = []
            for proposal in proposals {
                preferred.append(proposal.noteID)
                guard case .possibleDuplicate(let otherID, _, let score) = proposal.kind,
                      let newer = byID[proposal.noteID], let older = byID[otherID]
                else { continue }
                preferred.append(otherID)
                pairs.append((older: older, newer: newer, similarity: score))
            }
            var seen: Set<UUID> = []
            let shortlist = preferred.filter { seen.insert($0).inserted }.compactMap { byID[$0] }

            return ReasoningRun.plan(
                task: task, host: provider.host, model: provider.modelName,
                candidates: shortlist, preferred: preferred, pairs: pairs,
                establishedTags: established, cursor: cursor, caps: caps
            )

        case .ingested, .pendingReviews, .archived, .all:
            let candidates = notes(all, in: scope)
            return ReasoningRun.plan(
                task: task, host: provider.host, model: provider.modelName,
                candidates: candidates, establishedTags: established,
                cursor: cursor, caps: caps
            )
        }
    }

    /// Sends the plan, dispatches the answer through the restricted dispatcher,
    /// and records the call either way.
    ///
    /// A plan that can't be sent still produces a receipt: "we chose not to
    /// call" is evidence too, and a Trust Center that only lists successes is
    /// answering an easier question than the one it was built for.
    @discardableResult
    public func execute(_ plan: ReasoningPlan) async throws -> ReasoningRunReport {
        guard let request = plan.request, plan.canSend, let host = plan.host else {
            let call = OutboundCall(
                host: plan.host ?? "—", model: plan.model,
                noteCount: 0, estimatedTokens: 0,
                outcome: .notSent, detail: blockedDetail(plan.blocked)
            )
            try? log?.record(call)
            return ReasoningRunReport(plan: plan, dispatch: nil, call: call, failure: nil)
        }

        let response: JudgementResponse
        do {
            response = try await provider.judge(request)
        } catch {
            let call = OutboundCall(
                host: host, model: plan.model,
                noteCount: plan.noteCount, estimatedTokens: plan.estimatedInputTokens,
                outcome: .failed, detail: "\(error)"
            )
            try? log?.record(call)
            return ReasoningRunReport(plan: plan, dispatch: nil, call: call, failure: "\(error)")
        }

        // Attribution follows the model that actually answered, not the one that
        // was asked for — locked-in decision #4 is only useful if the name in
        // the log is the name of the thing that made the judgement.
        let dispatcher = RestrictedReasoningDispatcher(service: service, model: response.model)
        let report = try dispatcher.apply(ReasoningActionParser.parse(response.text))

        let reported = (response.promptTokens ?? 0) + (response.completionTokens ?? 0)
        let call = OutboundCall(
            host: host, model: response.model.isEmpty ? plan.model : response.model,
            noteCount: plan.noteCount,
            estimatedTokens: plan.estimatedInputTokens,
            reportedTokens: reported > 0 ? reported : nil,
            outcome: .succeeded,
            // Counts and fixed phrases only. Never a title, body, tag, or reason.
            detail: report.unreadable.map { "unreadable reply: \($0)" }
                ?? "\(report.applied.count) applied, \(report.allRefusals.count) refused"
        )
        try? log?.record(call)

        // Only advance the cursor for notes a model genuinely looked at.
        if report.unreadable == nil, let cursorURL {
            var cursor = ReasoningCursor.load(from: cursorURL)
            cursor.record(plan.notes)
            try? cursor.save(to: cursorURL)
        }

        return ReasoningRunReport(plan: plan, dispatch: report, call: call, failure: nil)
    }

    /// Records what a dry run would have cost, without sending it. Keeps the
    /// preview honest in the one place a user goes to check what left.
    @discardableResult
    public func recordDryRun(_ plan: ReasoningPlan) -> OutboundCall {
        let call = OutboundCall(
            host: plan.host ?? "—", model: plan.model,
            noteCount: plan.noteCount, estimatedTokens: plan.estimatedInputTokens,
            outcome: .dryRun, detail: plan.blocked.map { blockedDetail($0) } ?? "preview only, nothing sent"
        )
        try? log?.record(call)
        return call
    }

    // MARK: - Private

    private func notes(_ all: [Note], in scope: ReasoningScope) -> [Note] {
        switch scope {
        case .ingested:
            return all.filter { !$0.archived && $0.creator == "ingest" }
        case .pendingReviews:
            return all.filter { $0.flags.contains { !$0.resolved } }
        case .archived:
            return all.filter(\.archived)
        case .all, .janitorShortlist:
            return all.filter { !$0.archived }
        }
    }

    private func blockedDetail(_ blocked: ReasoningPlan.Blocked?) -> String {
        switch blocked {
        case .none: return "nothing to send"
        case .noProvider: return "no provider configured"
        case .nothingChanged: return "no notes changed since the last run"
        case .nothingInScope: return "nothing in scope"
        case .singleNoteExceedsTokenCap: return "a single note exceeds the token cap"
        }
    }
}
