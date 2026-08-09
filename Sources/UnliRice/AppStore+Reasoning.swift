import AppKit
import Foundation
import UnliRiceCore

/// Bring-your-own LLM, on demand. See docs/BYO_LLM.md.
///
/// Three things hold this together, and all three are load-bearing:
///
/// 1. **Default off.** With no key configured, `reasoningProvider()` returns
///    `NullReasoningProvider` and this app's network behaviour is exactly what
///    it was before the feature existed.
/// 2. **The key is never in `UserDefaults` and never in `AgentSettings`.** Only
///    the host, the model name, and the consent flag live in defaults — none of
///    which is a secret. The key is in the keychain, keyed by host.
/// 3. **Consent names the host.** Turning this on shows a sheet that says which
///    machine the user's note titles and bodies will be sent to, in those words.
///
/// Phase 1 is on-demand only: nothing here is reachable from `RoutineDriver` or
/// `unlirice-agent`. Notes leaving the machine while nobody is present is a
/// different promise from notes leaving while the user watches.
extension AppStore {
    // MARK: - Configuration

    var reasoningBaseURL: URL? {
        reasoningServerPath.isEmpty ? nil : URL(string: reasoningServerPath)
    }

    var reasoningHost: String? {
        reasoningBaseURL?.host
    }

    /// Whether the user has been shown, and accepted, the disclosure for the
    /// host currently configured. Changing the host revokes it — consent to send
    /// notes to one company is not consent to send them to another.
    var isReasoningConsented: Bool {
        guard let host = reasoningHost else { return false }
        return reasoningConsentedHost?.lowercased() == host.lowercased()
    }

    /// Everything that has to be true before a single byte may leave.
    var canRunReasoningHere: Bool {
        reasoningEnabled
            && isReasoningConsented
            && reasoningKeyPresent
            && !(reasoningModelName ?? "").isEmpty
    }

    func refreshReasoningKeyPresence() {
        guard let host = reasoningHost else {
            reasoningKeyPresent = false
            return
        }
        reasoningKeyPresent = ((try? reasoningKeyStore.key(forHost: host)) ?? nil) != nil
    }

    func saveReasoningKey(_ key: String) {
        guard let host = reasoningHost else {
            reasoningMessage = "Set the provider URL first — the key is stored against its host."
            return
        }
        do {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try reasoningKeyStore.removeKey(forHost: host)
            } else {
                try reasoningKeyStore.setKey(trimmed, forHost: host)
            }
            refreshReasoningKeyPresence()
            reasoningMessage = reasoningKeyPresent
                ? "Key saved to your keychain for \(host). It is not written to any file."
                : "Key removed for \(host)."
        } catch {
            reasoningMessage = "The keychain refused: \(error)"
        }
    }

    func forgetReasoningKey() {
        guard let host = reasoningHost else { return }
        try? reasoningKeyStore.removeKey(forHost: host)
        refreshReasoningKeyPresence()
        reasoningMessage = "Key removed for \(host)."
    }

    // MARK: - Consent

    /// The sheet's text. Names the host, says what leaves, and does not soften
    /// it — a checkbox buried in Setup is not what §2 of the design asks for.
    var reasoningDisclosure: String {
        let host = reasoningHost ?? "the provider you configure"
        return """
        Unli Rice will send the **titles and full bodies** of the notes it shortlists to \
        **\(host)**, using your API key and your account there. That is your own writing \
        leaving this Mac.

        It happens only when you press a button — never on a schedule, never in the \
        background, never while you are away. Nothing is sent unless you configure this, \
        and nothing about the rest of the app changes if you don't.

        Unli Rice has no server. Nothing is sent to calmdownoscar.com, and there are no \
        analytics. Your key is stored in your macOS keychain and is sent only to \
        \(host) itself.

        Every call is listed in the Trust Center — host, time, note count and token \
        estimate. Never the note contents.
        """
    }

    func requestReasoningConsent() {
        guard reasoningHost != nil else {
            reasoningMessage = "Set the provider URL first."
            reasoningEnabled = false
            return
        }
        showingReasoningConsent = true
    }

    func grantReasoningConsent() {
        reasoningConsentedHost = reasoningHost
        showingReasoningConsent = false
        reasoningMessage = "On for \(reasoningHost ?? "your provider"). Runs only when you ask."
    }

    func declineReasoningConsent() {
        reasoningEnabled = false
        showingReasoningConsent = false
        reasoningMessage = "Left off. Nothing has been sent."
    }

    // MARK: - The provider

    /// `NullReasoningProvider` unless every condition above is met.
    ///
    /// The failure mode this shape rules out is the important one: there is no
    /// branch that returns a network-capable provider from a partial
    /// configuration, so "half set up" can never mean "quietly sending".
    func reasoningProvider() -> ReasoningProvider {
        guard canRunReasoningHere,
              let url = reasoningBaseURL,
              let host = reasoningHost,
              let model = reasoningModelName,
              let key = (try? reasoningKeyStore.key(forHost: host)) ?? nil
        else { return NullReasoningProvider() }

        return (try? OpenAICompatibleReasoning(baseURL: url, model: model, apiKey: key))
            ?? NullReasoningProvider()
    }

    private func reasoningRunner() -> ReasoningRunner {
        ReasoningRunner(
            service: service,
            provider: reasoningProvider(),
            log: OutboundCallLog(besideEventLog: dataURL),
            cursorURL: ReasoningCursor.url(besideEventLog: dataURL)
        )
    }

    var reasoningCaps: ReasoningCaps {
        ReasoningCaps(
            maxNotesPerRun: reasoningMaxNotes,
            maxInputTokensPerRun: reasoningMaxTokens,
            maxOutputTokens: 1_500
        )
    }

    // MARK: - Dry run

    /// What a run would send, without sending it. Extends the janitor's existing
    /// promise — you can see what it would do first — to the part that costs
    /// money, where it matters more rather than less.
    func previewReasoning(scope: ReasoningScope, task: String) async {
        guard !reasoningBusy else { return }
        reasoningBusy = true
        defer { reasoningBusy = false }

        let runner = reasoningRunner()
        do {
            let plan = try runner.plan(
                scope: scope, task: task,
                config: JanitorConfig(autonomy: autonomy), caps: reasoningCaps
            )
            runner.recordDryRun(plan)
            reasoningPlan = plan
            reasoningMessage = plan.disclosure
            refreshOutboundCalls()
        } catch {
            reasoningMessage = "Couldn't work out what would be sent: \(error)"
        }
    }

    // MARK: - Running

    func runReasoning(scope: ReasoningScope, task: String, label: String) async {
        guard !reasoningBusy else { return }
        guard canRunReasoningHere else {
            reasoningMessage = "No provider is configured, so nothing was sent."
            return
        }
        reasoningBusy = true
        defer { reasoningBusy = false }

        let runner = reasoningRunner()
        do {
            let plan = try runner.plan(
                scope: scope, task: task,
                config: JanitorConfig(autonomy: autonomy), caps: reasoningCaps
            )
            reasoningPlan = plan
            guard plan.canSend else {
                reasoningMessage = plan.blocked?.explanation ?? "Nothing to send."
                refreshOutboundCalls()
                return
            }

            let report = try await runner.execute(plan)
            reasoningPlan = nil
            reasoningMessage = "\(label): \(report.summary)"
            // A refusal is the model asking for something it may not have. It is
            // worth showing rather than swallowing — it says either the prompt is
            // wrong or the model is, and the user is the one who can tell which.
            if let refusals = report.dispatch?.allRefusals, !refusals.isEmpty {
                reasoningRefusals = refusals.map(\.explanation)
            } else {
                reasoningRefusals = []
            }
            refreshOutboundCalls()
            routineDriver.announceNow(settings: agentSettings)
            reload()
        } catch {
            reasoningMessage = "\(error)"
        }
    }

    /// "Run it here" for one of the clipboard prompts. The clipboard item is
    /// untouched and stays the primary path — it is the only one that works with
    /// a ChatGPT Plus subscription and no API key.
    func runPromptHere(_ prompt: CleanupPrompt) async {
        guard let task = prompt.dispatchTask else { return }
        await runReasoning(scope: prompt.scope, task: task, label: prompt.title)
    }

    /// "Run it here" for the review queue. Same ladder: the model may propose
    /// and tag, and every structural resolution still waits for a human — which
    /// is why this asks it to sharpen the queue rather than clear it.
    func runReviewHere() async {
        await runReasoning(
            scope: .pendingReviews,
            task: """
            Each note below carries at least one unresolved flag raised by the local rules \
            or by another agent. Read them and say which flags are worth my time.

            Where a flag is right and I should act, raise one flag_for_review restating it \
            in one clear sentence with the evidence you found. Where two of these notes are \
            genuinely the same idea, say which is older and should be the keeper — as a \
            flag, not as an action; resolving it is mine to do. Where a flag looks like a \
            false positive, say nothing about that note at all.

            You cannot resolve, archive, or merge anything, and should not try.
            """,
            label: "Review queue"
        )
    }

    // MARK: - Trust Center

    func refreshOutboundCalls() {
        outboundCalls = (try? OutboundCallLog(besideEventLog: dataURL).list()) ?? []
    }
}
