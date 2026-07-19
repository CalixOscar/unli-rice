import Foundation
import MLX
import MLXEmbedders
import UnliRiceCore

/// The local MLX embedding model, plugged into the janitor through the
/// `SimilarityProvider` seam that was left for it (PROJECT_NOTES.md #5).
///
/// Note what this does *not* change: the janitor's permissions. Embeddings
/// decide which pairs of notes get *noticed*, never what may be done about
/// them — a duplicate found by a model still goes to the review queue as a
/// proposal, exactly like one found by token overlap. Nothing here can archive,
/// untag, or delete anything, because `JanitorRunner` still only has `tagNote`
/// and `flagForReview` and this file cannot reach either.
///
/// It is a small *embedding* model, not a generative one — the assessment that
/// 1–3B generative models are unreliable at cross-time concept matching still
/// stands, and nothing here asks a model to write prose or make a decision.
///
/// ## Why there's a cache instead of an async protocol
///
/// `SimilarityProvider.similarity` is synchronous, and `Janitor.scan` is a pure
/// synchronous function — that's load-bearing, it's what makes the rules
/// testable without a model. Rather than make the whole scan async to
/// accommodate MLX, this embeds every text up front in `warm(_:)` and then
/// answers from a dictionary. That works because the janitor only ever compares
/// note *titles*, and every title is known before a scan starts.
///
/// Any pair that misses the cache falls back to token overlap rather than
/// returning 0. Silently answering "not similar" would make a cache miss look
/// like a confident judgement.
public final class MLXSimilarity: SimilarityProvider, @unchecked Sendable {
    /// Cosine on normalised embeddings, not Jaccard — a different scale
    /// entirely, and much more compressed than intuition suggests.
    ///
    /// Measured over the real 49-note corpus (`Scripts/mlx-run
    /// janitor-calibrate`), the *median* score between two unrelated titles is
    /// 0.82, because they are all short English-ish strings and the model says
    /// so. The whole useful signal lives in the last two percent:
    ///
    ///     >= 0.90 : 136 pairs      >= 0.97 :  17 pairs
    ///     >= 0.96 :  36 pairs      >= 0.985:   8 pairs
    ///
    /// So these numbers are deliberately extreme, and picking them by intuition
    /// would have been badly wrong — 0.92 "looks strict" and would have queued
    /// 78 proposals where token overlap queues 18.
    /// `relatednessThreshold: 0.90` is the next real inflection point below the
    /// duplicate bar in that same table (136 of 1176 pairs in the real corpus
    /// clear it) — a genuinely looser bar for "worth a [[link]]," not a
    /// rounding of the duplicate threshold.
    public static let defaultCalibration = SimilarityCalibration(
        duplicateThreshold: 0.985,
        aggressiveDuplicateThreshold: 0.97,
        relatednessThreshold: 0.90
    )

    public let calibration: SimilarityCalibration

    /// bge-micro: ~17M parameters, tens of MB on disk. Deliberately the small
    /// end — this runs on the user's own machine alongside everything else, and
    /// the task (are these two short titles the same idea?) does not need a
    /// large model.
    public static let defaultModel = ModelConfiguration.bge_micro

    private let container: ModelContainer
    private let fallback = TokenOverlapSimilarity()

    private let lock = NSLock()
    private var embeddings: [String: [Float]] = [:]

    private init(container: ModelContainer, calibration: SimilarityCalibration) {
        self.container = container
        self.calibration = calibration
    }

    /// Downloads (first run only) and loads the model.
    ///
    /// Throws if the model can't be fetched or loaded — callers are expected to
    /// fall back to `TokenOverlapSimilarity` rather than treat this as fatal.
    /// The janitor working slightly less well offline is fine; the app failing
    /// to open because a model server was down is not.
    public static func load(
        model: ModelConfiguration = defaultModel,
        calibration: SimilarityCalibration = defaultCalibration,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> MLXSimilarity {
        let container = try await MLXEmbedders.loadModelContainer(configuration: model) { p in
            progress(p.fractionCompleted)
        }
        return MLXSimilarity(container: container, calibration: calibration)
    }

    /// Embeds everything the coming scan will ask about.
    ///
    /// Also the only place the model actually runs: `similarity` is pure
    /// arithmetic afterwards. Already-cached texts are skipped, so calling this
    /// before every run costs nothing on a corpus that hasn't changed.
    public func warm(_ texts: [String]) async {
        let pending = lock.withLock {
            Array(Set(texts.filter { !$0.isEmpty && embeddings[$0] == nil }))
        }
        guard !pending.isEmpty else { return }

        // Batched to keep peak memory flat and bounded regardless of corpus
        // size — 48 notes today, but nothing here should get worse at 5,000.
        for batch in stride(from: 0, to: pending.count, by: Self.batchSize).map({
            Array(pending[$0 ..< min($0 + Self.batchSize, pending.count)])
        }) {
            let vectors = await embed(batch)
            lock.withLock {
                for (text, vector) in zip(batch, vectors) {
                    embeddings[text] = vector
                }
            }
        }
    }

    private static let batchSize = 32

    public func similarity(_ a: String, _ b: String) -> Double {
        let (left, right) = lock.withLock { (embeddings[a], embeddings[b]) }
        guard let left, let right, left.count == right.count else {
            // Not embedded — say so honestly by deferring to the provider that
            // can answer without a model, instead of reporting "unrelated".
            return fallback.similarity(a, b)
        }
        return Self.cosine(left, right)
    }

    /// Embeddings are L2-normalised at pooling time, so this is a dot product;
    /// the divisor is kept for the case where they aren't, and to keep the
    /// result inside 0...1 rather than trusting an invariant set elsewhere.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for (x, y) in zip(a, b) {
            dot += x * y
            normA += x * x
            normB += y * y
        }
        guard normA > 0, normB > 0 else { return 0 }
        let value = Double(dot / (normA.squareRoot() * normB.squareRoot()))
        return min(max(value, 0), 1)
    }

    private func embed(_ texts: [String]) async -> [[Float]] {
        await container.perform { model, tokenizer, pooling -> [[Float]] in
            let encoded = texts.map { tokenizer.encode(text: $0, addSpecialTokens: true) }
            let padTo = encoded.reduce(into: 16) { $0 = max($0, $1.count) }
            let padToken = tokenizer.eosTokenId ?? 0

            let padded = stacked(
                encoded.map { tokens in
                    MLXArray(tokens + Array(repeating: padToken, count: padTo - tokens.count))
                }
            )
            let mask = (padded .!= padToken)
            let pooled = pooling(
                model(padded, positionIds: nil, tokenTypeIds: MLXArray.zeros(like: padded), attentionMask: mask),
                normalize: true,
                applyLayerNorm: true
            )
            // Must eval inside the actor: MLXArray isn't Sendable and can't
            // cross the isolation boundary lazily.
            pooled.eval()
            return pooled.map { $0.asArray(Float.self) }
        }
    }
}
