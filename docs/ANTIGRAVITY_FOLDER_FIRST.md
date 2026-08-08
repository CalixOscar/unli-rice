# Battleplan: the Unli Rice folder — making the app usable without touching a config file

**Audience:** Google Antigravity, executing a defined plan (not first-look
ideation this time — see Authorization note).
**Authored by:** Claude Code, 2026-08-08, at the founder's request.
**Supersedes:** the earlier draft of this plan that led with a CLI. The
founder's direction is explicit: **always do what is easier for the user.**
That reorders everything — the folder work moved to first, the CLI moved to
second-to-last, and one item disappeared entirely because a better version of
it fell out of the new design.
**Branch:** `feature/folder-first` off `main`. The app is **live on the Mac
App Store** (shipped 2026-08-01). Do not touch signing, entitlements, or
`project.yml`'s release-facing settings without flagging first. Get it
building and passing `swift test` locally; the founder/Claude review
packaging before anything goes near a real release.
**Authorization note:** `_AI Context/04_Guardrails.md` scopes Antigravity to
first-look ideation by default. The founder's explicit request in this
session is the one-time exemption for this initiative, following the same
precedent as `docs/ANTIGRAVITY_BATTLEPLAN.md` (2026-07-24). The guardrails
note itself is unchanged. Bring results back to Claude for architecture
review before merging to `main`.
**Status of this doc:** a plan derived from a completed investigation
(`docs/MCP_INDEPENDENCE.md` — read it; it has the reasoning this compresses
into tasks). Every file/line reference was verified against the source on
2026-08-08. If the code has moved since, trust the code.

---

## 0. Read these first, in order

1. `docs/MCP_INDEPENDENCE.md` — the investigation. It has the "why" for every
   item below; this document only has the "what."
2. `PROJECT_NOTES.md` — locked-in architecture decisions. Non-negotiable:
   append-only event log, no destructive delete reachable by any agent,
   structural changes are proposed never applied, every write attributed via
   `source`.
3. `AGENTS.md` — how to behave if you connect to the `unlirice` MCP server
   while working on this. Identify as `source: "antigravity"`.

## 1. The problem this fixes

To get value out of Unli Rice today, a user must: find their AI tool's MCP
config file (for Claude Desktop that's
`~/Library/Application Support/Claude/claude_desktop_config.json`), merge a
JSON block into it by hand without breaking whatever's already there, and
restart the tool. If it doesn't work, the app tells them nothing — there is
no success state on the screen where they did the work.

Mirror Export already exists as the zero-config alternative and is a good
feature. **But it writes to a folder nobody can find.** Verified in
`DataLocation.supportDirectory()`: in an App Store build the vault lives in
the app-group container, so the export lands at

```
~/Library/Group Containers/group.com.calmdownoscar.unlirice/<Profile> Export/
```

`~/Library` is hidden by Finder by default. The user cannot browse there,
cannot easily drag those files into a chat, and no coding agent would ever
have that as a working directory. `MirrorExportView`'s "Open in Finder"
button gets them there once; nothing gets them back.

So the single highest-value change in this codebase is not new functionality.
It is **putting an existing feature somewhere a human can reach it**, and
then making it the front door instead of tab 4 of 5 inside Setup.

## 2. Hard constraints (violating any of these fails review)

- **Derived and user-written content must live in separate directories.**
  `MirrorExporter.writeExportFile` overwrites atomically on every
  regeneration (`MirrorExporter.swift:162-166`). If an LLM writes into the
  same directory the exporter regenerates, its work gets clobbered. This is
  the load-bearing structural rule of item 1 — get it wrong and the feature
  destroys user data on a schedule.
- **Derived artifacts stay derived.** Nothing in this codebase reads the
  export folder back as authoritative input. The *inbox* folder is read
  (by ingest), but that is a different directory with a different contract.
- **No new write capability for machines.** `IngestRunner` stays
  `{created, appended, tagged}`; `JanitorRunner` stays `{tagged, flagged}`.
  Tests assert those sets — keep them honest.
- **No delete, anywhere, still.** Ingesting a file never removes it. The
  inbox accumulates; that's correct and matches decision #2.
- **No external dependencies.** `Package.swift` says so on purpose.
- **Sandbox rules are real.** Writing to `~/Documents/Unli Rice/` requires
  `user-selected.read-write` satisfied by an actual picker, then an app-scope
  security bookmark. The app already does exactly this for `scanRoots` and
  the vault folder — read that code before writing new code that duplicates
  it.
- **Per-tool instructions must be verified, not guessed.** `MCPTarget`'s own
  doc comment (`MCP/MCPTarget.swift:63-68`) sets the precedent: targets ship
  only when their format was confirmed against a real config file, because "a
  wrong format produces a config that silently never connects, which is worse
  than not listing the tool." The same standard applies to the folder-access
  instructions in item 1.4 — test each one against the real tool, or don't
  ship that row.

---

## 3. Item 1 — The Unli Rice folder ⭐ *the main event*

**Effort:** ~3 days. **Absorbs** what were previously three separate items
(relocate export, regenerate on tick, promote in onboarding).

### 1.1 — Pick a real location

- Add a folder picker (`NSOpenPanel`, `canCreateDirectories = true`),
  defaulting the suggestion to `~/Documents/Unli Rice/`. Store the result as
  an app-scope security-scoped bookmark in `AgentSettings`, parallel to how
  `scanRoots` bookmarks already work.
- `MirrorExporter.exportMirror` already accepts `customExportDirectory`
  (`MirrorExporter.swift:24`) — that parameter is the seam; use it rather
  than changing the default-path logic.
- **Migration:** an existing user has an export folder in the group
  container. On first run after this ships, offer to move it (copy, don't
  move — same reasoning as `DataLocation.migrateLegacyStoreIfNeeded`, which
  copies precisely so the failure mode is a stale duplicate rather than
  losing the only copy). Leaving the old one behind is acceptable; it's
  derived.

### 1.2 — Split the folder in two

```
~/Documents/Unli Rice/
  READ ME FIRST.md          ← per-tool access instructions (1.4)
  AGENTS.md                 ← already generated today, MirrorExporter.swift:144
  CLAUDE.md                 ← already generated today, MirrorExporter.swift:142
  Context/                  ← DERIVED — regenerated, safe to delete
    00_Index.md … 04_Guardrails.md
    05_Overlay_*.md
    PROJECTS/
    MEMORY.md
    HOUSE_RULES.md
    RAW/
  Notes for Unli Rice/      ← WRITE SIDE — the exporter must never touch this
    (empty on creation, with a short .md explaining what it's for)
```

The existing numbered files move under `Context/`; `AGENTS.md`/`CLAUDE.md`
stay at the top level so coding agents auto-load them when the folder is
opened as a workspace.

### 1.3 — Wire the inbox to ingest

This is the write channel, and it mostly already works. `IngestRunner` does
one note per file, keyed by content digest, revised when the file changes,
and never touches a note it didn't author
(`IngestRunner.swift:100-184`) — exactly the right semantics for "an LLM
wrote a markdown file, it becomes a note."

Three gaps to close:

- `LocalFileImporter`'s `minimumBytes: 200` default
  (`LocalFileImporter.swift:65`) would silently swallow a short note. Pass a
  lower floor **for this importer instance only** — do not change the default
  for user-nominated document folders, where the 200-byte floor is doing
  useful work.
- Auto-nominate `Notes for Unli Rice/` as a scan root when the folder is
  created, via the existing `ScanRoots.adding` logic (it already handles
  overlap correctly — `ScanRoots.swift:36`).
- Ingest currently runs on the scheduled slot only. The inbox needs to be
  picked up promptly or the loop feels broken. Run it on the routine tick
  (every ~5 min when the background agent is installed) rather than the
  weekly slot — **scoped to this one folder**, not a general loosening of the
  ingest schedule.

Also regenerate `Context/` from `RoutineDriver.tick`
(`Schedule/RoutineDriver.swift:106`). Today `MirrorExporter.exportMirror` has
exactly one caller — `MirrorExportView.swift:115`, from `.onAppear` and the
manual button — so the folder is a snapshot of whenever a human last opened
that tab. A folder we're telling users to point their LLM at cannot be stale.

### 1.4 — `READ ME FIRST.md` — the "how does my LLM see this?" guide

This is the part that makes or breaks the feature, and it is **content work,
not code**. Per-tool, and each row ships only once tested against the real
tool:

| Tool | Instruction | Note |
| --- | --- | --- |
| Claude Code | `cd` into the folder, or add it to the project | `AGENTS.md` auto-loads — easiest path of all |
| Cursor / Antigravity | Add folder to workspace | roughly equal to MCP |
| Claude Desktop | Needs the Filesystem MCP server | **be honest: this is another config paste, so the Unli Rice MCP block is the better option here** |
| ChatGPT web | No local file access — upload `Context/` into a Project, re-upload when it changes | manual, but it's the only option; point at item 3's clipboard button as the lighter alternative |

Do not paper over the rows where the folder is *worse* than the MCP paste.
The app's existing voice is calm and honest about tradeoffs; a guide that
oversells this will produce exactly the "silently never connects" outcome
`MCPTarget` warns about.

### 1.5 — Make it the front door

- On first run, present two options with equal weight: **"Create my Unli Rice
  folder"** and **"Connect an AI tool"**. Not tab 4 of 5 buried in Setup.
- Keep the existing Setup tab structure — this is an additional entry point,
  not a restructure.
- Copy stays in the app's concierge voice: calm, short, no hype. Match
  `Onboarding.swift`'s `welcomeBody`/`taggingBody`.

**Acceptance:** on a fresh install, a user who never opens a config file can
create the folder, see their guardrails in `Context/`, drop a `.md` into
`Notes for Unli Rice/`, and watch it appear as a note in the app within one
routine tick. Regeneration must never overwrite anything in the inbox.

---

## 4. Item 2 — "Is it actually working?" feedback

**File:** `Sources/UnliRice/ConnectView.swift`, plus wherever item 1's folder
status lives. **Effort:** ~0.5 day.

Today a user who pastes correctly and one who mangles the JSON see the
identical screen. The data to fix this already exists: `unlirice-mcp` calls
`recordContextDelivery` on every `initialize` (`unlirice-mcp/main.swift:64`)
and `recordToolCall` on every `tools/call` (`main.swift:99`), and
`AppStore.connectionActivities` already loads it (`AppStore.swift:83`,
populated in `AppStore+Trust.swift:21-26`). It surfaces only in
`TrustCenterView` — which is gated behind Advanced Mode.

**Do:**
- Per-row status in `ConnectorRow` (`ConnectView.swift:233`): last-seen
  relative time, or "Not connected yet." Reuse the client-name matching
  already written in `TrustCenterView.swift:227` — don't reinvent it.
- Empty state naming the two things that are actually wrong most of the time
  (tool wasn't restarted; block went in the wrong file), plus a "Check again"
  that re-reads the activity store (a file read — cheap to repeat).
- **Same treatment for the folder**: last regenerated, and how many notes
  have come in from the inbox. Both channels need to answer "did this work?"

## 5. Item 3 — "Copy context for…" button

**File:** `Sources/UnliRice/MirrorExportView.swift`. **Effort:** ~2 hours.

The best path for ChatGPT web, which can't see the folder at all. One click,
always current, no upload.

Assembles `Profile: guardrails` + a chosen `Project: <name>` note +
`Memory: capsule` (if present) into the clipboard with section headers. Find
project notes the way `MirrorExporter.swift:76-88` already does. Use
`NSPasteboard.general` following the pattern already used for MCP config
blocks and cleanup prompts (`PROJECT_NOTES.md:1217`) — no new clipboard
abstraction. A vault with no project notes still works, just omits that
section.

## 6. Item 4 — `unlirice` CLI

**Effort:** ~1 day. **Demoted** — this is a power-user and founder
convenience. It does not help a non-technical user at all; `unlirice note
add "…"` is strictly harder than pasting JSON for someone who doesn't open a
terminal. Build it after items 1–3 have landed.

Full spec in `docs/MCP_INDEPENDENCE.md` §2 and the superseded plan. In short:
new `Sources/unlirice-cli` target depending only on `UnliRiceCore`;
bootstrap copied from `unlirice-agent`'s `--ingest` path
(`unlirice-agent/main.swift:80-99`); one subcommand per `ToolDispatcher`
case (`ToolDispatcher.swift:25-129` is the exhaustive list — mirror exactly,
add nothing); `--source` required on every mutating command; `--json` output
mode reusing `JSONRPC.plain(...)`; hand-rolled argument parsing (no
`swift-argument-parser` — dependencies rule); embedded in the bundle via an
`install -m 755` line alongside the existing ones in `project.yml:160-170`.

**Before starting:** check whether the eval experiment
(`docs/MCP_INDEPENDENCE.md` §7) has been run — a documented CLI named in
House Rules, tested against a real session, transcript recorded into
`evals/fixtures/`. It tests whether a model reliably reaches for a CLI at
all. All eight cases in `evals/` are still `origin: predicted` with no
recorded transcript.

## 7. Item 5 — `unlirice project init`

**Effort:** ~1–2 days, most of it authoring the `PROJECT_NOTES.md` template.
**Last** — founder-facing only.

Full spec in `docs/MCP_INDEPENDENCE.md` §4. Key points: it needs its own
Projects-folder bookmark (the sandbox has no picker available to a CLI); it
**must never run from the scheduled tick** (creating directories in
`~/Documents` unattended would break `docs/USER_GUIDE.md §2.5`'s promise);
there is **no existing `PROJECT_NOTES.md` template anywhere in this repo** —
Profile Builder's `Project:` notes (`ProfileBuilder.swift:158-174`) are a
different, much shorter in-vault shape. The template needs the six fixed
Handoff fields from `_AI Context/04_Guardrails.md`'s "Note hygiene" section;
read that section directly rather than paraphrasing from memory.

---

## 8. Explicit non-goals

- **No `INBOX.md` single-file drop zone.** Superseded — item 1.3's
  one-file-per-note inbox is a strictly better version of the same idea, and
  it needs no new importer, no consumed-byte cursor, and no new state.
- **No menu-bar item or Finder Quick Action.** Item 3's in-app button was
  chosen specifically because it needs no new UI surface, no new entitlement,
  and no new App Store review surface.
- **`project init` never runs unattended.** Restated because it's the
  constraint most likely to get "helpfully" generalized into automation.
- **No changes to `project.yml`'s signing/release settings** beyond what a
  new executable target strictly requires (item 4 only). Anything touching
  `CODE_SIGN_ENTITLEMENTS`, `DEVELOPMENT_TEAM`, or existing bundle
  identifiers is out of scope — flag it, don't change it.
- **No user-facing "evals."** The founder mentioned evals alongside
  guardrails and context notes. `evals/` in this repo is a dev-only Python
  harness that grades recorded agent transcripts — not something that belongs
  in a user's folder. **Assumption made rather than blocking on it:** the
  folder ships guardrails and context notes only. If what was meant was the
  failure-premortem lenses (`docs/failure-premortem.md` /
  `_AI Context/08_AI_Failure_Modes.md`) as *context* for the LLM, that's a
  reasonable addition to `Context/` — but confirm before building it.

## 9. Working order

1. **Item 1** — the folder. Biggest user win; everything else is smaller.
   Land 1.1/1.2 (relocation + split) as one reviewable commit before
   starting 1.3 (ingest wiring), since the directory contract is what
   1.3 depends on.
2. **Item 2** — feedback for both channels. Small, high value.
3. **Item 3** — clipboard button. Small, independent.
4. **Item 4** — CLI. Power users.
5. **Item 5** — `project init`. Founder.

Bring results back to the founder → Claude for architecture review before
merging to `main`. Update `PROJECT_NOTES.md` as each item lands — dated,
terse, per the vault's own "Note hygiene" rules — not one write-up at the
end.
