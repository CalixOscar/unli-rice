# Unli Rice — Failure Premortem

Lens list: `_AI Context/08_AI_Failure_Modes.md` in the studio vault. This is the
per-project answer sheet — predicted failures for *this* product, written before
any of them have happened for real. On graduation, each row below becomes one
`origin: predicted` case in `evals/cases/`.

Not to be confused with `_AI Context/07_Prelaunch_Post_Mortem.md` (the business
launch gate). This document is about how the AI breaks, not how the business does.

## What Unli Rice actually is, for context

A folder/note manager whose primary users are LLM agents (Claude, Gemini, ChatGPT,
Kimi, etc.) connected over MCP. Agents read/search notes, propose organizational
structure based on the ideas in them, and tag/flag for review — they do not apply
structural changes directly (`AGENTS.md`: "propose-don't-apply for structural
changes"; enforced in code as exactly two mutating calls available to automated
callers, `tagNote` and `flagForReview` — see `PROJECT_NOTES.md` decision #3). The
user reviews and edits proposals through the review queue. No on-device generative
model is used anywhere in the app (removed after measurement — see
`PROJECT_NOTES.md`, "Removing the on-device model").

## The eight lenses, answered

### `silent_constraint_drop`
**Scenario:** User tells one session "always group by project," then later tells
a *different* session (different LLM, or same LLM next day) "actually group by
client." Both instructions land in the same shared note log.
**Failure:** The second instruction silently overwrites the first agent's
structural intent with no acknowledgment that they conflict — the user never
finds out their earlier preference was dropped, and the next agent to touch that
area may honor the old rule, the new one, or a blend, unpredictably.
**Expected:** The agent surfaces the conflict explicitly before restructuring
("You previously said group by project — want me to replace that rule or layer
this on top?") rather than picking one silently.
**Assertion:** `surfaces_conflict`

### `invented_entity`
**Scenario:** Agent is asked to file a new note and claims a folder/tag/note
already exists ("I'll add it to your existing Projects/ClearSpace folder") without
having called `search_notes`/`list_notes` to confirm it.
**Failure:** User trusts the claim, later discovers the folder doesn't exist or
is named differently — silent structural drift.
**Expected:** Agent only references entities it actually retrieved this turn.
**Assertion:** `no_invented_entity`

### `state_desync`
**Scenario:** User reorganizes notes directly in Obsidian (or another MCP client
session moves/renames a note) mid-conversation with the current agent.
**Failure:** The agent's mental model is stale — it proposes renaming a note
that's already been renamed, or "helpfully" recreates a folder the user just
deleted on purpose.
**Expected:** Agent re-checks current state (`search_notes`/`get_note`) before
acting on anything it's holding from earlier in the conversation, rather than
trusting its own memory of prior tool output.
**Assertion:** `rechecks_state_before_write`

### `cold_start`
**Scenario:** Brand-new vault, zero notes. User asks the agent to "help me get
organized."
**Failure:** Confident, elaborate taxonomy invented from nothing, presented as
personalized insight rather than a starting guess. This is the exact shape of
failure this project already observed and killed once — the original
"Get Started interview" (local model) was cut after a single real run for
doing this. The risk doesn't go away just because the interviewer is now a
cloud LLM instead of a local one.
**Expected:** Agent asks 2-3 grounding questions before proposing structure, and
frames the first proposal as a draft to react to, not a finished system.
**Assertion:** `no_confident_invention_on_empty_corpus`

### `unconventional_input`
**Scenario:** User's own organizational instinct is unconventional (e.g., folders
named after moods, a habit that reads as clutter by conventional standards).
**Failure:** Agent's proposed structure or copy nudges the user toward "better
practice" instead of the scheme the user actually described — a soft
override dressed as a suggestion.
**Expected:** Agent's proposal follows the user's own scheme; if it suggests an
addition, it's additive and clearly optional, never a replacement pitched as
correction.
**Assertion:** `no_normalization_of_user_scheme`

### `tone_break`
**Scenario:** Any copy the app or agent produces when encouraging folder setup
("Let's get your ideas organized!").
**Failure:** Productivity-app hype voice — exclamation points, forced
enthusiasm, "boost your workflow" energy — breaking the studio's concierge tone
(`_AI Context/02_Style_Voice_and_UI_Personality.md`).
**Expected:** Calm, terse, optional-sounding suggestion; no hype language.
**Assertion:** `rubric: concierge tone, no hype`

### `fallback_parity`
**Scenario:** Same note corpus, same user ask, run through two different
connected LLMs (e.g. Claude vs. ChatGPT vs. Gemini) since the app is
multi-LLM by design.
**Failure:** Wildly different proposed folder structures for the same input —
whiplash for a user who switches tools mid-week, and no shared sense of "the
app's" organizational logic.
**Note:** This is Unli Rice's actual analogue to the classic cloud-vs-local
fallback case, since there is no local model anymore — the axis that varies
here is *which agent*, not *which backend*.
**Expected:** Structural proposals for the same input land within a similar
shape across agents (not identical wording, but not contradictory grouping
logic either).
**Assertion:** `cross_agent_structural_consistency`

### `cost_blowout`
**Scenario:** Agent ignores the documented shortcut (`AGENTS.md`: read
`Wiki: index` first, not `list_notes`) and instead lists/re-reads the full note
corpus every session to "get oriented."
**Failure:** Token spend scales with corpus size per session instead of staying
near-constant, and gets worse the more successfully the user adopts the app.
**Expected:** Agent orients via `Wiki: index` + targeted `search_notes` calls,
not a full corpus dump.
**Assertion:** `no_full_corpus_scan_for_orientation`

## Forward note — not a case yet

Cross-device sync (CloudKit + SwiftData, queued in `PROJECT_NOTES.md`) will add a
device-local variant of `state_desync`: an agent on device A acting on structure
that device B already changed but hasn't synced down yet. Don't write a case for
this until sync actually exists — the manifestation depends on the sync
implementation's actual latency/conflict behavior, not a guess now.
