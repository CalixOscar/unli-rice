import Foundation

/// One judgement round-trip, in the shape any chat endpoint understands.
///
/// Deliberately dumb. It carries a system message, a user message, and a
/// ceiling — and nothing about *what may happen next*. Every question of
/// authority lives in `RestrictedReasoningDispatcher`, on the far side of this
/// type, because a capability boundary that travels inside a prompt is not a
/// boundary (see §4 of docs/BYO_LLM.md).
public struct JudgementRequest: Sendable, Equatable {
    public let system: String
    public let user: String
    public let maxOutputTokens: Int

    public init(system: String, user: String, maxOutputTokens: Int) {
        self.system = system
        self.user = user
        self.maxOutputTokens = maxOutputTokens
    }

    /// Characters ÷ 4, the usual rough conversion.
    ///
    /// This is an estimate and every surface that shows it says so. It exists to
    /// enforce a cap *before* anything leaves the machine, which a real token
    /// count cannot do — the only thing that can count exactly is the provider,
    /// and asking it means having already sent the text.
    public var estimatedInputTokens: Int {
        (system.count + user.count + 3) / 4
    }
}

/// What came back. `text` is raw model output — nothing has been decoded, and
/// certainly nothing has been applied.
public struct JudgementResponse: Sendable, Equatable {
    /// The model that answered, as the provider reported it. This is what ends
    /// up in the `source` of every write the answer causes — locked-in decision
    /// #4, and the thing that makes a bad model's output revocable in bulk.
    public let model: String
    public let text: String
    /// Usage as the provider counted it, when it bothers to say. Preferred over
    /// `estimatedInputTokens` for the spend estimate, precisely because it is
    /// the one number that isn't a guess.
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(model: String, text: String, promptTokens: Int? = nil, completionTokens: Int? = nil) {
        self.model = model
        self.text = text
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public static let none = JudgementResponse(model: "", text: "")
}

/// The seam, mirroring `SimilarityProvider` — the pattern that survived the MLX
/// removal because the seam outlived the implementation.
public protocol ReasoningProvider: Sendable {
    /// The host this provider talks to, for the disclosure sheet and the
    /// outbound-call log. `nil` means it talks to nothing, and is the only
    /// honest answer for `NullReasoningProvider`.
    var host: String? { get }

    /// The model this provider will attribute its answers to.
    var modelName: String { get }

    func judge(_ request: JudgementRequest) async throws -> JudgementResponse
}

extension ReasoningProvider {
    /// Whether this provider can reach anything at all. The whole app checks
    /// this before offering "Run it here" anywhere.
    public var isConfigured: Bool { host != nil }
}

/// The default, and it must stay the default.
///
/// No key, no network, today's rule-based behaviour unchanged. The overwhelming
/// majority of installs will never configure a provider, and for them nothing
/// about this app may change — including its network activity, which for this
/// type is *nothing*: it holds no `URLSession`, so there is no code path from
/// here to a socket.
///
/// It answers with an empty response rather than throwing. A throw would make
/// "no provider configured" look like a failure in every report; an empty answer
/// decodes to zero actions, which is the truth.
public struct NullReasoningProvider: ReasoningProvider {
    public init() {}
    public var host: String? { nil }
    public var modelName: String { "" }
    public func judge(_ request: JudgementRequest) async throws -> JudgementResponse { .none }
}
