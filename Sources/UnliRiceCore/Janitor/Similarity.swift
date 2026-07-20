import Foundation

/// How the janitor decides two pieces of text are about the same thing.
///
/// The seam exists so that *which pairs get noticed* is pluggable while *what
/// the janitor may do with them* is not. A bundled on-device embedder used to
/// live behind it and was removed once measured (PROJECT_NOTES.md);
/// `RemoteSimilarity` is the bring-your-own replacement. Whatever is plugged in,
/// `JanitorRunner` still calls only `tagNote` and `flagForReview`.
public protocol SimilarityProvider: Sendable {
    /// 0.0 (unrelated) to 1.0 (identical).
    func similarity(_ a: String, _ b: String) -> Double

    /// What counts as "the same thing" *on this provider's scale*.
    ///
    /// Both providers return 0...1, but the distributions are nothing alike:
    /// Jaccard over tokens gives two unrelated titles ~0.0, while embedding
    /// cosine gives them ~0.5 simply because both are English sentences. A
    /// single hardcoded 0.75 would mean "near-identical" for one and "flag
    /// everything" for the other, so the number travels with the provider that
    /// produced it.
    var calibration: SimilarityCalibration { get }
}

public struct SimilarityCalibration: Sendable {
    /// The default duplicate threshold, used at Eco and Balanced.
    public let duplicateThreshold: Double
    /// The looser one Aggressive opts into: more pairs surface, more of them
    /// wrong. That's the trade the slider offers.
    public let aggressiveDuplicateThreshold: Double

    /// A lower bar than either duplicate threshold: "worth a [[link]]," not
    /// "probably the same note." Used by `DraftAdvisor` to suggest related
    /// notes at creation time — a different question from "is this a
    /// duplicate," so it gets its own number rather than reusing one of the
    /// two above. Starting values, not measured the way the duplicate
    /// thresholds were (`janitor-calibrate` only reports the duplicate bar
    /// today) — reasonable to re-tune the same way if suggestions turn out too
    /// noisy or too quiet in practice.
    public let relatednessThreshold: Double

    public init(
        duplicateThreshold: Double,
        aggressiveDuplicateThreshold: Double,
        relatednessThreshold: Double
    ) {
        self.duplicateThreshold = duplicateThreshold
        self.aggressiveDuplicateThreshold = aggressiveDuplicateThreshold
        self.relatednessThreshold = relatednessThreshold
    }

    /// Token-overlap's numbers, and the default.
    ///
    /// `duplicateThreshold` was 0.75, measured against a 49-note corpus. Over
    /// the 233-note post-ingest corpus that queued 21 pairs at Balanced, where
    /// 0.85 queues 3 — and the pairs between the two are the same kind of false
    /// positive (`lib.js` ⟷ `compact.js`: different files sharing a path
    /// prefix). 0.85 is also *more* selective than the embedding model this
    /// replaced was at its own threshold, which is the finding that removed it.
    ///
    /// Re-run `janitor-calibrate` as the corpus grows; the right answer moves,
    /// and it has already moved once.
    public static let tokenOverlap = SimilarityCalibration(
        duplicateThreshold: 0.85,
        aggressiveDuplicateThreshold: 0.65,
        relatednessThreshold: 0.35
    )
}

extension SimilarityProvider {
    public var calibration: SimilarityCalibration { .tokenOverlap }
}

/// The no-model default: Jaccard overlap of normalised word tokens.
///
/// Deliberately dumb. It catches the failure mode AGENTS.md actually warns
/// about — an agent writing "MCP Server Registration" when "MCP server
/// registration notes" already exists — and it will miss anything requiring
/// real semantics. Missing a duplicate costs nothing; the review queue just
/// stays quiet. That asymmetry is why a crude default is safe to ship.
public struct TokenOverlapSimilarity: SimilarityProvider {
    public init() {}

    public func similarity(_ a: String, _ b: String) -> Double {
        let left = Self.tokens(a)
        let right = Self.tokens(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let union = left.union(right).count
        guard union > 0 else { return 0 }
        return Double(left.intersection(right).count) / Double(union)
    }

    static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { $0.count > 1 }
        )
    }
}

/// Levenshtein distance, used only for the typo'd-wiki-link rule where the
/// question is "did someone mistype this title" — a character-level question
/// that token overlap can't answer.
enum TextDistance {
    /// Case-insensitive edit distance, bailing out early once it exceeds `limit`
    /// since every caller only cares about "within 2".
    static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let source = Array(a.lowercased())
        let target = Array(b.lowercased())
        if abs(source.count - target.count) > limit { return limit + 1 }
        if source.isEmpty { return target.count }
        if target.isEmpty { return source.count }

        var previous = Array(0...target.count)
        var current = [Int](repeating: 0, count: target.count + 1)

        for i in 1...source.count {
            current[0] = i
            for j in 1...target.count {
                let substitution = previous[j - 1] + (source[i - 1] == target[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            if current.min() ?? 0 > limit { return limit + 1 }
            swap(&previous, &current)
        }

        return previous[target.count]
    }
}
