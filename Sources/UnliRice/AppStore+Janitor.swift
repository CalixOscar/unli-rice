import Foundation
import UnliRiceCore

/// Which similarity engine is in play, for the one line of UI that reports it.
///
/// Worth surfacing rather than hiding: the engine changes *which* notes the
/// janitor notices, so a user reading a proposal list deserves to know what
/// produced it. That was true when the choice was "did the bundled model load",
/// and it stays true now the choice is "is a bring-your-own server configured".
enum SimilarityEngine: Equatable {
    case tokenOverlap
    case remote(String)
    case unavailable(String)

    var label: String {
        switch self {
        case .tokenOverlap: return "word overlap, on-device"
        case .remote(let model): return "\(model), your local server"
        case .unavailable(let reason): return "word overlap — your server is unreachable (\(reason))"
        }
    }
}

/// The janitor, driven by hand.
///
/// `preview` is offered first and deliberately reads as the default action —
/// the janitor's whole contract is that you can see what it would do before it
/// does any of it.
extension AppStore {
    /// What the janitor would do at the current autonomy level. Writes nothing.
    func previewJanitor() async {
        guard !janitorBusy else { return }
        janitorBusy = true
        defer { janitorBusy = false }

        do {
            let provider = await similarityProvider()
            let runner = JanitorRunner(service: service, similarity: provider)
            janitorPreview = try runner.preview(config: JanitorConfig(autonomy: autonomy))
            janitorSummary = janitorPreview.isEmpty
                ? "Janitor found nothing to do at this level."
                : "\(janitorPreview.count) thing\(janitorPreview.count == 1 ? "" : "s") the janitor would act on. Nothing has been changed."
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Applies cosmetic proposals and queues structural ones. The split is
    /// enforced inside `JanitorRunner` by type, not here — this method could not
    /// grant the janitor a broader permission even if it tried to.
    func runJanitorNow() async {
        guard !janitorBusy else { return }
        janitorBusy = true
        defer { janitorBusy = false }

        do {
            let provider = await similarityProvider()
            let runner = JanitorRunner(service: service, similarity: provider)
            let report = try runner.run(config: JanitorConfig(autonomy: autonomy))
            janitorPreview = []
            janitorSummary = report.summary
            // The queue filling up is worth a line in the notification centre
            // however it got full — by hand here, or unattended in the agent.
            routineDriver.announceNow(settings: agentSettings)
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    var autonomy: JanitorAutonomy {
        JanitorAutonomy(rawValue: autonomyLevel) ?? .balanced
    }

    // MARK: - The engine

    /// Token overlap unless the user has pointed the app at their own local
    /// embedding server.
    ///
    /// There is no bundled model any more. A dry run over the real corpus found
    /// that a small on-device embedder surfaced the same top pairs as token
    /// overlap and made the same false positives, so it was removed rather than
    /// carried — see PROJECT_NOTES.md. `RemoteSimilarity` is the seam for anyone
    /// running something genuinely better locally.
    ///
    /// A failure is not fatal and not an error banner: the janitor falls back to
    /// token overlap and keeps working, just less perceptively. The one
    /// unacceptable outcome would be pretending a model answered when it didn't,
    /// which is why `SimilarityEngine` is shown in the panel.
    private func similarityProvider() async -> SimilarityProvider {
        guard let url = embeddingServerURL, let model = embeddingModelName, !model.isEmpty else {
            similarityEngine = .tokenOverlap
            return TokenOverlapSimilarity()
        }
        do {
            let remote = try RemoteSimilarity(baseURL: url, model: model)
            await remote.warm(notes.map(\.title))
            similarityEngine = .remote(model)
            return remote
        } catch {
            similarityEngine = .unavailable(Self.shortReason(error))
            return TokenOverlapSimilarity()
        }
    }

    private static func shortReason(_ error: Error) -> String {
        let text = "\(error)"
        return text.count > 60 ? String(text.prefix(57)) + "…" : text
    }
}
