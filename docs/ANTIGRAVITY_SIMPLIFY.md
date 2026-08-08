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
