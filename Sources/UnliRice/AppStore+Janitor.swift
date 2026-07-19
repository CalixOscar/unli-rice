import Foundation
import UnliRiceCore
import UnliRiceMLX

/// What the similarity engine is doing, for the one line of UI that reports it.
///
/// Worth surfacing rather than hiding: whether the local model loaded changes
/// which notes the janitor notices, so a user reading a proposal list deserves
/// to know which engine produced it.
enum SimilarityEngine: Equatable {
    case tokenOverlap
    case loading(Double)
    case mlx
    case unavailable(String)

    var label: String {
        switch self {
        case .tokenOverlap: return "word overlap (local model not loaded yet)"
        case .loading(let fraction): return "loading local model… \(Int(fraction * 100))%"
        case .mlx: return "MLX embeddings, on-device"
        case .unavailable(let reason): return "word overlap — model unavailable (\(reason))"
        }
    }
}

/// The janitor, driven by hand.
///
/// Human-triggered only: there is no timer, no idle trigger, and nothing here
/// runs at launch. `preview` is offered first and deliberately reads as the
/// default action — the janitor's whole contract is that you can see what it
/// would do before it does any of it.
extension AppStore {
    /// What the janitor would do at the current autonomy level. Writes nothing.
    func previewJanitor() async {
        guard !janitorBusy else { return }
        janitorBusy = true
        defer { janitorBusy = false }

        do {
            let provider = await similarityProvider()
            await warm(provider)
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
            await warm(provider)
            let runner = JanitorRunner(service: service, similarity: provider)
            let report = try runner.run(config: JanitorConfig(autonomy: autonomy))
            janitorPreview = []
            janitorSummary = report.summary
            reload()
        } catch {
            errorMessage = "\(error)"
        }
    }

    var autonomy: JanitorAutonomy {
        JanitorAutonomy(rawValue: autonomyLevel) ?? .balanced
    }

    // MARK: - The engine

    /// Loads the MLX model once, on first use, and remembers a failure so a
    /// machine that can't load it doesn't retry on every click.
    ///
    /// A failure is not fatal and not even an error banner: the janitor falls
    /// back to token overlap and keeps working, just less perceptively. The one
    /// thing that would be unacceptable is pretending the model is loaded when
    /// it isn't, which is why `SimilarityEngine` is shown in the panel.
    private func similarityProvider() async -> SimilarityProvider {
        if let loaded = mlxSimilarity { return loaded }
        if case .unavailable = similarityEngine { return TokenOverlapSimilarity() }

        similarityEngine = .loading(0)
        do {
            let similarity = try await MLXSimilarity.load { fraction in
                Task { @MainActor [weak self] in
                    self?.similarityEngine = .loading(fraction)
                }
            }
            mlxSimilarity = similarity
            similarityEngine = .mlx
            return similarity
        } catch {
            similarityEngine = .unavailable(Self.shortReason(error))
            return TokenOverlapSimilarity()
        }
    }

    /// Embeds every title the scan is about to compare. Titles only, because
    /// titles are the only thing `Janitor` asks the provider about — see the
    /// note on `MLXSimilarity.warm`.
    private func warm(_ provider: SimilarityProvider) async {
        guard let mlx = provider as? MLXSimilarity else { return }
        await mlx.warm(notes.map(\.title))
    }

    private static func shortReason(_ error: Error) -> String {
        let text = "\(error)"
        return text.count > 60 ? String(text.prefix(57)) + "…" : text
    }
}
