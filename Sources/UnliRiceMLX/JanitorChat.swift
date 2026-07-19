import Foundation
import MLXLLM
import MLXLMCommon
import UnliRiceCore

/// The local generative model behind the chat panel — distinct from
/// `MLXSimilarity`, which only ever embeds and never generates text.
///
/// **This type cannot write to the event log, by construction, not by
/// discipline.** Its only method takes a `String` and returns a `String`.
/// There is no tool-calling loop, no function-calling schema, nothing that
/// lets a model's output invoke `tagNote`, `resolveReview`, or anything else —
/// the chat panel renders whatever comes back as plain text, and every
/// structural action still requires a human to press Accept/Reject on a
/// `ReviewCluster`, exactly as it did before this file existed. That mirrors
/// how `Janitor.scan` holds no `NoteService` reference (PROJECT_NOTES.md,
/// decision #3): the type that only *thinks* is kept separate from the type
/// that's allowed to *write*.
///
/// PROJECT_NOTES.md's own assessment, from building the janitor's similarity
/// rules, is that 1–3B generative models are unreliable for nuanced cross-time
/// concept matching. This is exactly that class of model — chosen because the
/// alternative (an API model) would send note content off-device, which is a
/// real change in posture for an app whose whole pitch is local memory. The
/// chat panel surfaces that tradeoff rather than presenting answers as
/// authoritative; see `ChatContext.preamble`, which every prompt carries.
public final class JanitorChat: @unchecked Sendable {
    /// Small enough to load and run at conversational speed on-device;
    /// instruct-tuned, which matters more here than raw size for "explain this
    /// and stop" style answers.
    public static let defaultModel = ModelConfiguration(id: "mlx-community/Qwen3-1.7B-4bit")

    private let container: ModelContainer
    private let parameters: GenerateParameters

    private init(container: ModelContainer, parameters: GenerateParameters) {
        self.container = container
        self.parameters = parameters
    }

    public static func load(
        model: ModelConfiguration = defaultModel,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> JanitorChat {
        let container = try await MLXLMCommon.loadModelContainer(configuration: model) { p in
            progress(p.fractionCompleted)
        }
        // Bounded and fairly deterministic: this is meant to answer "which of
        // these looks like the keeper" consistently, not write varied prose.
        // maxTokens keeps a run on a small on-device model from wandering.
        let parameters = GenerateParameters(maxTokens: 400, temperature: 0.3)
        return JanitorChat(container: container, parameters: parameters)
    }

    /// One prompt in, one answer out — no memory kept between calls, and no
    /// `ChatSession`.
    ///
    /// Two things pushed this off the simplified `ChatSession` API and onto
    /// `UserInput`/`generate(...)` directly, both found by hitting the failure
    /// in the actual running app, not anticipated in advance:
    ///
    /// 1. `ChatSession.respond(to:)` replaces its whole message list on every
    ///    call (see `MLXLMCommon/Streamlined.swift`), which silently drops any
    ///    `instructions:` passed at construction the moment the first question
    ///    is asked. A fresh call each turn with the framing folded into
    ///    `prompt` itself (`ChatContext.questionPrompt`) sidesteps that
    ///    entirely regardless of what that internal behavior does.
    /// 2. Qwen3's chat template defaults to emitting a `<think>...</think>`
    ///    reasoning block before the real answer, and `ChatSession` has no way
    ///    to turn that off — the template only listens for an `enable_thinking`
    ///    Jinja variable, which is threaded through as `UserInput.
    ///    additionalContext`, a parameter `ChatSession` doesn't expose. Without
    ///    it, the panel showed the model's raw internal monologue as if it were
    ///    the answer (contradicting itself, second-guessing, never reaching a
    ///    conclusion within the token budget) instead of the 3–4 sentence
    ///    answer actually asked for.
    ///
    /// `stripThinkingBlock` is a second, independent layer: if `enable_thinking:
    /// false` primes the prompt correctly, the model never generates a `<think>`
    /// tag and this is a no-op. It stays in because "the template mechanism
    /// works as documented" is exactly the kind of assumption that already
    /// failed once above.
    public func ask(_ prompt: String) async throws -> String {
        let raw = try await container.perform { (context: ModelContext) async throws -> String in
            let userInput = UserInput(
                chat: [.user(prompt)],
                additionalContext: ["enable_thinking": false]
            )
            let lmInput = try await context.processor.prepare(input: userInput)
            // Explicit `[Int]` disambiguates from the sibling per-token overload
            // of `generate(input:parameters:context:didGenerate:)` — both take
            // a closure returning `GenerateDisposition` and differ only in
            // whether it's handed the whole token batch or one token at a time.
            let result = try MLXLMCommon.generate(
                input: lmInput, parameters: self.parameters, context: context
            ) { (_: [Int]) in .more }
            return result.output
        }
        // Pure string logic lives in UnliRiceCore (ChatContext) rather than
        // here, same as everywhere else in this codebase that separates "can
        // be unit tested without a model" from "needs MLX" — see
        // ChatContextTests.swift.
        return ChatContext.stripThinkingBlock(raw)
    }
}
