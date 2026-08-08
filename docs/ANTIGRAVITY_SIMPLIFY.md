# Battleplan: make Unli Rice a one-button app

**Audience:** Google Antigravity, executing a defined plan.
**Authored by:** Claude Code, 2026-08-08, at the founder's request.
**Relationship to other plans:** This is now the **primary** plan.
`docs/ANTIGRAVITY_FOLDER_FIRST.md` is not cancelled — its folder work becomes
item 3 here, and that doc keeps the detailed spec. Read this one first for
ordering and intent; read that one for the folder mechanics.
**Branch:** continue on `feature/folder-first` (there is already uncommitted
work there — `Sources/unlirice-cli/`, plus modifications to `MirrorExporter`,
`RoutineDriver`, `ConnectView`, `AppStore`, `AgentSettings`, `project.yml`).
Do not start a fresh branch and strand it.
**Authorization note:** `_AI Context/04_Guardrails.md` scopes Antigravity to
first-look ideation by default. The founder's explicit request in this session
is the one-time exemption for this initiative, same precedent as
`docs/ANTIGRAVITY_BATTLEPLAN.md` (2026-07-24).
**Status:** every file/line reference verified against source on 2026-08-08.

---

## 1. The problem, stated plainly

The founder's words: *"Right now the app is like opening Power BI for someone
who doesn't know what Excel is."*

That is accurate and here is the measurement. On first launch the app seeds
two notes and opens **Setup**. What is then on screen:

- Sidebar: Home, Needs you, Notes, Brain map, Setup, Looking back, plus an
  "Export Notes…" menu (`ContentView.swift:64-162`) — and three more rows if
  Advanced Mode is on
- Setup: five tabs (`SetupView.swift:10-18`)
- The default tab, AI Tools: five connector rows each with a Copy button, an
  "Add a tool…" button, a House Rules card with Choose Template / Edit / Save
  / Reset, and a Storage Location card with two more buttons
  (`ConnectView.swift`)

**More than twenty controls, eleven destinations, and zero delivered value.**
Every one of them is a decision the user has no basis to make yet. The
Profile Builder behind one of those tabs is a further six-step form.

And the surface is not merely confusing, it is unsafe: **"Switch Store…"**
sits on the default first-run screen. It re-points the entire app at another
folder, and `EventStore.init` creates a fresh empty log wherever it is
pointed. This machine currently has **four** `events.jsonl` files — the live
one with 135 notes, plus an orphan at `~/Documents/events.jsonl` holding
**389 notes** last written 2026-08-07. That is the documented failure mode
(`AppStore+Autopilot.swift:286-318` has a whole warning dialog about it)
happening in practice, to the app's own author.

## 2. The principle

**Nothing appears until it has a reason to.** The number of things on screen
should scale with what the *user* has, not with what the *app* can do.

This is not a new principle for this project — it is `docs/USER_GUIDE.md`'s
fourth promise ("Invisible by default… like checking a security camera, not
feeding a pet") applied to the interface itself rather than only to the
background work. The app currently honours that promise in what it *does* and
violates it in what it *shows*.

## 3. Three states, and that is all

### State 1 — Nothing connected (what every new user sees)

**One screen. No sidebar. One question.**

> ### Which AI do you use?
> [ Claude ]  [ ChatGPT ]  [ Cursor ]  [ Something else ]

Pick one → **one** instruction, written for that tool, with a live status dot
underneath that flips to ✓ on its own when the tool actually connects. The
data for that already exists and is already loaded:
`recordContextDelivery` fires on every `initialize`
(`unlirice-mcp/main.swift:64`) into `AppStore.connectionActivities`
(`AppStore.swift:83`).

Nothing else is on screen. No tabs, no House Rules, no storage path, no
sidebar, no profile wizard.

The branch per answer:

| Answer | What they get |
| --- | --- |
| Claude / Cursor | The config block + the file to put it in + "restart it" — one instruction, not a catalog of five |
| ChatGPT | Skip MCP entirely → the folder (item 3) or the clipboard button (item 4). ChatGPT cannot read local files; do not pretend otherwise |
| Something else | Today's connector table, unchanged. This is the escape hatch for people who know what they want |

**This one screen replaces the entire current first-run experience.**

### State 2 — Connected, no notes yet

> ### ✓ Claude is connected.
> Try asking it: *"Remember that I prefer short answers."*

Then the note appears in the app. That round trip **is** the product, and
right now nothing in the app tells the user to perform it. This screen exists
only until the first agent-authored note arrives, then it is gone forever.

### State 3 — Working

Home becomes the security camera it was always meant to be: *"Memory is
working — 135 notes, last written by Claude 4 minutes ago."*

Sidebar is **two rows**: **Home** and **Notes**. Everything else moves behind
a single **More** row.

## 4. What moves, and why

| Today | Becomes | Reason |
| --- | --- | --- |
| Profile Builder (6-step wizard) | **Deleted from the beginner path.** The connected AI interviews the user and writes `Profile: identity` etc. itself | The wizard asks a stranger to describe themselves in forms. An AI is *already connected* and is better at this. It also matches the locked-in principle that reasoning lives in the connected agent, not the app. Keep the wizard behind More for people who want the forms |
| House Rules card (4 buttons, explicit Save) | **On by default**, Standard Memory preset, no ceremony | A beginner has no basis to author standing instructions. Presets already exist (`HouseRulesPreset.swift`); pick one and move on. Editing lives behind More |
| Mirror Export tab | Not a tab — it is **what the ChatGPT answer routes to** in State 1 | It is a delivery path, not a feature to configure |
| "What Runs on Its Own" (2 switches + autonomy slider) | Behind More, defaults unchanged | Pure machinery. The current defaults are already conservative |
| Storage Location / **Switch Store…** | **Behind More, Advanced only** | Safety. Four orphaned vaults on this machine is the evidence. It should not be two clicks from first launch |
| Profiles / multi-vault | Behind More | Nobody needs a second memory on day one |
| Brain map | Behind More (or a toggle inside Notes) | It is a browsing toy occupying a top-level slot |
| Looking back | Behind More | It announces itself via a notice when a period ends — it does not need a permanent row |
| Export Notes… menu | Behind More | — |
| "Needs you" | Stays, but **only appears when the count is > 0** | An always-visible row reading zero is noise |

## 5. Vocabulary

Rename to what a stranger would call the thing. Internal type names stay
unchanged — this is GUI copy only.

- "House Rules" → **"What your AI should always do"**
- "Mirror Export" → **"The folder your AI can read"**
- "Profiles" → **"Separate memories"**
- "Brain map" → **"Map"**
- "Looking back" → **"Your year so far"**
- "Needs you" → keep; it is already plain
- Never show the string "MCP" in State 1 or 2. In State 3 it may appear as
  "connection" with MCP in parentheses

## 6. Hard constraints

- **No engine changes in items 1–2.** This is presentation and routing.
  `NoteService`, `IngestRunner`, `JanitorRunner`, the event log, and every
  permission boundary stay exactly as they are.
- **Nothing is removed, only relocated.** Every existing screen stays
  reachable behind **More**. This is a shipped App Store app with real users;
  a feature someone relies on must not vanish in an update.
- **No new capability for machines.** `IngestRunner` stays
  `{created, appended, tagged}`; `JanitorRunner` stays `{tagged, flagged}`.
  Tests assert these — keep them honest.
- **No delete, anywhere, still.**
- **Concierge voice** for all new copy: calm, short, no hype, no emoji spam
  (`_AI Context/02`). Match `Onboarding.swift`'s existing `welcomeBody` tone.
- **Advanced Mode must still reveal everything.** It is the contract with
  existing users.

## 7. Items, in order

**Item 1 — The one-question first run.** ~2 days.
State 1 + State 2 above. New view, plus routing in `AppStore` so an
unconnected vault lands here instead of `SetupView`. The live ✓ is the part
that matters most — build it first and confirm it flips against a real
client before styling anything.

**Item 2 — Collapse the sidebar to Home / Notes / More.** ~1.5 days.
`ContentView.swift:64-162`. Note the existing `active:` conditions are long
boolean chains of `showingX` flags; collapsing the sidebar is a good moment
to replace those with a single enum, but **do that as its own commit** so a
routing regression is bisectable separately from the visual change.

**Item 3 — The folder.** ~3 days.
Full spec in `docs/ANTIGRAVITY_FOLDER_FIRST.md` §3. Unchanged, except it is
now reached from State 1's ChatGPT branch rather than from a Setup tab. Its
sub-items still apply: real location, derived/inbox split, ingest wiring,
`READ ME FIRST.md`, regeneration on the routine tick.

**Item 4 — "Copy context" button.** ~2 hours.
`docs/ANTIGRAVITY_FOLDER_FIRST.md` §5. The best ChatGPT path; also the State 1
ChatGPT branch's lighter alternative to the folder.

**Item 5 — AI-led profile.** ~0.5 day.
Add to the default House Rules preset: at first session, ask the user a few
questions about themselves and write `Profile: identity` / `voice` /
`principles` / `guardrails`. Pure text — no code. Keep the wizard behind More.

**Item 6 — `unlirice` CLI.** ~1 day. Partly built already
(`Sources/unlirice-cli/` is untracked on this branch and a binary exists in
DerivedData). Power users only; finish it after 1–5.

**Item 7 — `unlirice project init`.** ~1–2 days. Founder-facing. Last.

## 8. Explicit non-goals

- **Do not delete any existing screen.** Relocation only.
- **Do not change defaults for automation.** They are already conservative.
- **Do not add a menu-bar item or Finder extension.**
- **Do not touch signing/release settings** in `project.yml` beyond what a
  new target strictly requires.
- **Do not build a vault-merge tool** for the four orphaned logs found on this
  machine. That is a real problem but it is the founder's data-recovery
  decision, not a feature — flag it, do not automate it.

## 9. The measure of success

A person who has never heard of MCP installs the app, sees **one question**,
answers it, follows **one instruction**, and watches a note they dictated to
their AI appear in the app. No tabs, no wizard, no config vocabulary, nothing
named after the machinery.

Twenty-plus controls on first launch → **one**.

Bring results back to the founder → Claude for review before merging to
`main`. Update `PROJECT_NOTES.md` as each item lands — dated and terse.

---

# Round 2 — Home became the new junk drawer

**Added 2026-08-08 after reviewing commit `fb8eec9`.**

Round 1 landed and the structural work is good: `FirstRunView.swift`,
`MoreView.swift`, the sidebar collapsed to Home / Notes / More, the CLI, the
folder. Keep all of it.

**But the sidebar's contents moved onto Home rather than going away.**
`HomeView.swift` now renders six stacked sections plus a four-button toolbar
(`HomeView.swift:21-39`). The founder's verdict on seeing it: still
overwhelming. That is the correct verdict — relocation is not simplification.

## R2.1 — The app never states its purpose. Fix this first.

Home's subtitle is "What Unli Rice is doing for you right now"
(`HomeView.swift:16`) — a status report. **Nothing anywhere in the app says
what problem it solves.** A stranger can read the whole screen and not learn
what the product is for.

Ship this copy, permanently, at the top of Home — above the status card, not
inside it:

> **One memory your AI tools share.**
> Tell something to Claude, and ChatGPT knows it too.

And in the First Run view and the More → About screen, the longer form:

> Every AI conversation starts from zero. You explain how you work to Claude.
> You explain it again to ChatGPT. Next week you explain it to Claude again,
> because it forgot.
>
> Unli Rice is one memory all of them read and write.

This is not decoration. It is the highest-value change in this round — it
costs nothing and it is the only thing on screen that answers "why do I have
this app."

## R2.2 — Home is exactly three blocks

Delete everything else from `HomeView`. Nothing is removed from the app —
each item below names where it goes.

**Block 1 — What this is.** The two-line statement from R2.1. Always present,
never changes, no controls.

**Block 2 — Is it working, and the one action.**

Replace `statusCard`'s subtitle (`HomeView.swift:178-180`). Current text is
"135 notes stored · Default Profile active · 6 client interactions recorded"
— three internal metrics and zero benefit. "Client interactions recorded" is
telemetry language, not a sentence a person would say.

Say who is connected and when they last wrote:

> ● **Working** — Claude and Codex share this memory.
> Last write: Claude, 4 minutes ago.

Both facts are already available: client names from
`store.connectionActivities`, last write from the newest event's `source` and
`timestamp`. Below it, **one** button: **Copy memory for ChatGPT**. That is
the only action a user takes from Home with any regularity.

**Block 3 — What happened.**

Keep `recentActivitySection` but change its source. It currently shows
notices — the screenshot's only entry is a five-day-old retrospective
announcement, which is not activity. Show the last few **note writes**
instead, from `transactionLog`:

> Claude added "Prefers short answers" — 4m ago
> Codex appended to "Project: Unli Rice" — 2h ago

This is the app proving it works, which is the entire job of Home.

**Plus, conditionally:** the existing `needsAttentionCard`, which is already
correctly gated on `needsAttentionCount > 0` (`HomeView.swift:28`). Leave it
exactly as is.

## R2.3 — What leaves Home, and where it goes

| Remove from Home | Goes to | Why |
| --- | --- | --- |
| **Instant Memory Capsule** block (`HomeView.swift:113-143`) | More | Caps-lock filename, exposes the internal `Memory: capsule` note-title convention, and its current content is an apology that the note doesn't exist. Most prominent block on the page; nothing actionable in it |
| **"Who You Are (Profile)"** + Launch Profile Builder + Manage Profiles (`HomeView.swift:233+`) | More | Round 1 already specified this move and it didn't happen. It also self-contradicts: "your profile is active" next to a button to build it |
| **New Note** button | The Notes screen | Rare by design — the premise is that the AI writes the notes |
| **Add Folder to Brain Map** | More, **renamed** | It calls `chooseScanRoot()` (`HomeView.swift:65`) — it adds a folder to be *indexed*. It has nothing to do with the Brain Map. Call it "Index a folder" |
| **Open Memory Folder** | More (and fix the bug below) | Occasional, not primary |

Net: Home goes from six sections plus four buttons to **three blocks and one
button**.

## R2.4 — Bug: "Open Memory Folder" opens the old hidden folder

`HomeView.openMirrorFolderInFinder()` (`HomeView.swift:152-157`) recomputes
the legacy path from `store.dataURL` and **ignores `AppStore.exportFolderURL`**
— the relocated-folder property added by this very commit
(`AppStore.swift:207`). So the button opens
`~/Library/Group Containers/group.com.calmdownoscar.unlirice/… Export`, which
is precisely the hidden location item 3 exists to escape.

Use `store.exportFolderURL` when set, and fall back to the legacy path only
when it is nil. Check for the same mistake anywhere else that path is
recomputed by hand rather than read from `AppStore`.

## R2.5 — Vocabulary still leaking

Round 1's rename list was not applied. Still on screen: "Instant Memory
Capsule (MEMORY.MD)", "Brain Map", "Profile", "Default Profile active". Apply
§5 of this document. A filename, a data structure, and an internal note title
should never appear in GUI copy.

## R2.6 — Working order

1. **R2.1** (the purpose copy) — an hour, and it is the thing the founder
   actually asked for. Do it first, on its own commit.
2. **R2.4** (the folder bug) — small and it is a live defect.
3. **R2.2 / R2.3** (cut Home to three blocks) — the bulk.
4. **R2.5** (vocabulary) — fold in as you touch each string.

Same constraints as round 1: nothing is deleted, only relocated; no engine
changes; every screen stays reachable behind More.

---

# Round 3 — Two users, one app

**Added 2026-08-08.**

The founder's framing: a brand-new user needs *a reason to install*. A
seasoned user — someone who builds their own tools — needs *a reason not to
replace this with a file they wrote themselves*. These are different
arguments and the app currently makes neither.

## R3.1 — The gate today is a boolean, and it is in the wrong place

`advancedModeEnabled` (`AppStore.swift:245`) defaults to false and is toggled
from a switch buried at `AutomationView.swift:503`. So depth is all-or-nothing
and the user has to already know it exists to find it. That is backwards: a
beginner cannot discover it, and an expert has to go hunting.

**Replace the boolean with stages the app enters on its own.** Every input is
a fact the app already has — note count, `connectionActivities`, and the
distinct `source` values in the event log. No new state, no new storage, one
computed property.

| Stage | Entered when | What Home shows | What unlocks |
| --- | --- | --- | --- |
| **1. Cold** | Nothing connected | `FirstRunView` — one question | Nothing else exists |
| **2. Connected** | ≥1 client seen, no agent-written note yet | "Try asking it: *remember that I prefer short answers*" | Nothing else |
| **3. Working** | ≥1 agent-authored note | Round 2's three blocks | Notes |
| **4. Multi-tool** | ≥2 distinct non-app sources have written | Adds "who wrote what" to notes | Review queue, provenance, House Rules |
| **5. Builder** | CLI used, or 2nd profile created, or ~200+ notes | Unchanged | CLI docs, `project init`, Trust Center, profiles, shard sync |

**The principle: a capability appears when the user acquires the problem it
solves.** Provenance is noise with one tool connected and essential with two.
The review queue is empty theatre until there are enough notes to have
duplicates. Neither should be visible before then.

Two rules on top:

- **Stages only ever add.** Nothing that has appeared may disappear later,
  even if the triggering condition stops holding. Users rely on what they
  have seen.
- **Keep the manual override.** The existing Advanced Mode toggle survives as
  "show everything" for someone who wants stage 5 on day one — but move it
  somewhere findable (More), not inside the automation pane.

## R3.2 — The new user's reason to install

One sentence, and it has to name the pain rather than the mechanism:

> **Your AI forgets you. Every single conversation.**

Then the turn:

> Unli Rice is one memory all your AI tools read and write. Tell something to
> Claude, and ChatGPT knows it too.

This is the App Store subtitle, the First Run headline, and the top line of
Home (R2.1). Same words in all three places — a person who installs because
of a sentence should see that sentence again when the app opens.

What this deliberately does **not** lead with: MCP, notes, memory capsules,
profiles, event logs, local-first, open source. Every one of those is a
*reason to keep* the app, not a reason to try it.

## R3.3 — The seasoned user's reason to stay

Be honest about the competition: **it is a markdown file they wrote
themselves.** Anyone technical enough to build apps will make a `CLAUDE.md`
or a `memory.md` and point their tools at it. The founder did exactly this —
`_Second Brain`, a `memory.md` capped at 2,500 characters, retired
2026-07-20.

So the app should say what you hit when you try. Every item below is verified
in this codebase, not marketing:

1. **Every write is signed.** Each event carries `source` and `device`
   (`Event.swift`). A markdown file cannot tell you whether Claude or Codex
   wrote that line, or when.
2. **Two agents can write at once without clobbering each other.** The
   projection cursor is a byte offset into an append-only file, so a second
   client's writes arrive as bytes past the cursor
   (`NoteService.swift:29-38`). Concurrent writes to a shared markdown file
   destroy each other.
3. **Nothing can be destroyed.** There is no delete method for an agent to
   call anywhere in the codebase; archiving is soft and reversible
   (`NoteService.swift:94-107`). An agent that decides to "tidy up" your
   `memory.md` truncates it, and nothing brings it back.
4. **Full history per note**, returned as the actual events rather than a
   synthetic diff (`NoteService.swift:197`).
5. **A maintenance pass that proposes and never applies** — the janitor may
   only tag and flag; structural changes queue for a human
   (`JanitorProposal.swift`).
6. **Ingestion** of Claude session logs and nominated folders, idempotent by
   content digest (`IngestRunner.swift`).
7. **Three access channels for the same memory** — MCP, the folder, and the
   CLI — so a tool that speaks none of one still works.

Ship this as a page in **More → "Why not just a text file?"**, and reuse it
verbatim as the second half of the App Store description. It is the strongest
copy this product has and it currently exists nowhere.

## R3.4 — Effort and order

1. **R3.2 copy** — an hour. Same sentence in three places. Do it with R2.1;
   they are the same commit's worth of work.
2. **R3.3 page** — half a day, almost all writing. High value, near-zero risk.
3. **R3.1 stages** — ~1.5 days. It is a computed property plus visibility
   conditions on screens that all already exist. Do **not** build new screens
   for this; if a stage has nothing to unlock, the stage is wrong.

Constraints unchanged: nothing deleted, only gated; no engine changes; every
screen reachable via the manual override.

---

# Round 4 — Nothing is actually being captured

**Added 2026-08-08, after the founder asked why a full working session did not
appear in the app.**

Home showed "codex and claude-code share this memory" while the newest real
write was Antigravity's CLI test from nine hours earlier. An entire Claude
Code session — an investigation, three battleplans, a code review — left no
trace. Three verified causes:

1. **The connected agent never wrote.** The MCP server delivered its
   `instructions` at handshake (`unlirice-mcp/main.swift:78`) telling the
   model to read the vault. The model read it and never called `create_note`
   or `append_to_note` once. Nothing in the system requires or prompts a
   write; it depends entirely on the model volunteering.
2. **Routines are off.** `agent.json` has `routinesEnabled: false`, so ingest
   and the janitor never run unattended.
3. **The Claude session importer has no folder.** `claudeProjectsPath` and
   `claudeProjectsBookmark` are both null. Meanwhile the transcripts are
   sitting on disk at `~/.claude/projects/<slugified-cwd>/<uuid>.jsonl`.

`ClaudeSessionImporter`'s own doc comment calls it *"the highest-signal
pipeline and the reason it's the one built first."* It is built, it works, and
it is pointed at nothing.

## R4.1 — Wire up the session importer

**The fix is not a button.** Asking the user to capture their own work
violates the app's central promise. The work is already on disk; nothing is
reading it.

- **Ask at the right moment.** `FirstRunView` already asks "which AI do you
  use?". When the answer is Claude, offer one follow-up: *"Also index your
  Claude Code sessions? They're already on your Mac."* → `NSOpenPanel` →
  store the app-scope bookmark in `AgentSettings.claudeProjectsBookmark`
  (the field already exists). The sandbox requires a picker for
  `~/.claude/projects`; it cannot be enabled silently.
- **Routines default on for new installs only.** An app whose whole promise
  is "works while you're not looking" ships inert today. Flip the default —
  but **do not change the stored value for existing users**, who may have
  turned it off deliberately.
- **Weekly is too slow.** The Tuesday slot means today's session is invisible
  until next week, which is the complaint that opened this round. Run the
  session importer on the routine tick, like Round 1's inbox.
- **But measure before shipping every-tick.** `discover()` walks the whole
  projects tree and reads each file to count messages and find titles
  (`ClaudeSessionImporter.swift:53+`), and those files run to several MB.
  Add an mtime-based skip so unchanged sessions are not re-read, then measure.
  This project's precedent is `janitor-calibrate` and the projection
  performance work: measure on the real corpus, don't assume.
- **Expect a large first run.** That directory holds months of sessions. The
  existing per-run note budget handles it (leftovers defer to the next run,
  by design — `IngestConfig.noteBudget`), but confirm the budget in use on
  this path is the small one, not the 10,000 default.

## R4.2 — Stop reporting a handshake as participation

Home currently says two connected tools "share this memory." They don't —
they *connected*. `recordContextDelivery` fires on `initialize`
(`unlirice-mcp/main.swift:64`), and the comment there explains why: so Trust
Center doesn't claim a client "never read a note" when it was handed the vault
and simply hasn't called a tool yet. Defensible in Trust Center. On Home,
rendered as "share this memory," it is a false claim.

- Show the two facts separately: **who is connected**, and **the last actual
  write**. The honest line is already on that card in small type.
- **A tool that connected but never wrote is a diagnostic, not a success.** It
  means the House Rules are not landing. `MCPConnectionActivity` already
  distinguishes the two — `TrustCenterView.swift:239` renders "connected …,
  never read a note" — so no new data is needed. Surface it: *"Claude Code
  has connected 6 times but never written a note."* That sentence is more
  useful than anything else on the screen.

## R4.3 — This failure is not in the eval suite. Add it.

All eight existing cases test *response quality when the agent acts*:
`silent_constraint_drop`, `invented_entity`, `state_desync`, `cold_start`,
`unconventional_input`, `tone_break`, `fallback_parity`, `cost_blowout`.
**None covers an agent that reads the vault, is instructed to write back, and
silently doesn't.** That is the failure that just occurred in production use.

- Add `evals/cases/unli-009.yaml`, `mode: no_write_back`, asserting that a
  session which materially changed the user's project produces at least one
  `create_note` or `append_to_note`.
- The assertion is deterministic — the harness already records `tool_calls`,
  so this needs no judge model, like nine of the existing eleven assertions.
- **The fixture already exists.** The 2026-08-08 session transcript is at
  `~/.claude/projects/-Users-calmdownoscar-Documents-Projects-Unli-Rice/`.
  Convert it into `evals/fixtures/unli-009.json`. It is a *failing* fixture,
  which makes it more valuable than a passing one — it is the first case in
  this suite with `origin: observed` rather than `predicted`.

This also retires the standing eval-gate warning: eight cases with no recorded
transcript becomes seven predicted plus one real.

## R4.4 — Order

1. **R4.2** — copy and a diagnostic line, no new data. Hours.
2. **R4.3** — the case file and the fixture conversion. Half a day, and it
   closes a gate that has been open since 2026-08-03.
3. **R4.1** — the picker, the default flip, the tick scheduling, the mtime
   skip, and the measurement. ~1 day, and it is the one that makes the app
   actually capture anything.

Constraints unchanged: no engine changes beyond the importer's scheduling and
mtime skip; no new write capability; nothing deleted.

---

# Round 5 — Show the memory, explain the silence

**Added 2026-08-08. The founder, on the rebuilt Home: "I still don't get this
page. What does it mean?"**

Round 2 made Home shorter. It did not make it meaningful. Every line on it is
telemetry — which processes connected, when the last database write happened,
a log of recent operations. **The memory itself, which is the entire product,
appears nowhere on the screen.**

## R5.1 — Lead with what the AI knows

Home's largest element should be the actual content of the memory, in plain
readable prose:

> **What your AI knows about you**
>
> You're a solo app developer at calmdownoscar. You prefer short answers, no
> hype, no emoji. You're working on Unli Rice, Nuptia, and ClearSpace.

Assemble it from notes that already exist — `Profile: identity`,
`Profile: voice`, `Profile: principles`, and `Memory: capsule` — the same
sources `MirrorExporter` already reads (`MirrorExporter.swift:48-99`). If
those notes don't exist yet, say so plainly and link to the one action that
creates them; do not render an empty box.

Then **one status line in plain words**, no client names and no timestamps:

> Claude reads this automatically. ChatGPT needs a copy-paste.

Then **one button**: Copy memory for ChatGPT.

Someone should read that page in three seconds and know what they have and
what to do. Client names, versions, and connection counts move to More.

## R5.2 — The event log stays, but it has to be legible and explain itself

The founder wants it kept. It is the app's evidence that it is real. Two
changes.

**Plain language, and only knowledge-changing events.** Today it reads
`Ingest tagged "Note" with 'document'` and
`Ingest created "Doc: raw/ae1860ffb0c4-AGENTS.md"` — a content hash and a
note literally called "Note". Rules:

- Show `created` and `appended` only. Tagging, untagging, and flagging are
  maintenance, not knowledge — fold them into a single trailing line
  ("plus 4 tidying changes") or drop them.
- Name the thing in human terms: "Indexed **AGENTS.md** from your Projects
  folder", not `Doc: raw/<digest>-AGENTS.md`.
- Say who in the user's vocabulary: "Antigravity added…", "Claude added…",
  "Unli Rice indexed…" — never `ingest`, never `janitor`, which are internal
  source identifiers.

**Explain the gap.** This is the founder's specific ask: why is the newest
entry nine hours old rather than now? The app can answer this from state it
already holds, and it must not guess:

| Detected condition | Line to show |
| --- | --- |
| `routinesEnabled == false` | "Background collecting is off, so nothing is being added on its own." + **Turn it on** |
| `claudeProjectsBookmark == nil` | "Your Claude Code sessions aren't being indexed — they're on this Mac but Unli Rice can't see them yet." + **Choose folder** |
| A client has connected but never called a write tool | "Claude has connected but hasn't written anything. Your standing instructions may not be reaching it." + **Review them** |
| None of the above | "Nothing new since then." — and nothing else |

**That last row matters.** If the user simply hasn't worked in nine hours,
nine hours is the correct answer and the app must say so calmly. Only show a
diagnosis when there is an actual detected cause. Manufacturing concern out of
an ordinary quiet period is exactly the urgency-bait the studio guardrails
forbid.

## R5.3 — "Unknown MCP client" is alarming, and it shouldn't be

The founder's reaction — *"that's worrying"* — is the correct reaction to that
string, and the string is the app's own fault. It is the fallback at
`unlirice-mcp/main.swift:36`, shown when a client doesn't send `clientInfo`
during the handshake. It reads like an unidentified program touched your data.

Three fixes, in order of value:

1. **Never show the raw fallback.** Say "A tool that didn't identify itself"
   and, next to it, the reassurance that is actually true and provable:
   *this server has no network listener — it is a local process started by a
   program on this Mac that you pointed at Unli Rice.* Nothing remote can
   reach it. That sentence belongs in the UI, not just in `PRIVACY.md`.
2. **Capture something identifying that is definitely available.** The server
   already reads `FileManager.default.currentDirectoryPath`
   (`main.swift:74`), and an MCP server's working directory is the project
   folder its client launched it in. Record it, and render "A tool that didn't
   identify itself — working in `~/Documents/Projects/Unli Rice`". That turns
   an anonymous entry into a recognisable one. *Optional, investigate only:*
   whether the parent process name is obtainable under the helper's sandbox
   profile — if it is, that is better still. Do not ship a guess.
3. **Don't show stale clients on Home at all.** The current entry was last
   seen 2026-08-03 and codex 2026-07-22 — 17 days ago. Home names the two
   least relevant clients while omitting `claude-code`, which connected the
   same day. The full history belongs in More → Trust Center.

## R5.4 — Four defects in the current card

All verified against `connections.json` on 2026-08-08.

1. **The headline picks the wrong clients.** It shows codex (last seen 22 Jul)
   and "Unknown MCP client" (3 Aug) while `claude-code` connected that same
   day at 12:48Z. Whatever the selection rule is, it is not "who is actually
   using this."
2. **"codex has connected 1 time but never written a note" is false.** That
   record carries `lastToolName: "append_to_note"` with
   `lastToolSucceeded: true`. The R4.2 diagnostic is checking the wrong field.
   It is also the most prominent line on the page, in warning colour, and it
   is wrong.
3. **Clients are keyed `name|version`** (`id: "claude-code|2.1.222"`), so
   `claude-code` appears as four separate clients across four updates.
   Collapse by `clientName` for anything user-facing; keep the version detail
   inside Trust Center.
4. **The internal fallback string is user-visible** — see R5.3.

## R5.5 — Order

1. **R5.4 defects** — the false warning first; a wrong claim in warning colour
   is worse than no claim. Hours.
2. **R5.3** — the identity and reassurance copy. Half a day.
3. **R5.2** — legible event log plus the gap diagnosis. ~1 day; the
   diagnosis reads state the app already has.
4. **R5.1** — lead with the memory. ~1 day, and it is the change that makes
   the page mean something.

Constraints unchanged: nothing deleted, only relocated; no new write
capability; no diagnosis shown without a detected cause.
