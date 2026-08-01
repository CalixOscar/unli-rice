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

   That carve-out has since been used exactly once: `TrashService` (see "The
   200-note pass" below). It is deliberately *not* part of `NoteService`, which
   is what keeps it unreachable from the MCP tool catalog — an agent cannot
   express it. The rest of this decision stands unchanged: nothing an agent or
   a routine can call deletes anything.

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
  - `ToolCatalog.swift` — the 14 tools exposed, 1:1 with `NoteService`
    methods. If you add a `NoteService` method, add a matching tool here and
    in `ToolDispatcher.swift` or it won't be reachable by agents.
  - Data file location: `~/Library/Application Support/Unli Rice/events.jsonl`
    by default, overridable via `UNLIRICE_DATA_PATH` env var (used for
    tests/smoke runs so they don't touch real data).

- `Tests/UnliRiceCoreTests/NoteServiceTests.swift` — 17 tests, all passing
  (**188 in the suite overall** as of this session). Covers: create/get,
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

**Everything builds and runs under plain SwiftPM. There are no external
dependencies.**

```sh
swift build
swift test
swift run unlirice-mcp        # the MCP stdio server, logs to stderr
swift run UnliRice            # the GUI
swift run unlirice-agent      # one unattended tick, then exits
swift run janitor-calibrate   # the dry-run threshold tool, see "Calibration"

./Scripts/make-app.sh         # dist/Unli Rice.app — double-clickable
```

`unlirice-agent --status` reports whether the background job is installed;
`--install` / `--uninstall` manage it without the GUI.

Two env overrides, both for staying off real data: `UNLIRICE_DATA_PATH` (the
event log) and `UNLIRICE_AGENT_SETTINGS` (the background agent's settings file,
so routines can be smoke-run without switching them on for real).

This used to be far more complicated: MLX forced `xcodebuild` (SwiftPM cannot
compile Metal shaders, so `swift run` died at runtime with "Failed to load the
default metallib"), which needed a `Scripts/mlx-run` wrapper, and pushed the
whole package's floor to macOS 14. All of that is gone with the model — see
"Removing the on-device model" below. `Scripts/mlx-run` is deleted; if you find
a reference to it anywhere, it's stale.

To point a real MCP client (Claude Code, Claude Desktop, etc.) at it, add an
entry to that client's MCP server config pointing at the built binary, e.g.
`.build/debug/unlirice-mcp` (or `swift run unlirice-mcp` as the
command). **Not yet done in this session** — nothing is registered with any
client config.

## MCP client registration (done)

- **Google Antigravity**: project-scoped `.agents/mcp_config.json` at the repo root points to the Swift PM stdio command. Takes effect on session initialization.
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

## The MLX model (rename/MLX session) — REMOVED, kept for the reasoning

> **This code no longer exists.** `UnliRiceMLX` was deleted once measured; see
> "Removing the on-device model" below for the numbers. The section is kept
> because the *calibration* lessons in it still govern `RemoteSimilarity`, and
> because the reasoning about why thresholds travel with a provider is still
> load-bearing.

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

**Completed (this session):** Added an interactive 2D graph/constellation view of the note corpus (Note Graph View) styled with liquid glass 3D spheres, glowing edge lines, zoom/pan gestures, legends, and a detail inspector.

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

### Get Started: Autopilot (this session)

The seeded guides above solve the janitor's cold start, not the user's. Someone
opening this app with zero notes has nothing connected to it, and the whole
pitch is "memory your AI tools share." `Sources/UnliRiceCore/Autopilot.swift`,
`Sources/UnliRiceCore/MCP/`, `AppStore+Autopilot.swift` and
`GetStartedWizardView` are the fix.

**The first version of this used the local model to interview the user, and it
was cut after one real run.** Qwen3-1.7B was asked to run a four-topic
conversation (project, stack, tool, conventions) and emit `===FINISHED===` when
done. On the first genuine test it emitted the marker after a single answer,
producing a setup prompt with no stack, no tool and no conventions in it. That
is not a prompt to iterate on — it is the third time this file has recorded the
same conclusion about 1–3B models, after the similarity work and after the chat
panel needed two independent workarounds. **Nothing in Get Started calls a model
now.** Every step is deterministic, instant, and unit-tested.

Three things the deleted version got wrong are worth remembering, because they
are the kind of mistake that looks reasonable while you're making it:

1. **A silent fallback made success and failure indistinguishable.** The
   interview's `catch` generated the artifact anyway, so a model that never
   loaded produced the same screen as one that finished properly — and left no
   log either way. Debugging the real run meant checking a model cache
   timestamp to infer what had happened.
2. **UI framing text leaked into the deliverable.** The opening question
   included its own hint ("A sentence or two… is plenty"), and the whole string
   was stored as the label for the answer, so it came out embedded in the
   pasted artifact.
3. **A throwaway path got baked into a config.** The override was computed as
   `dataURL != default`, which is true whenever `UNLIRICE_DATA_PATH` is set —
   including for a one-off test run. `AppStore.mcpDataPathOverride` now reads
   the *persisted* folder preference, which is the only signal meaning "the user
   chose this."

**The flow is three deterministic screens.** Start (Autopilot toggle, on by
default), pick at least one MCP client, then per-target results. Requiring a
client is the point — a note store nothing is connected to is the state this
feature exists to get someone out of. Autopilot ON additionally writes the
house-rules note (`Autopilot.noteBody`, `source: "unlirice"`): standing
instructions addressed to the *assistant*, telling it to call `list_notes` at
the start of a session and `append_to_note`/`create_note` at the end. That note
is what closes the loop, because it's the first thing a connected tool finds
when it looks.

### Why MCP setup is a table, not one copy-paste block

There is no single MCP config format. Verified against real files on this
machine, not from memory:

| Target | Path | Format |
| --- | --- | --- |
| Claude Code | `.mcp.json` (per project) | `mcpServers` JSON |
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` | `mcpServers` JSON |
| Cursor | `~/.cursor/mcp.json` | `mcpServers` JSON |
| Antigravity | `.agents/mcp_config.json` (per project) | `mcpServers` JSON |
| Codex / ChatGPT | `~/.codex/config.toml` | TOML `[mcp_servers.x]` |

Claude Code and Antigravity are **project-scoped**, so there is no correct path
to guess — `configURL(projectFolder:)` returns nil until the user picks a
folder, and that nil is what blocks the Connect button.

Grok and OpenCode are deliberately **not** in the catalog. Their formats would
have been written from memory, and a wrong format produces a config that
silently never connects — worse than not listing the tool. `MCPTarget.custom`
covers them: the user picks the config file, and the format is inferred from
the extension.

### The rules around writing someone else's config

`MCPConfigWriter` is the only code in this app that edits a file the user owns
and this app did not create. Three rules, none optional:

1. **Never write a file we could not read.** If an existing config doesn't parse
   as JSON, the write is refused *before* any backup or modification, and the
   user gets the paste block instead. A config we can't parse is one we'd be
   replacing wholesale — and the tool that config belongs to is very often the
   tool they'd use to fix it.
2. **Back up before changing anything**, timestamped, alongside the original.
   A no-op merge writes nothing and backs up nothing, so re-running Get Started
   doesn't churn the config or litter the directory.
3. **Touch exactly one key.** A real `claude_desktop_config.json` carries
   `coworkUserFilesPath` and `preferences` next to `mcpServers`, and
   `mcpServers` itself holds other servers. All of it round-trips.

**Codex TOML is paste-only, on purpose.** Writing TOML correctly means a
dependency or a hand-rolled parser, and the file it would edit holds plugin
tables and five other servers. The generated block was verified by a real TOML
parser *and* by appending it to the actual `~/.codex/config.toml` — all six
servers parse, none clobbered — but verifying output is not the same as safely
rewriting someone's file in place, and the second is what an in-place edit
would require.

### Pointing the app at a different folder

The "I already have notes" path needed a capability that didn't exist:
`AppStore.service` and `dataURL` were `let`, resolved once, with the env var as
the only way to move the corpus. Both are now `private(set) var` and
`switchDataFolder(to:)` reopens the store against any folder, persisting the
choice in `UserDefaults` (a plain path — this target ships no sandbox
entitlement, so there's no security-scoped bookmark to keep alive).

Two traps:

- **Precedence is env → persisted folder → default**, and `UNLIRICE_DATA_PATH`
  outranking the preference is deliberate: it's what tests and smoke runs use to
  stay off real data, and a stale preference silently winning would let a test
  write into whatever vault the user last opened. The rule lives in
  `DataLocation.resolvedEventLogURL`, a pure function taking the environment and
  persisted path as arguments. `DataLocation` still reads no `UserDefaults`
  itself — `unlirice-mcp` links the same file and has no business reading the
  GUI's preferences.
- **Switching corpora invalidates everything derived from the old one.**
  `resetCorpusScopedState()` clears `mlxSimilarity` (it holds a title-embedding
  cache), `chatHistory`, `clusterRecommendations`, `janitorPreview` and
  `selectedNoteID`. Leaving any would have the window confidently describing a
  corpus it isn't showing. `janitorChat` deliberately survives — the model isn't
  corpus-specific and costs seconds to reload.

Package-path detection walks up from `Bundle.main.bundleURL` for `Package.swift`,
which resolves because `Scripts/mlx-run` pins `-derivedDataPath .build/xcode`
*inside* the repo. Verified against the real build output, which is a bare
executable rather than a `.app`, so `bundleURL` is the containing directory — it
resolves either way. Detection failing yields a visible placeholder rather than a
confidently wrong path.

## The chat panel (rename/MLX session) — REMOVED, kept for the reasoning

> **This code no longer exists.** `JanitorChat`, `AppStore+Chat.swift`,
> `ChatContext` and the Assistant sidebar item were all deleted along with the
> model. An agent connected over MCP answers the same questions better. The
> section is kept because the workarounds it documents are the evidence that
> retired the model — see "Removing the on-device model" below.

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

## UI Redesign: Liquid Glass & Note Graph (this session)

We overhauled the application aesthetics to support a premium, fixed-dark **"liquid glass"** design system:
- **Frosted Panels**: Left sidebar and right autonomy column use `.ultraThinMaterial` on top of translucent black backing.
- **Neon Back-Gradients**: Large, heavily blurred gradient circles (Violet, Teal, Amber) glow from behind the windows to bleed through frosted panels.
- **Glossy 3D Note Graph**: Rendered note nodes as glossy 3D spheres using offset radial specular highlights. Edges glow with custom multi-stroke lines (neon glow background + sharp neon core). Labels are centered inside legible semi-transparent capsules. Spaced physics values (repulsion: `-450.0`, spring rest length: `130.0`) prevent overlapping of nodes and text.
- **Recenter & Zoom**: The graph view supports trackpad zoom, mouse wheel, panning drag on background, and custom node manipulation. Double-clicking any note node navigates directly to its standard detail pane.

## The data lake: /raw, the pipelines, and routines (this session)

Built from a five-step framework for a self-improving knowledge system (base →
upload → inflow → loop → drive). Most of it landed as new code in
`Sources/UnliRiceCore/Ingest/` and `Sources/UnliRiceCore/Schedule/`.

**The important thing is what wasn't built, and why.** The framework's step 4 is
a three-bucket approval strategy — auto-approve the low-risk, get sign-off on
the high-stakes, escalate the ambiguous. That already exists here, one layer
down, and has since the janitor shipped:

| Framework | This codebase |
| --- | --- |
| Bucket 1: auto-approve | `JanitorRisk.cosmetic` → auto-applied tags |
| Bucket 2: needs sign-off | `flagForReview` → the review queue |
| Bucket 3: more context needed | The same queue, clustered |
| A daily `output/review/<date>.md` of checkboxes | `ReviewQueueView`, backed by the event log |

So ingest deliberately grew **no approval logic of its own**. The split is:
**the pipelines fill the lake, the janitor works it, the human decides.** An
importer that also judged its own output would be a second, weaker copy of a
boundary that's already enforced by type.

Likewise, the framework's `/wiki` folder isn't a folder here — the note corpus
already is one, with `[[wiki-links]]` and permanent titles. Only `/raw` was
genuinely missing.

### The pieces

- `RawStore` — content-addressed store at `raw/`, beside `events.jsonl` so that
  pointing the app at another folder moves the raw files with the corpus that
  indexes them. **Copies, never moves**, and never overwrites: decision #2
  applied to files the app doesn't own. It's a derived artifact — delete the
  whole directory and nothing the user owns is lost.
- `ResourceImporter` — the pipeline seam. Importers are handed no `NoteService`
  and no `RawStore`, so one cannot write a note however it's implemented. Same
  shape, and same reason, as `Janitor.scan` being pure.
- `ClaudeSessionImporter` — `~/.claude/projects/**/*.jsonl`.
- `LocalFileImporter` — folders the user nominates.
- `IngestRunner` — the safety boundary, deliberately shaped like `JanitorRunner`.
- `RoutineScheduler` — pure decision function; closes the scheduling half of
  deferred #5.

### `IngestRunner`'s boundary, and the one rule that's stricter than the janitor's

It calls exactly three write methods — `createNote`, `appendToNote`, `tagNote`.
A test asserts the event kinds it can produce are a subset of
`{created, appended, tagged}`, the direct counterpart of the janitor's
`{tagged, flagged}` test. That's the test to keep honest if the rules grow.

The extra rule: **it never writes into a note it did not create.** This matters
more here than for the janitor because importers *generate* titles — from
filenames and session titles — so colliding with a title a human already owns is
a normal occurrence, not an edge case. On collision it skips and says so.
Appending machine-built index text onto someone's hand-written note is not
undoable: appends are events, and events don't come off the log.

Authorship is read from the raw event log (`created` events with
`source: "ingest"`), not from `Note.sources` — that field is the *set* of
everyone who ever wrote to a note and cannot answer "who created this".

### Two bugs the real corpus caught, exactly like the janitor's dry run

The lesson from the janitor's calibration pass — run the rules over real data
before trusting them — paid off twice. A read-only dry run over the actual 285
sessions in `~/.claude/projects`:

1. **279 unique titles from 285 sessions.** A git worktree gets its own
   `~/.claude/projects` directory but shares the parent's session ids, so the
   same session is genuinely discovered twice in one pass. `byTitle` was seeded
   once before the loop, so the second copy wouldn't see the note the first had
   just created — and would mint a second note with a byte-identical
   **permanent** title, the one thing a permanent-title corpus can't recover
   from. Regression test: `testTheSameKeyTwiceInOneRunDoesNotCreateTwoNotes`.

   **That fix was insufficient, and the calibration run below caught the rest.**
   Matching on title only works if titles are stable, and they are not: a
   session's `ai-title` is *regenerated as the conversation grows*, and two
   worktree copies of one session diverge, so their titles differ by a few
   characters and by where truncation falls. One session id turned up across
   three notes. Identity is now `DiscoveredResource.key` — the session id, or a
   document's absolute path — carried in the note body as `[ingest:<key>]` and
   matched on there. The title is a display name and nothing more.
   `ClaudeSessionImporter` additionally collapses copies of one session at
   discovery, keeping whichever saw more messages.

   The scale of it: **285 discovered sessions became 183 after collapsing —
   36% of them were duplicate worktree copies.** Any title-keyed scheme was
   always going to produce a corpus a third of which was redundant.
2. **372 MB across those sessions, 8 files over the 8 MB per-file limit.**
   Ingesting copies, so a naive first run would have doubled that in one go.
   `IngestConfig.noteBudget` (40) is what keeps it gradual — the same
   "don't bury the user" reasoning behind the janitor's per-run budgets, now
   load-bearing for disk footprint as well as attention.

### Post-ingest calibration: the embedding model stops paying for itself

Re-ran `janitor-calibrate` over the deduplicated post-ingest corpus (233 live
notes: the real 50 plus 183 ingested sessions, 27,028 pairs). The measurement
this project has always used to settle threshold questions now says something
about the model itself.

| | token overlap | MLX (bge-micro) |
| --- | --- | --- |
| Balanced, would queue | 21 | 8 |
| Aggressive, would queue | 73 | 24 |
| Cosmetic (tagging) | 45 | 45 |

MLX looks quieter — but **the two engines' top pairs are the same pairs**, in
nearly the same order: the `clearspace-session-log` cluster, the
`orchestrator-grill` pair, the `lib.js`/`compact.js`/`import.js` cluster. They
also make the *same false positives*: `lib.js ⟷ compact.js` are different source
files sharing a path prefix, and both engines flag them.

Two conclusions follow:

1. **Selectivity is a threshold, not a model.** Token overlap at ≥0.85 surfaces
   3 pairs; MLX at its own 0.985 surfaces 8. Token overlap tuned up is *more*
   selective than the embedding model, at zero dependency cost. Its default is
   currently 0.75, which is simply set too low for a corpus this size.
2. **Tagging never needed the model** — 45 cosmetic proposals from either
   engine, since that rule is string matching.

Also worth recording because it contradicts the prediction made earlier in this
section: **ingest did *not* flood the duplicate detector.** No ingested session
note appears in either engine's top pairs. Including the session id in the title
makes them distinctive enough, and collapsing worktree copies removed the real
source of noise. The flags that remain are all from the hand-written corpus.

A third bug was caught by a unit test rather than the corpus: `RawStore`
deduplicates by digest, but the *filename* also carries the original name for
readability, so identical bytes arriving as `a.md` and `b.md` computed two
different destinations and were stored twice. Identity is now looked up through
a digest→filename index instead of being inferred from the path.

And one avoided by construction: `LocalFileImporter` originally disambiguated
colliding titles with `hashValue`. Swift seeds `Hasher` randomly **per process**,
so that suffix would change on every launch and each run would mint a fresh
permanent title for the same file — a duplicate-forever bug that unit tests
passing within a single process would never have shown.
`ImporterText.stableSuffix` uses SHA-256.

### Why there's no default scan root

`LocalFileImporter.roots` is non-optional with no fallback. The framework says
"scan your computer"; this asks which folders. A scanner starting at `~` would
copy a decade of unrelated documents into `/raw` and index them, and nobody
reviewing four thousand notes can tell which ones they meant to add. "Scan
everything" is not a state the type can be left in by accident.

Prose only (`md`, `txt`, `rst`, `org`) — **source code is deliberately excluded.**
It's already in version control, an agent can read it directly, and indexing it
would bury the documents that actually carry decisions.

### Routines, and Eco's promise finally having code behind it

`RoutineScheduler` is a pure function, for the same reason `Janitor.scan` is: a
scheduler holding a `NoteService` could quietly grow the ability to write, and
the one thing that must stay true of unattended execution is that *deciding to
run* and *running* are separate.

Two routines, Tuesday and Friday — ingestion at 09:00, improvements at 13:00, so
the janitor always works on data that already arrived rather than racing it.
There is deliberately **no third routine for human review**: a routine is
something this app makes happen, and it cannot make a person look at a queue.

`lastFiring` looks *backwards* — "has this slot passed unserved", never "is it
exactly 09:00". That's what lets a slot survive the Mac being asleep at the
scheduled minute; a forward-only timer would skip it silently, and a pipeline
that quietly stops is worse than one that never started, because the corpus goes
stale while still looking maintained. The GUI heartbeat is therefore a coarse
5-minute tick, not a precise alarm.

`RoutineScheduler.gate` is where Eco's documented "only while plugged in and
idle" finally became code rather than a sentence in the UI — that gap was called
out in deferred #5 and #6. Eco needs power **and** 5 minutes idle; Balanced
takes either power or 2 minutes idle; Aggressive doesn't gate. **No level grants
any permission the manual button doesn't already have** — aggressive runs
sooner, never wider.

Desktops report no power sources at all, which is read as on-power. Treating it
as "on battery" would mean Eco never runs on a Mac mini.

**Routines ship off by default**, and the panel says so. This app reads the
user's own files; that is not something to start doing because an update
shipped.

### Running the GUI to check it, and what that caught

Worth writing down because it's non-obvious and cost time. The app is a **bare
executable, not a `.app` bundle**, so it isn't in the LaunchServices index —
screenshot tooling that resolves apps by name can't see it at all. What works:
find the window by owner PID through `CGWindowListCopyWindowInfo` and capture it
by id with `screencapture -l<id>`. Note that the main window does *not* appear
under `.optionOnScreenOnly` when the app isn't frontmost; list with no options
and filter by height.

Run it against a scratch corpus, not the real one —
`UNLIRICE_DATA_PATH=<scratch>/events.jsonl`, which is exactly what that override
exists for.

Doing this caught a bug no amount of building would have: **`Toggle` reports its
label's width as its ideal width**, so the routines toggle's original long label
("Run on a schedule (Tue & Fri)") pushed `DataPipelinePanel`'s VStack wider than
the sidebar and clipped *every sibling* — the status line rendered as "Off —
nothing runs unless you press a butto…". The label is now two words with the
detail on the line below, plus `.fixedSize(horizontal: false, vertical: true)`
so it wraps instead of truncating. Any future long label in that sidebar will do
the same thing.

## Removing the on-device model (this session)

`UnliRiceMLX` is gone. So are `JanitorChat`, `AppStore+Chat.swift`,
`ChatContext`, the Assistant sidebar item, `Scripts/mlx-run`, the
`mlx-swift-examples` dependency, and the macOS 14 floor it forced. The package
now has **no external dependencies** and builds under plain `swift build`.

**This was decided by measurement, not taste** — see "Post-ingest calibration"
above for the table. The short version: over a 233-note corpus the embedding
model surfaced the *same top pairs* as token overlap, in nearly the same order,
and made the *same false positives*. Its apparent advantage was volume, and
volume is a threshold: token overlap at ≥0.85 is more selective than the model
was at its own 0.985. So `TokenOverlapSimilarity`'s default moved 0.75 → 0.85
(and aggressive 0.55 → 0.65), and the model was removed rather than carried.

The chat half had already accumulated its own verdict. This file records, three
separate times, that a 1–3B local model underperformed here: the similarity
work, the chat panel needing two independent workarounds, and the Get Started
interview being cut after a single real run. Deleting it is that conclusion
applied rather than re-derived.

### What replaced it

**Nothing, in the app.** The intelligence lives in the agent the user already
has. Anything connected over MCP can call `list_notes`, `tag_note` and
`flag_for_review` — the janitor's entire permission set — and reads meaning
instead of comparing title cosines.

Worth knowing for anyone wiring that up: **MCP points the wrong way for
scheduling.** This app is the *server*; it cannot call out to Claude, so
"a cloud model does the maintenance" only happens while a session is open. The
intended shape is for the maintenance routine to live in the *client's*
scheduler and call these tools — which is also why nothing here stores an API
key or a credential, and nothing should.

### `RemoteSimilarity`, and the one rule on it

`Sources/UnliRiceCore/Janitor/RemoteSimilarity.swift` is the bring-your-own
seam for someone already running a local model server (LM Studio, Ollama —
OpenAI `/v1/embeddings` shape). Off by default, empty fields, no network
traffic unless configured.

**It refuses any address that isn't loopback, and that is not a preference.**
`warm(_:)` sends every note title to the endpoint, and note titles are the
user's own content. Shipping a text field that will POST someone's corpus to
an arbitrary host because a URL was pasted into it is not a thing to do
quietly. If remote endpoints are ever wanted, that must be an explicit,
separately-labelled decision. A test asserts the refusal.

The same seam keeps the lesson the MLX work paid for: thresholds travel with
the provider, because a cosine scale and a Jaccard scale mean nothing alike.
Anyone plugging in their own model should re-run `janitor-calibrate` against it
rather than trusting the inherited numbers — the tool now takes a base URL and
model name for exactly that.

### What was kept, and why

`janitor-calibrate` survives with only its MLX half removed. It would have been
easy to delete alongside the model, but it is the tool that produced the
evidence for deleting the model, and the thresholds it tunes matter *more* once
there's no model to hide behind. It has now twice settled an argument that
reasoning alone got wrong.

## Running with the window closed (this session)

Everything this app said about unattended maintenance used to be true only while
you were looking at it: `tickRoutines` was a SwiftUI `.task` attached to the
window. For an app whose pitch is "you shouldn't have to visit me", that is the
difference between the automation working and looking like it works.

- `Sources/unlirice-agent/` — a fourth executable. launchd starts it every five
  minutes; it does **one tick and exits**. No loop, no resident process: it can't
  leak, can't wedge, and can't hold a stale view of the settings.
- `Sources/UnliRiceHost/` — a new target for the handful of things that have to
  ask macOS a question: IOKit (power), CoreGraphics (idle), launchd
  (`BackgroundAgent`). The GUI and the agent both depend on it, so there is one
  answer to "is this Mac plugged in", not two that can disagree. `UnliRiceCore`
  stays dependency-free — it's what `unlirice-mcp` and the whole test suite link.
- `RoutineDriver` (in Core) is the shared body of the loop. **Both** the window
  heartbeat and the daemon call it, so a scheduled run cannot quietly differ from
  a button press. `Pipelines.standard` exists for the same reason.

**Nothing about the permission boundary changed, and that is the point.**
`IngestRunner` and `JanitorRunner` still enforce `{created, appended, tagged}`
and `{tagged, flagged}` by type. Running from a daemon rather than a button
grants neither of them anything — which is exactly why `RoutineDriver` is as
short as it is, and why `RoutineDriverTests` asserts Eco still refuses to run on
battery when headless.

### The three files that make two processes agree

| File | Scope | Written by |
| --- | --- | --- |
| `agent.json` (support dir) | app | GUI only — the agent reads, never writes |
| `routine-state.json` (beside the log) | corpus | whoever serves a slot |
| `notices.json` (beside the log) | corpus | both |

`AgentSettings` is a file rather than `UserDefaults` because the agent is a
different binary with a different defaults domain: it would have read an empty
domain, concluded routines were off forever, and looked exactly like a bug in
scheduling. Last-run stamps moved out of `UserDefaults` for the sharper version
of the same problem — two processes each remembering their own "last run" would
serve the same 09:00 slot twice. `RoutineRunLock` (`flock`) covers the remaining
race where both tick at the same instant; existing `UserDefaults` stamps are
migrated across once on launch.

**Smoke-tested for real**, against a copy of the live log: `unlirice-agent`
ingested 40 sessions, ran the janitor, and posted three notices — which then
appeared in the GUI's notification centre in a *separate* process. Use
`UNLIRICE_AGENT_SETTINGS` (alongside `UNLIRICE_DATA_PATH`) to do that again
without switching routines on for real.

### What the first real press of the toggle taught us

Three things, none of which any test caught, all found by opening the packaged
app and using it:

1. **The toggle could lie.** `Toggle(isOn:)` with a get/set binding flips
   *visually* on click, then relies on a republish to correct itself. A failed
   install left `backgroundAgentInstalled` false → false, nothing published,
   nothing re-rendered — so the switch sat there reading **on** while no job
   existed. `setBackgroundAgent` now always calls `objectWillChange.send()`, and
   the failure is shown next to the toggle rather than only in `errorMessage`,
   which renders in the note list — not the panel you're looking at when you
   press it.
2. **`SMAppService` does not work here.** It's the modern API and the rewrite to
   it was half-done before being reverted: `register()` returns `Operation not
   permitted` because it requires a properly signed app, and `make-app.sh` can
   only sign ad-hoc without a Developer ID. If this ever gets a signing
   identity, switch — it puts the job in Login Items where a user can find it.
3. **The diagnosis that sent it down that path was wrong, and measuring settled
   it.** The symptom (installed job, toggle reading off) looked exactly like
   macOS protecting `~/Library/LaunchAgents` from a double-clicked app. A
   throwaway probe run from inside the real bundle showed it listing *and*
   writing that folder happily — so the direct-plist approach was fine all
   along. Same habit as the janitor's calibration runs and the ingest dry run:
   this project has now been wrong three times in a way that only running it
   against reality could reveal, and right every time it did.

`unlirice-agent --status` / `--install` / `--uninstall` exist because of this.
The GUI had no way to report *why* the toggle did nothing; a one-line command
that prints the real error is the difference between a five-minute fix and
guessing.

**Known sharp edge**: the installed job holds an absolute path to the agent
binary. Running the app from `dist/` and later moving it to `/Applications`
leaves the job pointing at the old copy. Re-toggling reinstalls it correctly.

### Double-clickable

`Scripts/make-app.sh` assembles `dist/Unli Rice.app` — GUI, MCP server and agent
in one `Contents/MacOS`, ad-hoc signed. The bundle isn't cosmetic: it's how
`BackgroundAgent.locateBinary` finds the agent. A launchd job pointing into
`.build/debug` would break the next time anyone ran `swift package clean`, and a
job pointing at a missing binary installs perfectly happily and then does nothing
forever — so `locateBinary` returns nil rather than a plausible guess, and the
toggle disables itself with an explanation.

## Performance: the projection stopped being quadratic (this session)

Deferred item #8, closed. It said "measure before assuming; it hasn't been" — so:

| notes (2 writes each) | before | after |
| --- | --- | --- |
| 100 | 0.34s | 0.013s |
| 200 | 1.29s | 0.025s |
| 400 | 5.21s | 0.043s |
| 4000 | (~minutes) | 0.47s |

The old numbers grow 4× per doubling; the new ones grow 2×. Three changes:

1. **`EventStore.read(from:)`** — a byte-offset cursor into the append-only log.
   Sound *only* because nothing before the cursor can ever change; if the log
   ever gains rewriting, this type is the alarm. Takes a shared `flock` and stops
   at the last newline, so a partial line from a non-`EventStore` writer is read
   once it's complete rather than skipped forever.
2. **`NoteService` keeps the projection** and folds only new bytes onto it.
   A read with nothing new does no projection work at all — which is the case
   that matters, since every MCP `list_notes`/`search_notes` is one.
3. **`LinkIndex`** — incremental wiki-links.

Point 3 is the one worth remembering, because the first attempt was wrong.
Caching the *body parse* seemed obviously right and moved 400 notes from 1.00s to
0.84s. The expense was never the bracket-scanning: it was rebuilding n sets and
re-sorting n titles on **every one of 800 writes**. `LinkIndex` instead tracks
what can actually change — a changed body affects only that note; a new note
affects whatever was dangling on its title or its raw UUID, found by index rather
than by scanning; a tag, archive or flag can't affect links at all, so a whole
janitor pass now costs nothing here. That took it to 0.043s.

`Projector.resolveLinks` stays the simple whole-corpus version on purpose: it is
the *definition* of what links mean, and `ProjectionCacheTests` asserts the
incremental answer equals a cold `Projector.project` of the same log — including
over a 60-note mixed sequence of creates, appends, tags, archives and links. If
the two ever disagree, the cold one is right.

## The notification centre and the review screen (this session)

Two things that answer one problem: the app wants to run itself *and* to be worth
opening a year later, and those clash the moment it needs you to come to it. A
year of unattended work with no way to mention anything becomes a pile of chores
waiting at the door.

**`NoticeStore`** is deliberately *not* the event log. Everything in
`events.jsonl` is permanent by design; notices are read, go stale, and get
trimmed (capped at 50). Deleting the file loses nothing the user owns — the same
status `/raw` has. Three rules earned their keep:

- `Notice.key` identifies **the situation**, not the telling of it. Posting over
  an existing *unread* notice with the same key replaces it, so an agent ticking
  every five minutes reports one review queue, not 288 a day. Once read, the key
  is free again, so a situation recurring after you've dealt with it is news.
- A routine that ran and changed nothing posts nothing. Read from the runners'
  own counts, not sniffed out of their summary text — "285 scanned, 0 new" is
  full of digits and describes nothing happening.
- A **failure** never collapses into the success notice. A pipeline that quietly
  stops while still looking maintained is the failure this design fears most.

Notices point; they never act. `NoticeDestination` is a closed enum of screens,
so nothing here can resolve a flag or consolidate a duplicate — decision #3,
enforced by type again rather than by discipline.

**`Retrospective`** is a pure function over notes, and needs no new data at all:
every note already carries when it happened, what wrote it, which project
(`**Project:**`, from the ingest pipelines) and what links to it. Months and
years only — a week is too short to have forgotten and a quarter is a unit of
work, not of memory. Periods with nothing in them are never offered.

Highlights rank by how many notes point *back* at something, not by length:
recognition, not volume. Archived notes are excluded, because archiving is how
someone says stop showing me this and a year-in-review that resurfaces exactly
what they filed away is the app arguing with its user — the same mistake
`JanitorRunner`'s untag check exists to avoid.

**Running it over the real corpus caught two bugs again**, as it has every time:
the top "most-worked project" came out as the home folder's name, and a note
whose prose began "**Project:** Architecturally…" was counted as a project called
"Architecturally". `Retrospective.project(of:)` now requires an absolute path of
more than two components. Both are pinned by tests.

`DigestAnnouncer` announces the month *just ended*, once — never the month in
progress, and never twelve of them to someone who ignored the app for a year.
It is not a third `RoutineKind`: the decision recorded above ("a routine is
something this app makes happen, and it cannot make a person look at a queue")
still stands. This is the other half of that thought — if the app can't make you
look, the least it can do is pick one moment worth mentioning it and then be
quiet.

## The 200-note pass: scrolling, connectors, trash (this session)

Everything here came out of using the app against a real corpus (190 notes, 144
of them ingested Claude sessions) rather than the eight-note store the UI was
designed on. At that size four things broke that weren't visible before.

**All Notes did not scroll.** `NoteList` was a plain `VStack` inside the column's
`VStack` — no `ScrollView` anywhere in that path. Every row past the window's
height was rendered off-screen and unreachable, and the `NewNoteRow` composer was
pushed out with them. Fixed by pinning the header and composer and scrolling only
the list, with a `LazyVStack` (ingest adds 40 notes a click; the eager stack built
every row view on every redraw). The list also gained search over
title/body/tags/source, date group headers, a first-line body preview per row, and
a hover **Archive** button — archiving used to require opening the note first,
which is backwards: you judge a note is noise from its title.

The source badge is now hidden when it says `claude`. With every note in the
corpus stamped `claude`, 190 identical badges carried no information.

**Get Started became Connect.** The three-stage wizard (`SetupStage.start` →
`.chooseTargets` → `.results`) is gone; `SetupStage` and `connectSelectedTargets`
remain only because the enum is still referenced, and the screen no longer reads
them. It's a flat connector table modelled on Claude's own Connectors panel: one
row per tool, each acting alone via `AppStore.connect(_:)`, each showing live
state from `MCPConfigWriter.presence` — a **read-only** probe added for this, so
drawing the screen doesn't attempt writes on five of the user's config files.
Batching five independent switches into one commit was the whole problem: "is
Cursor connected?" was unanswerable once you'd left the results page.

**The graph's grouping was fiction.** Colours were hardcoded to four tag names
(`ai-context`, `guardrails`, `projects`, `system`) picked when the corpus was tiny;
on the real store almost nothing matches and everything lands in one grey cluster.
Groups are now derived from the notes present, under a `GraphGrouping` picker —
**Tag / Author / Year-Month**. Author is `note.creator`, which is finally
meaningful now that multiple LLMs write here. Cluster centres are evenly spaced on
a circle (the old four were hand-placed with nowhere to put a fifth), and there's
a **Fit** that solves for the node bounding box plus a one-shot auto-fit 3s after
load. "Recenter" only ever reset to 100% at the origin, which fits nothing once
the layout is bigger than the window.

Two things about the graph are worth knowing before touching it again:

- **Labels are budgeted.** Above 60 nodes they're drawn only for hover, selection,
  or an active group filter. At 170 they overlap into a solid block of text with
  the graph somewhere underneath — every node having a label is the same as none
  having one. `fitToWindow`'s padding allowance follows the same rule, since
  padding for labels that aren't drawn just zooms out for nothing.
- **`fitToWindow` takes the size as an argument, from the enclosing
  `GeometryReader`.** Don't "simplify" it back to reading a `@State var
  viewportSize`. That was tried: the `onAppear` read captured a zero, `onChange(of:
  geometry.size)` never fired, and a `PreferenceKey` measurement didn't populate it
  either — so the function tripped its own `width > 0` guard and returned silently
  on every call, with the button appearing dead and the zoom readout stuck at 100%.
  The auto-fit is a `DispatchQueue.main.asyncAfter` in `onAppear` for the same
  reason (that's where the size is in scope), and it's a fixed delay rather than a
  watch on `alpha` because hover and drag re-heat the simulation — "has cooled" is
  a state the user can postpone forever just by moving the mouse.

**Review Queue → Review Notes**, with a **Clean up** menu, and Archived gained
**Ask an LLM…**. Both copy a prompt from `CleanupPrompts` to the clipboard and do
nothing else. That's deliberate and follows decision #3: judging which of four
near-identical ingest notes is the real one needs a model that can read all four,
and that model is the one the user already has connected. A "Delete all ingest"
button would make the app the thing that decides. Each prompt restates the house
rules (append-only, no delete, titles permanent) because it gets pasted into a
fresh chat that has never seen `AGENTS.md`.

### Trash — the carve-out in decision #2, now real

`TrashService` is the first and only code in this repo that removes note history
from the log. Decision #2 always allowed for this — *"must be a human-triggered
action, never something an agent or the janitor can invoke autonomously"* — and
the carve-out is enforced structurally, not by convention:

- It lives **outside `NoteService`**. `unlirice-mcp` builds its tool catalog from
  `NoteService` methods, so no MCP tool can be wired to it even by accident. An
  agent cannot express the operation at all.
- `RoutineDriver` has no path to it. It never runs unattended.
- It's reachable from one place: ticking notes in **Archived** and confirming an
  `NSAlert`. The alert is raised inside `moveSelectedToTrash`, not in the view, so
  a second caller can't reach the purge without it.

Mechanically it is a backup-then-rewrite, in a fixed order that can't be
rearranged: copy the whole log to `Backups/events-<stamp>.jsonl`, write each note's
complete event history to `Trash/<uuid>.json`, then rewrite the log without those
lines — all under one exclusive `flock`, so a concurrent MCP write can't be
silently dropped by the rewrite. A crash between any two steps leaves the log
either untouched or fully rewritten with the recovery data already on disk.
Surviving lines are written back **byte-for-byte** rather than re-encoded, so a log
written by another version of this app can't be reformatted or have unknown fields
dropped. `TrashService.restore` appends a trashed note's events back onto the log —
still append-only, still projects identically, which is why the purge can afford to
be the one rewrite in the system.

Seven tests in `TrashTests.swift` cover it (202 in the suite overall now): only the
targeted note goes, the backup is byte-identical to the pre-purge log, a restore
reproduces body/tags/sources exactly, and a purge of unknown ids writes no backup
and changes no bytes on its way to throwing.

### Every switch has to do something

An audit of every `Toggle` and `Slider` in the GUI, against what each one is
actually wired to:

| Control | Wired to |
|---|---|
| Autonomy slider | Real. `JanitorConfig` reads it — eco disables structural rules, aggressive enables orphan detection and drops `minimumTagCorpusUse` 2→1, plus the thresholds. Synced into `AgentSettings` for the background agent. |
| Run routines on a schedule | Real. Gates `RoutineDriver` and `unlirice-agent`. |
| Keep working with the window closed | Real. Installs/removes the launchd job, and reads its state back from disk rather than remembering it. |
| **Autopilot** | **Nothing, by the time you'd have touched it.** Removed. |

Autopilot's entire effect was writing one note whose body is `Autopilot.noteBody`
— prompt text telling an assistant to read the notes at session start and write
back at the end. Three things were wrong with expressing that as a switch:

1. **A binary is the wrong control for a prompt.** It offers a choice between our
   wording and nothing, when the thing a user wants is to change a line — add
   their own conventions, drop a rule that doesn't fit how they work.
2. **It didn't persist.** There was no `UserDefaults` key, so "off" silently
   became "on" at the next launch.
3. **It was inert in both positions.** The write was guarded on the note not
   already existing, so after the first connect the switch did nothing either way.

It's now `AppStore.houseRulesText`: the text itself, editable and persisted,
with an explicit Save. Saving is no longer a side effect of connecting a tool —
a note appearing in your store is something you should have asked for. Edits
append rather than rewrite, which is both what the append-only log requires and
the honest representation: the assistant reads the whole body with the newest
text last, and the original wording stays in the history.

One related thing this audit found and did *not* change: `monthlyReviewEnabled`
is persisted and read by `RoutineDriver`, but no control anywhere sets it, so it
is permanently `true`. That's a setting without a switch rather than a switch
without an effect — worth either surfacing or hardcoding, but it isn't lying to
anyone today.

### The right-hand panel is gone

`AutonomyPanel` — the 260pt column of settings and manual triggers pinned to the
right of every screen — is now `AutomationView`, a sidebar destination like every
other pane. Nothing was cut except the "Review queue" pointer inside it, which
duplicated the sidebar's own Review Notes row and its badge.

The reasoning: every control in it is setup or a deliberate manual trigger. You
touch the autonomy slider, the janitor's Preview/Run, the ingest folders and the
two schedule switches when configuring the app or when you want something to
happen *now* — not while reading a note. Pinning them cost the main column a
fifth of the window on panes where none of it applied (Connect, the graph, the
retrospective), and a permanent wall of knobs is the opposite of the
invisible-by-default posture the rest of the app is built around.

It also lifted a constraint the narrow column imposed on the controls themselves.
A `Toggle` reports its label's width as its ideal width, so long labels used to
widen that whole VStack and clip its siblings — which is why the switches were
called "Routines" and "In background" with the explanation exiled to a line
underneath. They now say "Run routines on a schedule" and "Keep working with the
window closed", and the janitor/ingest previews scroll instead of truncating at
eight items.

One bug fixed alongside it: `showLast(_:)` echoed its argument into the status
line, so "Everything" (which passes `Int.max`) followed by a click on All Notes
reported *"Showing: last 9223372036854775807 updated notes."* It now describes
what's on screen rather than the ceiling it was given.

Verified against the real 170-note store, on screen: All Notes scrolls with sticky
date headers and distinct per-row previews ("170 of 170"), search filters, Connect
renders the five connectors with live per-row state, Review Notes' Clean up menu
puts the right prompt on the clipboard (checked with `pbpaste`), Archived shows its
toolbar with Move to Trash correctly disabled on an empty selection, and the graph
fits the window under both Tag and Author grouping with Fit reframing to 48% to
catch the outliers. The only things not directly observed are the 3-second auto-fit
firing on load (it calls the same `fitToWindow` the button proves works) and the
Automation pane itself — macOS screen capture stopped working before that build
could be photographed, though it compiles, launches, and stays up.

## Trust Center: connection evidence, recovery, and note history (2026-07-22)

The new **Trust Center** closes three trust gaps without putting a model or a
cloud service inside the app:

- `MCPConnectionActivityStore` records local, content-free evidence that a
  client initialized the server or called a tool: client name/version, time,
  tool name, and success only. Arguments and note contents never enter the
  diagnostic sidecar. The Trust Center combines this with event-log
  readability, vault writability, snapshot availability, and launch-agent
  state so “configured” is no longer presented as proof that memory works.
- `VaultSnapshotService` captures `events.jsonl`, `/raw`, House Rules, routine
  state, and notices into a corpus-scoped recovery point with a SHA-256 manifest.
  Creation verifies every copied file. Restore verifies again, appends only
  event IDs missing from the live log, and copies only absent raw files; it never
  replaces current history or settings. The same screen finally exposes
  `TrashService.restore` in the GUI.
- `NoteService.noteHistory` and the matching `note_history` MCP tool return one
  note's immutable events oldest-first. Note detail renders that attribution
  timeline and parses ingest-owned provenance markers to reveal the original
  file and preserved raw copy when available.

Recovery, trash restore, and provenance actions remain GUI-only and
human-triggered. Connection activity and snapshots are derived sidecars, not
events: losing either cannot lose or change a note.

## App Store dead-code sweep (2026-07-21)

The App Store connection design is now enforced by the core API, not just by
which button the UI happens to call. `MCPConfigWriter` and its automatic JSON
merge, backup, presence-probe, and config-path machinery were removed. The only
remaining surface is `MCPConfigRenderer`, which turns an `MCPServerEntry` into a
JSON or TOML block for the clipboard. This supersedes the older Connect section
above: there is no live per-row config state and no code in the product that can
modify another app's configuration.

The same sweep removed connector state that only meant "copied during this
process" but was labelled connected, plus a target lookup, trash count, and
default-data resolver with no callers. Review-prompt menus now list the available
tools without pretending the app inspected their configuration. The hidden
`monthlyReviewEnabled` GUI preference was also removed and its existing product
behaviour made explicit (`true`) when generating `AgentSettings`; its persisted
key had no control anywhere in the app.

The target model now contains only what the copy flow consumes: display name,
paste destination text, and config format. Project-folder resolution,
user-config resolution, and "supports automatic write" flags were deleted with
the feature they served. The Xcode project was regenerated, the Release app
bundle built successfully, and the resulting suite is 205 passing tests. Ten
tests disappeared because they exclusively specified the removed writer and
destination-resolution behaviour; all renderer-format coverage remains.

## App Store release packaging verification (2026-07-21)

`project.yml` is now the committed source of truth for the Xcode project and
persists development team `22SNGN5JYD`, automatic signing, sandbox entitlements,
version 1.0 (build 1), app category, and the encryption declaration. The app
icon moved from a loose resource into a complete macOS `AppIcon.appiconset`, so
`actool` writes both `CFBundleIconFile` and `CFBundleIconName` into the archive.
The public privacy and support URLs are recorded in `APP_STORE_SUBMISSION.md`
and exposed from the in-app privacy screen.

The two embedded executables are independent sandboxed tools because launchd
and MCP clients start them directly rather than as children of the GUI. Both
now receive stable bundle identifiers, embedded Info.plists, the same Team ID,
the App Group entitlement, and hardened-runtime signatures. A signed Release
archive was inspected rather than assuming the build settings worked: the GUI,
agent, and MCP server are universal `x86_64 arm64` binaries; deep strict
signature verification passes; the privacy manifest and generated Info.plist
lint cleanly; and the archive contains the launch-agent plist, asset catalog,
compiled icon, and privacy manifest.

The source-side release work is complete, but the locally available development
profile is still the team's wildcard profile and does not grant the App Group.
Before Organizer can validate an App Store distribution, the owner must register
`com.calmdownoscar.unlirice`, register and attach
`group.com.calmdownoscar.unlirice`, and let Xcode create the distribution
profile. Those account-side steps are deliberately not hidden behind code or a
temporary entitlement exception.

## Xcode release inputs restored to main (2026-07-22)

The App Store release work had been committed on `codex/app-store-release`, but
that branch was never made an ancestor of `main`. The ignored generated
`UnliRice.xcodeproj` remained on disk and still referenced
`UnliRice.entitlements`, `UnliRiceHelper.entitlements`, release resources, and
source files that disappeared whenever the checkout returned to `main`. SwiftPM
therefore stayed green while Xcode failed first at `CODE_SIGN_ENTITLEMENTS` and
would then have failed on stale source references.

The release branch is now reconciled with the newer House Rules and Trust Center
work. `project.yml`, both entitlement files, the embedded launch-agent plist,
privacy manifest, icon catalog, and release documentation are restored as
versioned source-of-truth inputs. The Xcode project was regenerated with XcodeGen
so it includes the Trust Center sources as well as the release resources. The
combined tree passes 222 Swift tests, a signing-disabled Xcode Debug build, a
signed Xcode Debug build, and a signed universal Release build. The signed app
and both embedded helpers expose the expected sandbox and App Group
entitlements.

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
5. **The janitor.** ~~The embedding model~~ — built, measured, then **removed**;
   see "Removing the on-device model". ~~Scheduling/triggering~~ — done, see
   "Routines": `RoutineScheduler` gates on power and idle time, and the GUI
   ticks it. What's left:
   - ~~**Generative TL;DRs**~~ — **dropped, not deferred.** This was the last
     planned cosmetic action, and it required exactly the on-device generative
     model that was just deleted for underperforming. If it ever returns it
     must come from an agent over MCP, and it must still be cosmetic
     (append-only, one note, no meaning change) or it is a `flagForReview`.
   - **Verify a routine actually fires unattended.** Half-done. The full path
     — decide, run, record, notify — has now been exercised end to end by
     running `unlirice-agent` against a copy of the real log: 40 sessions
     ingested, janitor run, notices posted and then read by the GUI in a
     separate process. What still hasn't been observed is **launchd** starting
     it on a real Tuesday, and the power/idle readers have still never been
     exercised on battery. Neither pipeline button has been *clicked* in the
     GUI either.
6. ~~**Battery/aggressiveness settings**~~ — done. The three levels exist as
   `JanitorAutonomy`/`JanitorConfig` and are honoured by the rules, and the
   *battery* half is now `RoutineScheduler.gate` — Eco's "only while plugged in
   and idle" is enforced rather than merely described.
7. **Real search.** `search_notes` is currently plain case-insensitive
   substring matching over title/body/tags. No embeddings/vector search yet
   — intentionally deferred until the embedding model (#5) exists.
8. ~~**Performance**~~ — done, measured, see "Performance: the projection
   stopped being quadratic". Reads are now O(1) when nothing has been appended,
   and a 4000-note build takes 0.47s where it used to take minutes. **What's
   left**: `transactionLog(limit:)` still decodes and sorts the whole log on
   every call. That's once per janitor run (`humanRemovedTags`) and once per
   ingest run, so it's linear-per-run rather than quadratic and hasn't been
   worth an event cache yet — but it is the next thing to look at if runs get
   slow, and unlike the projection it has no cache behind it at all.

9. **The other two pipelines from the framework.** Built: Claude sessions, local
   documents. Not built:
   - **Ecosystem sync** (meeting transcripts, Slack, YouTube) — each needs a
     network integration and a credential story, neither of which exists here.
   - **Curated content** (a `+newsletter@` email alias filtered into the wiki).
   Both fit `ResourceImporter` without changing anything else — that seam is
   the whole point. The deliberate omission is any pipeline that would make
   this app hold a third-party credential; nothing here does today.

   Also unbuilt: **periodic voice/rant dumps**. The framework routes these
   through the same "add a resource" path, which here is just dropping a file
   into a scanned folder — so this may need no code at all. Try it that way
   before building anything.

## Mac App Store submission (this session)

Submitted 2026-07-21: Content Rights Information (no third-party content),
App Privacy (Data Not Collected), and Pricing (Free) were the three blockers
App Store Connect required before "Add for Review" would unlock — all three
resolved, matching the declarations already recorded in
`APP_STORE_SUBMISSION.md`. The build is now **Waiting for Review** with
**automatic release** on, so it goes live the moment Apple approves it with
no further action needed. `Screenshots/AppStore/` (4 screenshots, 2880x1800)
and `Screenshots/unli-rice-promo.png` (marketing hero) were generated this
session too, built from real window captures rather than mockups.

## House Rules template gallery and per-vault drafts (2026-07-21)

House Rules on Connect is now a template workflow rather than only one large
free-text field. `HouseRulesPreset` supplies three built-ins — Standard Memory,
Codebase Memory, and Minimalist / Low Token — and the new two-pane gallery shows
the exact monospaced text plus approximate token and character counts. Imported
UTF-8 `.md`/`.txt` files are validated (empty, binary, and files over 200 KB are
refused), previewed, and added as custom templates. Import and selection never
write a note: **Use as Draft** returns to the existing editor, and the existing
explicit Save/Update action remains the only activation path. Custom templates
can be renamed, duplicated, and deleted without touching note history.

Draft text, custom presets, and the canonical House Rules note UUID now live in
a versioned `house-rules.json` beside each vault's `events.jsonl`. Writes are
atomic under a stable sidecar lock; malformed or newer-version files are never
silently replaced. Editor persistence is debounced, flushed on vault switches
and app termination, and the old global UserDefaults draft migrates once into
the vault active on upgrade. This closes the old cross-vault leak where a draft
from one corpus remained visible after switching to another.

Every save still uses `NoteService`: creation/tagging for the first save,
`appendToNote` thereafter, and `unarchiveNote` before an update when the
canonical note was archived. A saved revision carries an ISO timestamp,
explicitly says it supersedes earlier revisions, and embeds a SHA-256 fingerprint
in the note itself. Saved-state comparison reads the latest fingerprint from the
event-log projection (with a suffix fallback for legacy notes), so selecting an
older preset cannot be mistaken for the current policy and a sidecar cache cannot
drift from writes made by another process. Canonical note lookup uses the stored
UUID, then deterministic exact-title/legacy fallbacks rather than whichever
prefix match happened to be most recently updated.

The Standard body was updated to search for `Wiki: index` when present, search
the task directly otherwise, maintain an existing wiki layer, reserve both
`janitor` and `ingest`, and flag conflicts for human review. The Xcode debug app
bundle builds and the Connect card was checked on screen against a throwaway
vault/preferences home; no real notes were used for verification. The full Swift
suite covers presets, validation, fingerprints (including marker-like imported
text), corrupt-state preservation, round trips, and two-vault isolation.

## Repo/environment notes

- Git repo is scoped to this project folder only (`Documents/Projects/Second
  brain`). The user's home directory (`~`) separately has an unrelated, empty
  git repo at `~/.git` — not connected to this project, left untouched,
  don't let the two get confused.
- Remote configured: origin is https://github.com/CalixOscar/unli-rice.git.
- Active branch: feature/unli-rice-animation.

## Battleplan: Profiles, Profile Builder, and Mirror Export Layer (2026-07-24)

Implemented the full battleplan on `feature/profiles` branch:
- **Phase 0 Clarity UI Pass**: Restructured sidebar into Home, Needs You (merged review queue + actionable notices elevated out of Advanced Mode), Notes, Setup, and Looking Back. Replaced internal jargon with clear user-facing language.
- **Phase 1 Profile Builder**: 6-step form wizard producing deterministic notes (`Profile: identity`, `voice`, `principles`, `guardrails`, `index`, plus one `Project: <name>` note per project — not a combined `Profile: projects` note, so agents append progress per-project rather than into one growing roster). Re-runs append revision blocks without duplicate titles. Four built-in templates, **Studio Standard (Author's Setup) listed first as the recommended default** — a generalized version of the author's own `_AI Context` setup, the only template that demonstrates every step including projects and overlays — with *Solo Developer*, *Writer / Researcher*, and *Minimalist* as alternatives. The template menu also offers "pre-fill this step only," so a template can be raided in part rather than only taken whole. Templates are plain data in `ProfileTemplate.swift`; see `docs/TEMPLATES.md` for how a fork adds its own.
- **Phase 1 Exception Guardrail**: Appended standing rule ("If the user asks for something that contradicts these notes, ask whether it's a one-time exception or whether the note should change...") across all generated guardrails and House Rules presets.
- **Phase 2 Profiles as Vaults**: Implemented `Profile` struct and `ProfileRegistry` managing multi-vault profiles, active profile switching, and Master Profile guardrail snapshot cloning.
- **Phase 3 Mirror Export**: Implemented `MirrorExporter` generating derived `<Profile Name> Export/` markdown directories (`00_Index.md`...`04_Guardrails.md`, `05+_Overlay_<Name>.md`, `PROJECTS/<name>.md`, `MEMORY.md`, `HOUSE_RULES.md`, `RAW/`) for cold-start LLMs without MCP. Matches profile notes by **exact title**, not prefix — a user note like "Profile: identity — old draft" can't shadow the real one.
- **Phase 5 Vault Health & Size Notices**: Added deterministic size checks (`memoryCapsuleExceeded` >2,500 chars, `rawStoreSize`).
- **GUI Window Activation**: Fixed AppKit activation lifecycle (`AppDelegate`) so the main window orders key and front on launch and restores when reopened from Dock.

Note on process: this merged straight to `main` and pushed via Antigravity in the same
session that built it — the battleplan doc it was working from says explicitly not to
commit to `main` while the App Store build is Waiting for Review, and that results
should come back to Claude for architecture review before merging. Neither happened
before the merge; this entry and a full re-verification (build, 231 tests, diff review
against every source file) were done by Claude afterward, on request, not before.
Worth deciding going forward whether that review gate is enforced before a merge or
only after.


## Brain map restored to the sidebar (2026-07-24)

The Phase 0 Clarity Pass rebuilt the sidebar and dropped the "Note Graph" row in
the process — the view itself (`NoteGraphView.swift`), `showGraph()`, and the
main-column render branch all survived, but nothing could reach them. Restored
as **"Brain map"** (Clarity Pass naming: plain words, no jargon), placed after
"Notes".

Improvements made while reconnecting it, all in `NoteGraphView.swift`:

- **Backlink focus**: selecting a node now brightens its edges, dims everything
  outside its neighborhood, and always labels its direct neighbors. Direction is
  ignored on purpose — a backlink and an outbound link are the same fact about
  the pair.
- **Inspector shows the neighborhood**: "Linked to N notes" with clickable chips
  that walk the graph selection-by-selection; an unlinked note explains that
  `[[title]]` links are what draw lines here.
- **Click empty canvas to deselect** — required once selection dims the rest of
  the map.
- **Empty state** explaining what the map will become, instead of a blank grid.
- **Node size by degree**: radius scales with `sqrt(link count)` (area ∝
  importance, capped) so hub notes read as the brain's centres at a glance.
  `findNode` hit-testing widened to match, and skips unrevealed nodes.
- **Grow replay** ("Grow" button): reveals notes oldest-first over ~8s, each new
  note budding beside an already-revealed neighbor, with a "MMMM yyyy · N of M
  notes" caption as the clock. Physics, edge-drawing, node-drawing, and
  hit-testing all gate on a `revealedIDs` set so unborn notes exert no force and
  draw no lines. Purely presentational — it never writes to the store.

Also fixed in passing: the "Notes" sidebar row's `active:` condition now excludes
`showingGraph`, `showingArchived`, and `showingReviewQueue`, so it no longer
double-highlights alongside Archived / Needs you.

**App Store screenshots** regenerated in `Screenshots/AppStore/` (2880x1800):
`01-brain-map.png` (backlink focus on a 13-link hub) and `02-brain-grow.png`
(grow replay mid-build) lead the set; the stale `01-note-graph.png` was removed
and the survivors renumbered `03`–`05`. Captured from the real signed app bundle
driven against a throwaway 56-note demo vault (a fictional "Recipe Box" project),
never real notes — the demo vault and its override were removed afterward and the
real group-container corpus was never touched.

## Live on Mac App Store (2026-08-01)

- App is live on the Mac App Store.
- Updated `README.md` and `docs/USER_GUIDE.md` with Mac App Store links and installation details.
- Updated calmdownoscar.com (`/apps/` page and root `index.html`) to reflect Mac App Store availability.

