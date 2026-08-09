import Foundation

/// Bring-your-own reasoning, speaking `/v1/chat/completions`.
///
/// One hand-rolled client against one wire format covers OpenAI, OpenRouter,
/// Anthropic's compatibility endpoint, Groq, LM Studio and Ollama. There are
/// deliberately **no per-provider SDKs**: the no-external-dependencies property
/// is load-bearing — it is why `swift build` works with no toolchain beyond
/// Xcode, and it is cited in the App Store description.
///
/// `RemoteSimilarity` already speaks the sibling `/v1/embeddings` shape, so this
/// is the same mental model with the same settings surface.
///
/// **This type is the one place in the app that may talk to a non-local host,
/// and that is the whole point of it existing separately.**
/// `RemoteSimilarity.isLoopback` is untouched — embeddings remain localhost-only
/// forever. Its comment asked that remote endpoints be "an explicit, separate,
/// clearly-labelled decision — not a side effect of this field accepting a
/// string." This is that separate decision: its own type, its own settings, its
/// own one-time consent naming the host, and its own line in the Trust Center
/// every time it fires. Nothing here relaxes anything there.
public final class OpenAICompatibleReasoning: ReasoningProvider, @unchecked Sendable {
    public enum Failure: Error, CustomStringConvertible {
        case noAPIKey(String)
        case notHTTP(String)
        case httpError(status: Int)
        case badResponse(String)

        public var description: String {
            switch self {
            case .noAPIKey(let host):
                return "No API key is stored for \(host). Nothing was sent."
            case .notHTTP(let scheme):
                return "\(scheme) isn't a URL this can call. Use an http or https base URL ending in /v1."
            case .httpError(let status):
                return "The provider replied HTTP \(status)."
            case .badResponse(let detail):
                return "The provider replied with something unusable: \(detail)"
            }
        }
    }

    public let baseURL: URL
    public let model: String
    private let apiKey: String
    private let session: URLSession

    public var host: String? { baseURL.host }
    public var modelName: String { model }

    /// Throws rather than storing an unusable configuration. The empty-key case
    /// matters most: it is what guarantees that a half-configured provider
    /// cannot reach the network at all, so "no key ⇒ no outbound request" holds
    /// by construction and not by a caller remembering to check.
    public init(baseURL: URL, model: String, apiKey: String, session: URLSession = .shared) throws {
        let scheme = baseURL.scheme?.lowercased() ?? ""
        guard scheme == "http" || scheme == "https", baseURL.host != nil else {
            throw Failure.notHTTP(baseURL.scheme.map { "\($0)://" } ?? baseURL.absoluteString)
        }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Failure.noAPIKey(baseURL.host ?? baseURL.absoluteString) }

        self.baseURL = baseURL
        self.model = model
        self.apiKey = key
        self.session = session
    }

    public func judge(_ request: JudgementRequest) async throws -> JudgementResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The key goes to the endpoint it belongs to and nowhere else. There is
        // no calmdownoscar server in this design and there must never be one.
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "max_tokens": request.maxOutputTokens,
            // Judgement, not prose. The lowest temperature every one of these
            // endpoints accepts.
            "temperature": 0,
            "messages": [
                ["role": "system", "content": request.system],
                ["role": "user", "content": request.user]
            ]
        ])

        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw Failure.badResponse("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The body can quote the request back, so it is never surfaced or
            // logged — only the status, which is metadata.
            throw Failure.httpError(status: http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.badResponse("not a JSON object")
        }
        guard let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw Failure.badResponse("no `choices[0].message.content`")
        }

        let usage = object["usage"] as? [String: Any]
        return JudgementResponse(
            // Prefer what the provider says it ran, since a gateway may route
            // an alias elsewhere and the attribution has to name the real thing.
            model: (object["model"] as? String) ?? model,
            text: content,
            promptTokens: usage?["prompt_tokens"] as? Int,
            completionTokens: usage?["completion_tokens"] as? Int
        )
    }
}
