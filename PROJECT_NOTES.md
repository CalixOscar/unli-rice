# Unli Rice — Project Notes

Living status doc. **Read this first** if you're picking this project up in a
new session, on a different machine, or with a different tool (Claude, Codex,
whatever). Keep it current as you work — don't let it drift from what's
actually in the repo.

If you're an agent about to *use* the `unlirice` MCP tools (not just read
about the architecture), read `AGENTS.md` too — it has the actual behavioral
conventions (title discipline, tagging, when to flag vs. resolve) for keeping
multi-agent notes coherent.

## What this is

A persistent memory layer whose primary users are autonomous LLM agents
(Claude, coding assistants, local daemons), not humans directly. Multiple
different LLMs (Claude, Gemini, ChatGPT, Kimi, etc.) may all read and write
into the same project's notes concurrently via a local MCP server.

Full original design discussion (CloudKit/SwiftData sync, local MLX janitor
model, storage footprint targets, etc.) is summarized in this repo's git
history / the chat that produced it — the durable architectural decisions
that came out of it are captured below.

## The rename (Second Brain → Unli Rice)

The app is **Unli Rice**. The old name is gone from the code: module
`UnliRiceCore`, executable `unlirice-mcp`, MCP server key `unlirice`, env
override `UNLIRICE_DATA_PATH`.

The one place it survives on purpose is `DataLocation.legacyDirectoryName`.
The event log moved from `~/Library/Application Support/SecondBrain/` to
`.../Unli Rice/`, and `DataLocation` **copies** the old log across on first run
if the new one doesn't exist. Copies, not moves: this codebase destroys no note
history (decision #2), and a rename is not an exception to that. Worst case the
user keeps a stale copy; the failure mode of a move is losing the only copy of
the log. Verified on the real 150-event file — byte-identical at the new path,
original untouched.

## Locked-in architecture decisions (do not violate these)

1. **The event log is append-only and is the source of truth.** Notes are
   never edited or deleted in place. Every change from any agent is a new
   `Event` appended to a JSON-Lines file. Current note state (`Note`) is
   always a *projection* rebuilt from the full event history — throwaway and
   deterministic, not authoritative itself.

2. **No destructive delete exists anywhere in the codebase, on purpose.**
   `NoteService` has no delete method, and no MCP tool maps to one. The
   closest thing is `archive_note`, which is soft and fully reversible via
   `unarchive_note`. This was a direct response to the risk that a local
   janitor model (MLX, or a careless agent) could otherwise silently destroy
   a note that mattered. If a future feature needs real deletion (e.g. a
   time-based purge of old archives), it must be a human-triggered action,
   never something an agent or the janitor can invoke autonomously.

3. **Structural changes (merge, dedupe, "these two notes conflict") are only
   ever proposed, never applied by an agent.** The `flag_for_review` /
   `resolve_review` / `pending_reviews` tools exist specifically so an agent
   can raise a concern without acting on it. Resolving a flag is meant to
   happen after a human decides — there's no UI for that yet (see Deferred).

4. **Every write records which agent made it** (`source` field, e.g.
   `"claude"`, `"gemini"`). This is how multi-LLM concurrent writes stay
   attributable and how future conflict-detection (a janitor comparing what
   different agents wrote) will work.

## What's actually built (MVP, this session)

Swift Package (`swift build` / `swift test`, macOS 13+, Swift 5.10 tools).

- `Sources/UnliRiceCore/` — the engine, has no I/O dependencies beyond the
  filesystem:
  - `Event.swift` — the event model (see decision #1). No `.deleted` kind.
  - `Note.swift` — the read-side projection + `ReviewFlag`.
  - `EventStore.swift` — append-only JSON-Lines file store. `append()` and
    `readAll()` are the only operations.
  - `Projector.swift` — pure function: `[Event] -> [UUID: Note]`.
  - `NoteService.swift` — the only API anything should use to touch notes
    (create/append/tag/untag/archive/unarchive/flag/resolve/search/list/
    transaction log). This is the safety boundary — if you're tempted to
    write directly to `EventStore` from outside this file, don't.

- `Sources/unlirice-mcp/` — an executable exposing `NoteService` over MCP:
  - Hand-rolled JSON-RPC 2.0 over stdio (one JSON object per line, both
    directions) — **not** using the official Swift MCP SDK yet, see Deferred.
  - Implements `initialize`, `notifications/initialized`, `tools/list`,
    `tools/call`, `ping`.
  - `ToolCatalog.swift` — the 13 tools exposed, 1:1 with `NoteService`
    methods. If you add a `NoteService` method, add a matching tool here and
    in `ToolDispatcher.swift` or it won't be reachable by agents.
  - Data file location: `~/Library/Application Support/Unli Rice/events.jsonl`
    by default, overridable via `UNLIRICE_DATA_PATH` env var (used for
    tests/smoke runs so they don't touch real data).

- `Tests/UnliRiceCoreTests/NoteServiceTests.swift` — 16 tests, all passing
  (plus 4 in `ExportServiceTests.swift`, 20 total). Covers: create/get,
  multi-agent append history preservation, tag/untag, archive is
  soft+reversible, archiving never removes underlying history, flag/resolve
  review, search, not-found error, event log survives reopen + reprojects
  identically (the "new device replays the log" scenario in miniature), and
  wiki-link resolution — forward references, bidirectional backlinks, raw-UUID
  targets, dangling links, malformed `[[` syntax, and links updating on append.

- Manually smoke-tested the actual `unlirice-mcp` binary over stdio
  end-to-end (initialize → tools/list → tools/call create_note) — worked.

**Status: builds clean, tests pass, MVP is functionally real** — not a stub.
It's a working local memory store with a real MCP surface. What it is *not*
yet: synced, backed by a real LLM, or reachable from any actual MCP client
config (see Deferred).

## How to build / run / test

```sh
swift build
swift test
swift run unlirice-mcp   # starts the MCP stdio server, logs to stderr
```

**Anything that uses MLX must be built by xcodebuild, not SwiftPM.** `swift
build` cannot compile Metal shaders — a plain `swift run` builds fine and then
dies at runtime with "Failed to load the default metallib". This is a
documented mlx-swift limitation, not a problem with this package. Use the
wrapper:

```sh
Scripts/mlx-run UnliRice            # the GUI, with the local model available
Scripts/mlx-run janitor-calibrate   # the dry-run tool, see "Calibration" below
```

Everything that does *not* touch MLX — `UnliRiceCore`, `unlirice-mcp`, and the
whole test suite — still builds and runs under plain SwiftPM. Keeping that true
is exactly why `UnliRiceMLX` is a separate target: the safety-critical code
stays buildable and testable on a machine with no model at all.

To point a real MCP client (Claude Code, Claude Desktop, etc.) at it, add an
entry to that client's MCP server config pointing at the built binary, e.g.
`.build/debug/unlirice-mcp` (or `swift run unlirice-mcp` as the
command). **Not yet done in this session** — nothing is registered with any
client config.

## MCP client registration (done)

- **Claude Code**: project-scoped `.mcp.json` at the repo root points at
  `swift run --package-path <this dir> --quiet unlirice-mcp`. Takes effect
  next time a Claude Code session starts in this project folder — this
  session couldn't hot-load it into itself.
- **Claude Desktop**: an entry was added here in an earlier session, but as of
  the rename session the config contains only `Roblox_Studio` — whatever was
  added is gone. Re-add it if you want Claude Desktop to see the notes.
- Both configs were smoke-tested by running the exact configured command
  and sending a raw `initialize` request — responded correctly.
- Data file is the shared default (`~/Library/Application Support/Unli
  Rice/events.jsonl` unless `UNLIRICE_DATA_PATH` is set), so every client
  reads and writes the same underlying notes.

## GUI: closing the capture loop (this session)

An audit of the real event log found 148 events / 48 notes, every single one
with `source: "claude"`, all written in one 15-minute burst — zero human-
authored notes, and zero `appended`/`archived`/`flagged` events ever. The
cause wasn't discipline, it was a gap in `Sources/UnliRice/`: the GUI added in
commit 65228c5 could create a note *title* but had no way to capture, read, or
add to a note's *body* — `NewNoteRow` collected only a title,
`AppStore.createNote` hardcoded `body: ""`, and `note.body` was never rendered
anywhere. `NoteService` already supported the full lifecycle; the GUI reached
maybe a third of it. This session closes that gap:

- `NewNoteRow` now captures a body (multi-line, ⌘⏎ to save).
- New `NoteDetailView` — the first place a note's full body is readable.
  Replaces the list view rather than splitting the column with it (one thing
  on screen at a time). Shows tags (with add/remove), sources, timestamps,
  any unresolved review flags (reusing `ReviewQueueRow`), resolved wiki-links
  and dangling ones, backlinks, and an "add to this note" field wired to
  `appendToNote` — previously unreachable from the GUI entirely.
  `AppStore.append/addTag/removeTag/archive/unarchive` wire these through to
  the matching already-existing `NoteService` methods.
- Sidebar gained a working **Archived** row (`listNotes(includeArchived:)`
  was implemented but nothing in the GUI ever passed `true`).
- **Wiki-links**: `Sources/UnliRiceCore/WikiLink.swift` parses `[[Target]]`
  spans out of body text. `Projector.project` resolves them in a second pass
  after the main event-replay loop (a note can link to one created *later* in
  the log, so resolution can't happen inline). Targets match either a note
  title, case-insensitively, or a raw UUID. Title matching is safe here
  specifically because there's no `retitled` event kind — titles are fixed at
  creation, so a link can't silently go stale. Nothing is written to the
  event log; `outboundLinks`/`backlinks`/`danglingLinks` are pure derived
  `Note` fields, rebuilt on every projection, consistent with decision #1.

Net effect: the GUI and the MCP server are now full peers over the same
`NoteService` — `source: "human"` vs `source: "claude"` finally means
something, since a human can actually write and revisit a note.

## The janitor (this session)

The janitor's *role* and its whole permission boundary are now built and
tested in `Sources/UnliRiceCore/Janitor/`. What is deliberately not built
is the MLX model — and the point of this session's split is that none of the
safety-critical design was waiting on it.

**The role, in one sentence: the janitor notices things and is trusted to
tidy, never to decide.**

Concretely it has exactly two output channels and no third:

- **Cosmetic** conclusions auto-apply. Only one qualifies today: adding a tag
  that is already established elsewhere in the corpus *and* appears verbatim
  in the note's own text. Reversible with an existing tool, one note affected,
  meaning unchanged.
- **Structural** conclusions (duplicate, mistyped link, orphan) only ever
  reach a human through `flagForReview`. This is decision #3, enforced.

The boundary is enforced by *type*, not by discipline: `JanitorProposalKind`
has no case for archiving, untagging, retitling, resolving a flag, or
rewriting a body, so "the janitor archived my note" is a sentence that cannot
be expressed. `JanitorRunner` is the only component that writes and calls
exactly two write methods — `tagNote` and `flagForReview`. A test asserts that
the set of event kinds the janitor produces is a subset of `{tagged, flagged}`;
that test is the one to keep honest if the rules ever grow.

Structure:

- `Janitor.scan` is a pure function `[Note] -> [JanitorProposal]`. It holds no
  service and opens no file, so a rule cannot quietly acquire the ability to
  write.
- `JanitorRunner` acts on proposals, and is where every safety check lives.
- `SimilarityProvider` is the seam the MLX embedding model plugs into. The
  default `TokenOverlapSimilarity` is deliberately crude Jaccard-over-tokens.
  Missing a duplicate costs nothing (the queue stays quiet); a false positive
  costs the user's attention. That asymmetry is why shipping a dumb default is
  safe, and why embeddings change *which pairs surface*, never what the
  janitor may do with them.
- Autonomy (Eco/Balanced/Aggressive) maps 1:1 onto the existing GUI slider's
  persisted raw values — **don't renumber them.** The levels vary how much the
  janitor notices; no level grants auto-apply of anything structural.

### Two things the real event log taught us

Dry-running the rules over the actual 48-note log (against a copy) caught two
over-eagerness bugs before any of this could run unattended:

1. It wanted to tag 64 of 48 notes `memory` — in a corpus *about* memory, that
   word is everywhere. A tag that matches almost everything is wallpaper, not
   a filter. Hence `maximumTagSaturation` (40%), which behaves as a fixed
   point: as the janitor tags, usage rises, and the tag stops being proposed.
   It only applies above a corpus size of 10, since in a three-note corpus
   every tag looks saturated.
2. A first run would have queued 18 flags at Balanced and 66 at Aggressive.
   Burying the review queue is the fastest way to teach someone to ignore it.
   Hence per-run `cosmeticBudget`/`structuralBudget`, spent highest-confidence
   first, with leftovers deferred to the next run rather than dropped.

Simulated over the real corpus, repeated Balanced runs converge at round 5
(38 tags applied, 18 flags queued) instead of creeping toward tagging
everything.

### Idempotence, and deferring to the human

A janitor that re-proposes a rejected merge every scan is worse than one that
never ran. Two mechanisms:

- Each proposal has a stable `fingerprint`, stamped into the flag reason as
  `[janitor:...]`. A later scan skips anything already stamped — **including
  flags the human already resolved**, so "no" means no.
- Before re-adding a tag, the runner reads the raw event log for any
  `untagged` event by a non-janitor source. The projection only knows the
  *current* tag set; the fact that a human once removed a tag survives nowhere
  else, and it's exactly the signal needed to stop the janitor arguing with
  its user.

Archived notes are out of scope entirely — archiving is how a human says stop
showing me this, and a janitor mining archives for proposals would quietly
undo that.

### Wired up (rename/MLX session)

The janitor now runs — **by hand only**. `JanitorControls` in `ContentView`
offers "Preview" and "Run now", backed by `AppStore+Janitor.swift`. Preview is
listed first and styled as the primary action deliberately: the janitor's
contract is that you can always see what it would do before it does anything,
and a UI where "Run" is the obvious button quietly weakens that.

The panel also states which similarity engine produced the proposals, since
that changes what gets noticed and a user reading a list deserves to know.

Still no scheduler and no idle/on-power trigger — nothing runs unattended, and
nothing runs at launch. That remains deferred (#5 below).

## The MLX model (rename/MLX session)

`Sources/UnliRiceMLX/MLXSimilarity.swift` conforms an on-device MLX embedding
model (`bge-micro`, ~17M params) to the `SimilarityProvider` seam that was left
for it. It is a separate SPM target so that the core, the MCP server and the
whole test suite never pull MLX in — `swift test` stays fast and the
safety-critical code still builds on a machine with no model.

**Nothing about the janitor's permissions changed, and that was the point.**
Embeddings decide which pairs get *noticed*; a duplicate found by a model still
goes to the review queue as a proposal, exactly like one found by token
overlap. `JanitorRunner` still calls only `tagNote` and `flagForReview`.

Two things worth knowing before touching this:

- **`similarity` is synchronous and the scan is a pure function** — both
  load-bearing. Rather than make the whole scan async for MLX's sake,
  `MLXSimilarity.warm(_:)` embeds every title up front and `similarity` reads
  from a cache. That works because the janitor only ever compares note
  *titles*, all of which are known before a scan starts. A cache miss falls
  back to token overlap rather than returning 0 — answering "not similar" would
  dress a miss up as a judgement.
- **Thresholds now travel with the provider** (`SimilarityCalibration`), because
  the two engines' 0...1 scales mean nothing alike. See below.

### Calibration, and why it's a checked-in tool

`swift run janitor-calibrate` (or `Scripts/mlx-run janitor-calibrate` for the
MLX half) dry-runs the rules over a *copy* of the real log and reports the score
distribution and what each autonomy level would propose. It writes nothing and
calls only `preview`.

It exists because the thresholds are not guessable. Over the real 49-note
corpus, the median cosine between two **unrelated** titles is **0.82** — they're
all short English-ish strings and the model says so. All the signal is in the
last two percent:

    >= 0.90 : 136 pairs      >= 0.97 :  17 pairs
    >= 0.96 :  36 pairs      >= 0.985:   8 pairs

An intuitive-looking 0.92 would have queued 78 proposals where token overlap
queues 18. The shipped numbers (0.985 default / 0.97 aggressive) land at 8 and
17 — comparable to token overlap's 18/66 but on better pairs. Re-run this tool
as the corpus grows; the right answer moves.

## Review queue clustering (rename/MLX session)

Running the janitor against the real 49-note corpus surfaced a UX problem the
design hadn't anticipated: a pile of five near-identical `clearspace-session-
log` notes produced five separate duplicate flags (one per pair sharing a
newer note), asking "is A a duplicate of B?" five times about what is really
one decision. `Sources/UnliRiceCore/Janitor/ReviewCluster.swift` groups
mutually-duplicate flags into one `ReviewCluster` via union-find over the
`[janitor:dup/<uuid>/<uuid>]` fingerprint pairs; `AppStore.resolve(cluster:
outcome:)` still calls `resolveReview` once per underlying flag, so the event
log ends up identical to clicking each one — this is a presentation change,
not a permission change.

The subtle bug worth remembering if this file is touched again: a duplicate
flag is written to only the *newer* note in a pair (`Janitor.
duplicateProposals`), so the *oldest* note in a chain of five carries no flag
of its own and never appears in `pendingReviews()`. Naively building clusters
from `pending` alone silently drops it from the group. `ReviewQueue.cluster`
takes a `resolveNote: (UUID) -> Note?` closure specifically so it can look up
every note named by a fingerprint, not just the ones with a flag attached —
in the GUI this is `AppStore.note(id:)`, which already resolves against the
full `noteIndex`, not just the pending subset.

Also fixed in the same pass: `ReviewQueueRow`'s single `Text("\(title):
\(reason)")` line was being visually collapsed to one truncated line by
SwiftUI inside the panel's nested flexible `VStack`s — a `.fixedSize(horizontal:
false, vertical: true)` on the `Text` was the actual fix; without it SwiftUI is
free to compress wrapped text down to its single-line intrinsic size in that
context instead of wrapping.

### Accept/Reject actually doing something (rename/MLX session, later pass)

A user testing the real app asked how to explain the review queue to someone
non-technical, which surfaced a sharper problem than wording: **Accept and
Reject did the exact same thing to a note's data — nothing.** Both just call
`resolveReview`, which only flips one `ReviewFlag.resolved` bool (see
`Projector.swift`'s `.reviewResolved` case); nothing merges, nothing archives.
They differed only in one word buried in the event log for later auditing. A
friendlier label on a button that still does nothing would have made this
*more* confusing, not less — someone pressing "Accept" on "these look like
duplicates" reasonably expects the duplicates to get cleaned up.

`NoteService.consolidateDuplicates(keeping:archiving:resolving:source:)` is the
real fix, and it's exactly the human-decides action decision #3 named as
deferred ("resolving a flag is meant to happen after a human decides — there's
no UI for that yet"). It's composed entirely from the three existing
primitives — `appendToNote` (once per other note, so nothing is lost),
`archiveNote` (soft, reversible — decision #2, never a delete), `resolveReview`
(clears every flag in the group) — so it doesn't grant any new capability, it
just sequences ones that already existed. **Never called by `JanitorRunner` or
any agent** — `JanitorRunner` still only calls `tagNote` and `flagForReview`;
this is reachable only from the GUI, one press of "Keep this one" on one
specific note in a `ReviewClusterCard`. `ConsolidateDuplicatesTests.swift`
pins this down, including a test that the janitor never touches it.

The review-queue UI changed to match: each note in a duplicate cluster gets its
own "Keep this one" button (and is tappable to open and actually read it
first, which it wasn't before), replacing one generic Accept/Reject pair that
implied a decision without being able to act on it. Non-duplicate flags
(orphan, mistyped link) don't have a "keeper" concept, so their two buttons
stayed dismiss-only — but relabeled honestly ("Got it, I'll take care of it" /
"Not important, dismiss") instead of "Accept"/"Reject," which implied
something happened when nothing did. Rationale text throughout (`JanitorProposal.rationale`,
`ReviewCluster.summary`) was also rewritten to drop technical vocabulary —
`[[wiki-link]]` syntax, "forward reference," "title overlap" — in favor of
plain sentences a non-technical reader can act on without translation.

### Review queue moved to the main column (same session, later pass)

The review cards used to render inside `AutonomyPanel`, the fixed 260pt
right-hand column shared with the autonomy slider. Once cards started needing
a full note title *and* a "Keep this one" button on the same line, that width
wasn't enough — the button label itself was being truncated ("Keep this o…"),
not just the title. `ReviewQueueView` is a new full-width view in the main
column (same slot `AssistantView` and the note list use), toggled by
`AppStore.showingReviewQueue` alongside the existing `showingArchived`/
`showingAssistant` flags — all three, plus note selection, stay mutually
exclusive the same way they already did. `AutonomyPanel` keeps only what
actually fits a narrow column: the slider, Preview/Run now, and a one-line
"N pending →" pointer that jumps to the real view. `showWaiting()` (which used
to fake this by showing zero notes with a status caption) is gone — both the
sidebar's "Review Queue" row and the "What's waiting on me?" prompt chip now
call `showReviewQueue()` directly.

## Draft-time suggestions (same session, later pass)

`Janitor` only ever looks at notes *after* they're saved — which means the
five-note `clearspace-session-log` pile that started this whole thread of work
was never actually preventable by anything in this app, only cleanable up
afterward. `Sources/UnliRiceCore/Janitor/DraftAdvisor.swift` runs the same
rules *before* a note is written: `DraftAdvisor.suggestions(forTitle:body:
existing:config:similarity:)` is a pure, synchronous function over a draft
title/body and the existing corpus, returning up to three things —

- **A possible duplicate** — same threshold `Janitor`'s own duplicate rule
  uses (`config.duplicateThreshold(similarity.calibration)`), just checked
  against a draft instead of two saved notes. `NewNoteRow` offers "Add to that
  note instead" right next to it, which skips creating a new note entirely and
  calls `AppStore.appendDraft(_:toExisting:)`.
- **Suggested tags** — the exact same rule as `Janitor.scan`'s cosmetic pass,
  factored out as `Janitor.establishedTags(_:config:)` so the two call sites
  (after-save scan, before-save draft) can't quietly drift apart. Never
  invents a tag; only reuses one the corpus already agreed on.
- **Related notes** — a new, deliberately *lower* bar than the duplicate
  threshold (`SimilarityCalibration.relatednessThreshold`: 0.35 token-overlap,
  0.90 MLX — the next real inflection point below the duplicate bar in the
  calibration table, not a rounding of it). "Related" and "the same thing" are
  different questions, so they get different numbers. Accepting one appends a
  `[[Title]]` line to the draft before it's ever saved.

Deliberately uses `TokenOverlapSimilarity`, not whichever engine the janitor
panel has loaded — this runs on every keystroke in `NewNoteRow`, and a
note-taking flow should never stall on a model load just to type a title. The
MLX embedding model stays exactly what it was: something `Preview`/`Run now`
loads on demand for the background scan, not something typing triggers.

Every suggestion is a tappable chip, **defaulted off** — nothing is
pre-selected, including tags (unlike the janitor's own cosmetic auto-apply,
which is a *human* pressing a button in `NewNoteRow`, not the janitor acting
unattended, so it doesn't inherit that permission). `NewNoteRow.add()`
intersects the selected set against the *current* suggestions before applying
them, specifically so that editing the text after selecting a tag — which can
make that tag stop being suggested — can't leave a stale selection silently
attached to the saved note with no chip ever having shown it.

**Deferred, not started:** the user asked for "some kind of animation to view
the brain" once the rest of this is done — a visual/graph view of the note
corpus. Noted here so it survives a session boundary; nothing built yet.

## Onboarding (rename/MLX session)

A structural cold-start problem, not just a missing tutorial: the tag rule
(`Janitor.cosmeticTagProposals`) only proposes a tag once it's already used on
`minimumTagCorpusUse` (2 at Eco/Balanced) *other* notes. A brand-new corpus has
zero tags, so the janitor proposes nothing — forever, no matter how much the
user writes — until a human manually tags two notes with the same word by
hand, which nothing in the UI ever explains.

`Sources/UnliRiceCore/Onboarding.swift` fixes this the same way Notes.app or
Obsidian ship a first note: `AppStore.init()` seeds two short notes ("Welcome
to Unli Rice", "How tags and the janitor work") on a genuinely empty,
never-before-seeded corpus, both tagged `"guide"` — exactly hitting the
threshold the janitor needs, so it has something to demonstrate on from the
very first real note the user writes that happens to mention "guide" or any
tag they've since established. `source: "unlirice"` marks them as the app's
own voice, distinct from `"human"` and any agent.

Deliberately scoped to the GUI only (`AppStore.init`, not `unlirice-mcp`): an
agent connecting over MCP before any human has ever opened the window should
never find two notes it didn't write. A `UserDefaults` flag makes it one-time —
a user who archives both notes doesn't get them silently reinjected on the
next launch.

## The chat panel (rename/MLX session)

A second, independent MLX seam: `Sources/UnliRiceMLX/JanitorChat.swift` wraps
a small local instruct model (`mlx-community/Qwen3-1.7B-4bit`) behind one
method, `ask(_ prompt: String) async throws -> String`. That signature is the
whole safety argument — there is no tool-calling loop and no function-calling
schema, so there is no path from a model's output to a write. The chat panel
(`AssistantView` in `ContentView.swift`) renders whatever comes back as plain
text; every structural action is still, and can only ever be, a human pressing
Accept/Reject on a `ReviewCluster`. This mirrors `Janitor.scan` holding no
`NoteService` (decision #3) — the type that thinks is kept structurally
separate from the type that's allowed to write.

Two features, both advisory:

- **Free-form Q&A** (sidebar → Assistant) — `ChatContext.questionPrompt`
  builds a bounded snapshot (last 20 live notes, truncated bodies, the pending
  review queue) plus the last 4 turns of conversation, and folds it into one
  prompt string.
- **Per-cluster recommendation** — a button on any duplicate `ReviewCluster`
  card asks "which of these looks like the keeper?" with the full (bounded)
  bodies of just that cluster's notes. Still just text on the card; Accept/
  Reject is unaffected.

Worth knowing if this is touched again:

- **No conversation state is kept in the model between calls, on purpose.**
  `ChatSession.respond(to:)` in mlx-swift-examples replaces its entire message
  list on every call, which silently drops any `instructions:` passed at
  construction the moment the first turn happens — confirmed by reading
  `MLXLMCommon/Streamlined.swift`, not assumed. Rather than depend on that (or
  on a KV-cache-continuation code path whose exact semantics could change
  between library versions), every `JanitorChat.ask` call gets a fresh
  `ChatSession`, and the caller (`ChatContext`) is responsible for folding all
  needed context and history directly into the prompt text. Slower per turn,
  correct regardless of the library's internals.
- **The model class itself is the one PROJECT_NOTES already flagged as
  unreliable.** The janitor's similarity work concluded 1–3B generative models
  are unreliable for nuanced cross-time concept matching — Qwen3-1.7B is
  exactly that size, chosen for local/offline operation over the quality an API
  model would give. `ChatContext.preamble`, prepended to every prompt, states
  the model's actual authority (none) in plain language; the panel's own
  caption states the tradeoff rather than presenting answers as authoritative.
  An API-backed alternative was considered and explicitly not built — it would
  send note content off-device, a real change in posture for an app whose
  whole pitch is local memory.

## Deferred / explicitly not done yet, in rough priority order

1. ~~Register the server with an actual MCP client~~ — done, see above.
   Still TODO: actually drive it from within a live Claude Code/Desktop
   session (ask it to create/search notes in conversation) to confirm the
   full loop works, not just the raw protocol handshake.
2. **Swap the hand-rolled JSON-RPC layer for the official MCP Swift SDK**,
   once dependency resolution is confirmed reliable — hand-rolled was chosen
   for this MVP to avoid dependency-resolution risk while getting something
   real and testable quickly.
3. ~~Review-queue UI~~ — done. `AutonomyPanel` / `ReviewQueueRow` in
   `ContentView.swift` render pending flags with working Accept/Reject wired
   to `resolveReview`, and (this session) the same row now also appears
   inline on `NoteDetailView` for that note's own flags. This item went
   stale in the doc after commit 65228c5 shipped it — a reminder to keep this
   file honest as work lands, not just when a session starts.
4. **CloudKit + SwiftData sync layer.** Needs Xcode + an Apple Developer
   account + iCloud container entitlement — can't be scaffolded headlessly.
   When picked up, the event log format here (`Event`, JSON-Lines) is meant
   to map directly onto SwiftData records; the append-only design was chosen
   specifically so CloudKit sync conflict resolution stays simple (new
   records only, no in-place record mutation to reconcile).
5. **Local MLX janitor.** ~~The embedding model~~ — done, see "The MLX model"
   above. What's left:
   - **Scheduling/triggering** — the janitor runs from a button and nothing
     else. An idle + on-power trigger is still unbuilt, and is the remaining
     half of the Eco level's "only while plugged in and idle" promise.
   - **Generative TL;DRs** — the one planned cosmetic action still missing.
     If added, it must stay cosmetic (append-only, one note, no meaning
     change) or it becomes a `flagForReview` instead.
6. ~~**Battery/aggressiveness settings**~~ — the three levels exist as
   `JanitorAutonomy`/`JanitorConfig` and are honoured by the rules. Still
   missing the *battery* half: Eco is documented as "only while plugged in
   and idle", which is a scheduling concern and lands with the trigger work
   in #5.
7. **Real search.** `search_notes` is currently plain case-insensitive
   substring matching over title/body/tags. No embeddings/vector search yet
   — intentionally deferred until the embedding model (#5) exists.
8. **Performance**: `NoteService` reprojects the *entire* event log on every
   read call. Fine at current/expected MVP scale (small file, single user's
   projects); will need an in-memory cache + incremental projection before
   this could handle years of heavy multi-agent use. Not a problem yet, flag
   it if the event log grows large and things get slow.

## Repo/environment notes

- Git repo is scoped to this project folder only (`Documents/Projects/Second
  brain`). The user's home directory (`~`) separately has an unrelated, empty
  git repo at `~/.git` — not connected to this project, left untouched,
  don't let the two get confused.
- No remote configured yet. No commits pushed anywhere.
