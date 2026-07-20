import Foundation

/// Bring-your-own embeddings, for someone already running a local model server.
///
/// This is what replaced the bundled on-device model. The measurement that
/// removed MLX (see PROJECT_NOTES.md) found that a 17M-parameter embedder
/// surfaced the *same* top pairs as token overlap and made the same mistakes,
/// so shipping one wasn't worth a package-wide dependency. But a user running a
/// genuinely capable model locally is a different case, and the seam that made
/// MLX pluggable is still here — so they can plug into it.
///
/// Speaks the OpenAI `/v1/embeddings` shape, which LM Studio and Ollama both
/// serve. Typical base URLs: `http://localhost:1234/v1` (LM Studio),
/// `http://localhost:11434/v1` (Ollama).
///
/// **Deliberately local-only.** `warm(_:)` sends every note title to the
/// endpoint, and note titles are the user's own content. Sending them to a
/// third party is not something to do because a URL was pasted into a settings
/// field, so `isLoopback` refuses anything that isn't localhost. If remote
/// endpoints are ever wanted, that needs to be an explicit, separate,
/// clearly-labelled decision — not a side effect of this field accepting a
/// string.
public final class RemoteSimilarity: SimilarityProvider, @unchecked Sendable {
    public enum Failure: Error, CustomStringConvertible {
        case notLoopback(String)
        case badResponse(String)

        public var description: String {
            switch self {
            case .notLoopback(let host):
                return "\(host) isn't a local address. Embeddings are only sent to localhost — see RemoteSimilarity."
            case .badResponse(let detail):
                return "The embedding server replied with something unusable: \(detail)"
            }
        }
    }

    /// Same shape as the removed `MLXSimilarity`: `similarity` is synchronous
    /// because `Janitor.scan` is a pure function, so every title is embedded up
    /// front by `warm(_:)` and read from this cache. A cache miss falls back to
    /// token overlap rather than returning 0 — answering "not similar" would
    /// dress a miss up as a judgement.
    private var vectors: [String: [Double]] = [:]
    private let fallback = TokenOverlapSimilarity()
    private let baseURL: URL
    private let model: String
    private let session: URLSession

    public init(baseURL: URL, model: String, session: URLSession = .shared) throws {
        guard Self.isLoopback(baseURL) else {
            throw Failure.notLoopback(baseURL.host ?? baseURL.absoluteString)
        }
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    /// Embeds every title a scan is about to compare. Titles only — that's all
    /// `Janitor` ever asks the provider about.
    public func warm(_ titles: [String]) async {
        let missing = Array(Set(titles)).filter { vectors[$0] == nil }
        guard !missing.isEmpty else { return }
        // One request per batch, not per title: 233 titles is 233 round trips
        // otherwise, and local servers are not fast at that.
        for chunk in stride(from: 0, to: missing.count, by: 64).map({
            Array(missing[$0..<min($0 + 64, missing.count)])
        }) {
            guard let embedded = try? await embed(chunk) else { continue }
            for (title, vector) in zip(chunk, embedded) { vectors[title] = vector }
        }
    }

    public func similarity(_ a: String, _ b: String) -> Double {
        guard let left = vectors[a], let right = vectors[b] else {
            return fallback.similarity(a, b)
        }
        return Self.cosine(left, right)
    }

    /// Thresholds travel with the provider because the scales mean nothing
    /// alike — the lesson the MLX work paid for. These start at the numbers the
    /// removed embedder used; anyone plugging in their own model should re-run
    /// `janitor-calibrate` against it rather than trusting them.
    public var calibration: SimilarityCalibration {
        SimilarityCalibration(
            duplicateThreshold: 0.98,
            aggressiveDuplicateThreshold: 0.97,
            relatednessThreshold: 0.90
        )
    }

    // MARK: - Private

    private func embed(_ inputs: [String]) async throws -> [[Double]] {
        var request = URLRequest(url: baseURL.appendingPathComponent("embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["model": model, "input": inputs]
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw Failure.badResponse("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = object["data"] as? [[String: Any]]
        else { throw Failure.badResponse("no `data` array") }

        return rows.compactMap { $0["embedding"] as? [Double] }
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }
        guard normA > 0, normB > 0 else { return 0 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}
