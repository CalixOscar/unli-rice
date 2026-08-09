# Design: bring-your-own LLM for janitor judgement and prompt dispatch

**Authored by:** Claude Code, 2026-08-09, at the founder's request.
**Status:** Phase 1 built, 2026-08-09, on `feature/byo-llm` off `main`. `swift build` and
`swift test` (294 tests) are green. Phase 2 remains design-only and needs an entitlement
decision that touches App Store review — see §8.
**Decisions taken by the founder, 2026-08-09:** run **on demand first, unattended later**;
the LLM may write **proposals, derived notes, and tags**.

---

## What this is, and what it deliberately isn't

Unli Rice's premise is that it holds the memory and *something else* does the reasoning.
Today that "something else" reaches the vault two ways: an agent connects in over MCP, or
the user copies a prompt out to the clipboard. This adds a third transport — the app can
call an endpoint the user configured — and changes nothing about the premise. The vault
still holds; a model still reasons; the model is still the user's own, paid for by the
user, chosen by the user.

It is **not** a bundled model (that was measured and removed — see PROJECT_NOTES.md on
the MLX removal), **not** a subscription, and **not** a hosted service. There is no
calmdownoscar server anywhere in this design and there must never be one.

The gap it closes is already named in the codebase. `ContentView.swift`'s `CleanupMenu`
comment says the work these prompts describe "needs a model that can read all of them,
and the model that can do that is the one the user already has connected." Right now the
only way to get that model's judgement is for a human to be present with a clipboard. The
janitor runs at 3am and can only count token overlap.

---

## 1. The seam

Mirror `SimilarityProvider` exactly. That pattern is already proven in this repo — it
survived the MLX removal precisely because the seam outlived the implementation.

```swift
public protocol ReasoningProvider: Sendable {
    func judge(_ request: JudgementRequest) async throws -> JudgementResponse
}
```

- **`NullReasoningProvider`** — the default, and it must stay the default. No key, no
  network, today's rule-based behaviour unchanged. This is a free open-source app; the
  overwhelming majority of installs will never configure a key, and for them nothing
  about the app may change, including its network behaviour.
- **`OpenAICompatibleReasoning`** — speaks `/v1/chat/completions`. One client covers
  OpenAI, OpenRouter, Anthropic's compatibility endpoint, Groq, LM Studio and Ollama.
  `RemoteSimilarity` already speaks the sibling `/v1/embeddings` shape, so the settings
  UI, the mental model, and the local-server story all come for free.

**Do not add per-provider SDKs.** The no-external-dependencies property is load-bearing:
it is why `swift build` works with no toolchain beyond Xcode, and it is cited in the App
Store description. One hand-rolled client against one wire format keeps it.

## 2. The loopback rule stays exactly as it is

`RemoteSimilarity.isLoopback` is not relaxed, not parameterised, not touched. Its comment
asked that remote endpoints be "an explicit, separate, clearly-labelled decision — not a
side effect of this field accepting a string." This is that separate decision, and it
gets its own type, its own settings surface, and its own consent. Embeddings remain
localhost-only.

Consent for the new provider:

- Default **off**. When off, the app makes no outbound request, ever.
- Turning it on shows a one-time sheet that names the host, states plainly that note
  titles and bodies will be sent there, and requires an explicit action. Not a checkbox
  buried in Setup.
- The Trust Center gets an outbound-call log — host, timestamp, note count, token
  estimate, outcome. It already exists to answer "is this actually doing what it says";
  "what left this machine" is the same question. Log metadata, never note contents,
  matching the existing diagnostics rule.

## 3. Key storage

**Keychain.** `kSecClassGenericPassword`, account keyed by provider host.

There is no Keychain usage anywhere in this codebase today, so this is greenfield — and
it must not follow either existing pattern:

- **Not `UserDefaults`.** Readable by anything running as the user.
- **Not `AgentSettings`.** That is a plain JSON file at a fixed path, and its own doc
  comment advertises that someone can `cat` it to debug the daemon. A key there is a key
  on disk in plaintext.

The studio guardrails' backend security floor applies in full: no secret in the binary or
the repo, and a key that must reach a client is restricted at the provider console. Since
this is the *user's* key for the *user's* account, the app's obligation is storage and
never transmitting it anywhere but the endpoint it belongs to.

## 4. The authority ladder — enforced by types, not by prompt

The founder's decision was proposals + derived notes + tagging. Three tiers, and the
boundary between them is a restricted dispatcher, not an instruction the model is asked
to follow. A capability boundary that lives in a prompt is not a boundary.

| Tier | What it may do | Why it's safe |
|---|---|---|
| **Propose** | `flag_for_review` only | Locked-in decision #3. Every structural judgement — merge, dedupe, "these conflict" — is *always* this tier and always waits for a human |
| **Own** | Create and rewrite notes it authored | Scoped by title prefix so ownership is mechanical, not a judgement. `Memory: capsule` and summaries live here |
| **Tag** | `tag_note` / `untag_note` on any note | Additive and reversible; `untag_note` already exists. No note content is at risk |

Out of reach, permanently: creating notes on the user's topics, appending to
user-authored notes, archiving, and anything in `TrashService`. The MCP `ToolDispatcher`
exposes 14 tools; the LLM janitor gets a **subset wrapper**, so an over-eager model
cannot express a forbidden action even if it tries.

**Attribution is mandatory** (locked-in decision #4). Every flag and every tag records
which model made it — `source: "janitor:gpt-5"` or equivalent. A user looking at a tag
six months later must be able to see that a model added it and which one. This also makes
a bad model's output revocable in bulk.

## 5. Cost control — the rule-based janitor becomes the filter

The single most important design decision here: **never send the corpus.**

`Janitor.scan` already produces candidate pairs by token overlap, cheaply and locally.
The LLM adjudicates that shortlist and nothing else. Rules filter, the model judges.

On top of that:

- **Incremental.** Only consider notes changed since the last LLM run. `SyncState`'s
  cursor pattern is the model to copy.
- **Hard caps**, configurable and defaulted low: max notes per run, max tokens per run.
  Refuse to exceed rather than truncating silently.
- **Dry run.** `previewJanitor()` already exists. Extend it so the LLM path shows exactly
  what would be sent and the estimated cost, before anything leaves.
- A visible running spend estimate. This is the user's money.

## 6. Prompt dispatch to other LLMs

`CleanupPrompts`, `copyReviewPrompt` and `copyContextToClipboard` already compose good
prompts. This needs no new prompt subsystem — it needs one more sink.

One `Prompt` value, two transports: `NSPasteboard` (today, no key required) or
`ReasoningProvider` (new). The "Ask an LLM…" and "Resolve with AI…" menus gain a **"Run
it here"** item when a key is configured, and are completely unchanged when one isn't.
Responses return as proposals or derived notes, subject to the same ladder in §4.

This keeps the clipboard path first-class rather than legacy, which matters: it is the
only path that works with a ChatGPT Plus subscription and no API key, and that is a large
fraction of users.

## 7. The App Store consequence — handle it, don't discover it

The shipped macOS description says, verbatim: *"No account, no analytics, no cloud sync,
no bundled model — the reasoning comes from whichever AI tool you connect, and the
optional embedding connection is restricted to localhost."*

Adding an outbound LLM call makes the tail of that sentence false. Required before the
next Mac release:

- Update the description in `APP_STORE_SUBMISSION.md` and App Store Connect. The honest
  replacement keeps the spirit: still no account, still no analytics, still no bundled
  model, still no calmdownoscar server — plus an optional connection *the user configures
  and pays for*, off by default.
- Review the privacy label. The developer collects nothing and the data goes to a
  provider the user chose and contracted with directly, which is a good argument that
  **Data Not Collected** still holds. Get this confirmed rather than assumed, and
  disclose in `PRIVACY.md` and in-app regardless.
- `com.apple.security.network.client` is **already** in `UnliRice.entitlements`, so
  Phase 1 needs no new entitlement and no new review surface beyond the metadata.

## 8. Phasing

**Phase 1 — on demand — built 2026-08-09.**
`ReasoningProvider` + `OpenAICompatibleReasoning`, Keychain storage, consent sheet,
restricted dispatcher, the three-tier ladder, dry run and caps, "Run it here" on the
existing prompt menus, Trust Center outbound log. Key lives only in the main app. No new
entitlement.

Where it lives: `Sources/UnliRiceCore/Reasoning/` (`ReasoningProvider`,
`OpenAICompatibleReasoning`, `ReasoningKeyStore`, `ReasoningAction` +
`RestrictedReasoningDispatcher`, `ReasoningCursor`, `ReasoningRun` + `ReasoningRunner`,
`OutboundCallLog`), `Sources/UnliRice/AppStore+Reasoning.swift` (consent, keychain
plumbing, the on-demand entry points), the "Bring your own LLM" card and consent sheet in
`AutomationView.swift`, "Run it here" in `ContentView.swift`'s `CleanupMenu` /
`AIReviewMenu`, and the outbound-call card in `TrustCenterView.swift`. Tests in
`Tests/UnliRiceCoreTests/Reasoning*Tests.swift` and `OutboundCallLogTests.swift`.

Not yet done, deliberately out of Phase 1's scope as specced: App Store description /
`APP_STORE_SUBMISSION.md` update and privacy-label review (§7) — do this before the next
Mac release, not before this branch merges. `PRIVACY.md` disclosure likewise pending.

**Phase 2 — unattended (deferred, needs a decision).**
Running on the routine tick means the sandboxed `unlirice-agent` helper must read the
key, which requires a shared `keychain-access-groups` entitlement on both binaries plus
App ID configuration — a genuine App Store review surface. Do not start this until
Phase 1 has shown the judgement is worth paying for unattended. It also raises the
consent bar considerably: notes leaving the machine while nobody is present is a
different promise from notes leaving while the user watches.

Note the tension to resolve at that point, rather than pretending it isn't there:
"invisible by default — never build anything that needs the user to show up" argues for
unattended, and the privacy posture argues for on-demand. Phase 1 buys the evidence to
settle it.

**Out of scope:** iOS. Capture is a different app with a different threat model, and
nothing here should ship there without its own pass.
