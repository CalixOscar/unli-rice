# Can Unli Rice work fully without MCP?

Design/feasibility investigation, 2026-08-08. No code written. Every claim
below was checked against the source in this repo on this date; where the
brief's premise turned out to be wrong, that's called out inline.

---

## 0. What the code actually says (corrections to the brief)

Five things worth fixing before any of the recommendations make sense.

1. **`ToolDispatcher` is a pure translation layer, exactly as hoped.**
   `Sources/unlirice-mcp/ToolDispatcher.swift` is 159 lines and does nothing
   but map 14 tool names onto `NoteService` public methods 1:1, then JSON-encode
   the result. Its own doc comment says so. The MCP server holds no logic a CLI
   would have to re-derive.

2. **A shipped CLI would not need `swift run`, and would reach App Store
   users.** `MCPServerEntry.forInstalledApp` (`MCP/MCPTarget.swift:155`) points
   MCP clients at `Unli Rice.app/Contents/MacOS/unlirice-mcp` — a signed helper
   binary inside the bundle, embedded by the `Embed sandboxed helpers`
   postCompileScript in `project.yml:160`. Spawning a bundled helper from
   outside the app is therefore *already the production path*, proven in the
   shipped build. A `unlirice` CLI is a fifth executable target installed
   alongside it.

3. **`unlirice-agent` is already a CLI.** It parses `--status`, `--install`,
   `--uninstall`, `--ingest`, `--janitor`, `--preview-ingest`, resolves the
   shared security-scoped bookmark out of `AgentSettings`, and opens the right
   `EventStore` (`Sources/unlirice-agent/main.swift:35-120`). That bootstrapping
   — the genuinely fiddly part of a sandboxed CLI — exists and works.

4. **Mirror Export is only regenerated when a human opens the tab.**
   `MirrorExporter.exportMirror` has exactly one caller in the whole codebase:
   `MirrorExportView.swift:115`, from `.onAppear` and the *Export Now* button.
   The routine tick never touches it. So the brief's "Mirror Export already
   regenerates its files from live vault state" is true only in the sense that
   pressing the button regenerates them. Left alone, the folder is a snapshot
   of whenever you last looked at it.

5. **There is no `PROJECT_NOTES.md` template anywhere.** Profile Builder emits
   `Project: <name>` notes with a Status / Overview / Log body
   (`ProfileBuilder.swift:158-174`) — that's all. The Handoff-field shape the
   studio guardrails depend on (`**Status:** / **Task:** / **Files touched:** /
   **Next step:** / **Gotchas:** / **Left by:**`) exists only as prose in
   `_AI Context/04_Guardrails.md`. Any `project init` has to *author* that
   template first; the file I/O is the easy half.

Also: there is no `MenuBarExtra` or `NSStatusItem` in `Sources/` — a menu bar
trigger is a new surface, not an addition to an existing one.

---

## 1. Does the "auto-injected instructions" equivalence hold? (brief §5)

**Not today. It could, with two small fixes — but it doesn't change the
conclusion, because writes were always the real constraint.**

The MCP half is confirmed live, not theoretically: this investigation's own
session received `unlirice-mcp`'s `instructions` string verbatim
(`unlirice-mcp/main.swift:78`) with no tool call and no action from the model.
That mechanism works exactly as the brief describes.

The file half has two gaps:

- **Staleness.** Per §0.4, the export's `CLAUDE.md`/`AGENTS.md` (written at
  `MirrorExporter.swift:142-145`, with near-identical wording to the MCP
  instructions) are only rewritten when someone opens the Mirror Export tab.
  MCP's instructions are computed at every `initialize`.
- **Location — the bigger one.** The export lands at
  `<vault parent>/<Profile> Export/`. Coding tools auto-load `CLAUDE.md` /
  `AGENTS.md` from the working directory and its ancestors. A session opened in
  `~/Documents/Projects/Foo` never sees the export's `AGENTS.md` at all. It is
  auto-loaded by nothing unless the user opens the export folder *as* their
  project, which is not how anyone works.

And the equivalence is per-tool, not universal: `CLAUDE.md`/`AGENTS.md`
auto-loading is a convention of terminal/IDE coding agents. ChatGPT web and
Antigravity's chat surface don't read arbitrary local files at all — for those,
neither MCP instructions nor a convention file arrives on its own, which is
precisely what brief §4 exists to solve.

So the narrowing the brief hoped for is real but arrives by a different route:
**reads are already solved by Mirror Export** (modulo freshness), and the only
thing that genuinely requires a protocol or a shell is **writes**.

### Recommendation: MCP stays primary, CLI added as a peer write channel

Not "CLI-first, MCP-optional". Reasons, in order of weight:

- MCP gives the model a *typed schema* it discovers automatically. A CLI gives
  it a binary it has to be told about, with argument shapes it can get wrong.
  For the write path — where a malformed call means a bad note in a permanent
  append-only log — the schema is worth keeping as the default.
- The auto-injected `instructions` field has no file equivalent for non-coding
  surfaces, and only a fixable-but-currently-broken one for coding surfaces.
- "Exposed over MCP" is the product's positioning and it's accurate. Adding a
  CLI doesn't undermine it; it *strengthens* the "no external dependencies,
  local-first" claim, because a shell command is the one interface with no
  protocol, no client, and no version negotiation. The README line becomes
  "exposed over MCP, with a plain CLI for everything else" — strictly more
  compatible, same identity.

Dropping MCP would be trading a working, shipped, auto-discovering channel for
one that needs every tool told about it by hand. There is no version of that
which is an improvement.

---

## 2. CLI feasibility (brief §1)

**Thin wrapper. Rough estimate: ~1 day including tests and packaging.**

What exists: `NoteService` (the sole write surface, in dependency-free
`UnliRiceCore`), `ToolDispatcher` as a worked example of the exact mapping, and
`unlirice-agent`'s argument parsing + sandbox-bookmark bootstrap to copy.

What's new:
- A `Sources/unlirice-cli` target — 8 lines in `Package.swift`, ~12 in
  `project.yml`, plus two `install -m 755` lines in the embed script.
- Argument parsing. No dependency available (`swift-argument-parser` would
  break the no-dependencies rule), so hand-rolled, matching `unlirice-agent`'s
  existing style. This is the bulk of the work and it's mechanical.
- Output shaping: human-readable by default, `--json` for machines. The JSON
  path is `JSONRPC.plain(...)` — already written.

Surface, mirroring `ToolCatalog` so nothing new is exposed:
`unlirice note add|append|get|list|search`, `unlirice tag|untag`,
`unlirice archive|unarchive`, `unlirice flag|reviews|resolve`,
`unlirice log`. Same 14 capabilities, same absence of delete.

Two real caveats:
- **Sandbox.** The CLI inherits `UnliRiceHelper.entitlements`
  (app-sandbox + app-group + app-scope bookmarks + user-selected read-write).
  Reading and writing the vault is fine — that's the app-group container or a
  bookmarked folder, exactly what `unlirice-mcp` does. Touching anything else
  on disk is not (see §4).
- **Discovery.** A model won't use a binary it doesn't know about. The CLI has
  to be named in House Rules / the Mirror Export `AGENTS.md` stamp, or it may
  as well not exist. That's a content change, not a code one — but it is
  load-bearing.

---

## 3. Store-and-forward `INBOX.md` (brief §2)

**Not a lower-effort alternative. Defer it.**

It reads as cheap because ingest exists, but ingest is the wrong shape:

- `IngestRunner` is keyed on `resource.key` and creates *one note per file*,
  appending a "Revised" block when the digest changes
  (`IngestRunner.swift:137-159`). An `INBOX.md` would become a single
  ever-growing note, not N notes. Wrong semantics.
- `LocalFileImporter` has `minimumBytes: 200` — a one-line inbox entry isn't
  even discovered.
- It only runs over folders the user nominated as scan roots, on the Tuesday
  slot, if routines are on. A drop zone that ingests on Tuesdays is not a drop
  zone.
- Nothing is destructive here by design, so the inbox can't be emptied after
  ingest. It needs a consumed-byte cursor — doable (it's the same idea as
  `EventStoreCursor`), but it's new code with new state, not reuse.

So it needs its own `ResourceImporter`, its own cursor, its own provenance
source, and its own "create only" boundary. Call it 1–2 days — comparable to
the CLI, for a strictly weaker channel: free text with no note id, so
`append_to_note`, tagging, and flagging are all impossible through it.

The decisive argument: **almost nobody is served by it.** A tool that can write
a local file can also run a shell command; a tool that can do neither (ChatGPT
web) can't write `INBOX.md` either. The only real beneficiary is a hypothetical
agent with file-write but no terminal. Revisit if Antigravity specifically
turns out to be that — otherwise it's effort spent on an empty set.

---

## 4. `unlirice project init <name>` (brief §3) — design only

**Blocked as a pure CLI command by the sandbox. Make it a GUI-owned action
with a CLI front door.**

`~/Documents/Projects/<Name>/` is outside the app-group container. A sandboxed
helper cannot create it without `user-selected.read-write` being satisfied by
an actual picker, and a CLI has no picker. The app already solves this exact
problem twice (vault folder, scan roots) with app-scope bookmarks.

Proposed shape:

1. **One-time**: Setup gains a "Projects folder" picker. NSOpenPanel →
   app-scope bookmark stored in `AgentSettings`, same as `scanRoots`.
2. **`unlirice project init <Name>`** resolves that bookmark. If absent, it
   fails with "open Unli Rice → Setup and choose your Projects folder first"
   rather than guessing. Creates:
   - `~/Documents/Projects/<Name>/` (refuses if it exists — never overwrite)
   - `AGENTS.md` + `CLAUDE.md` stamped from the current `Profile: guardrails`
     note, with a generated-on date and a "regenerate with `unlirice project
     sync <Name>`" line
   - `PROJECT_NOTES.md` from a **new** template that has to be authored (§0.5)
     — Overview / Handoff (all six fixed fields, empty) / Decisions Log /
     Session Log
   - `git init`
3. **Registers `Project: <Name>`** in the vault via `NoteService.createNote`,
   with the folder path in the body, so the Mirror Export `PROJECTS/` slice
   picks it up on the next regeneration for free.

Two boundaries this has to respect and one is non-negotiable:
- **Human-triggered only. Never in the routine tick.** Creating a folder
  outside the vault is categorically more than any button in the app does
  today, and `docs/USER_GUIDE.md §2.5`'s promise is that nothing unattended
  exceeds the buttons. A background job that mints directories in `~/Documents`
  would break that promise outright.
- It also directly matches the studio guardrail "never create a new top-level
  project folder by hand without confirming with the founder" — the command
  *is* the confirmation, and it replaces the tool the guardrails note as
  missing since `brain new` was retired.

Rough estimate: 1–2 days, and most of it is writing the `PROJECT_NOTES.md`
template well enough that it doesn't need rewriting by hand every time.

---

## 5. Manual per-project injection trigger (brief §4)

Three options, then a pick.

**A — Menu bar item.** `MenuBarExtra` with "Copy context for ▸ <project>".
Fastest to reach from inside ChatGPT — no app switch to a window. Costs a new
persistent UI surface and status-item lifecycle code. ~1 day. The tension with
"invisible by default" is arguable both ways: it's small, but it's always
visible, which the app currently never is.

**B — Finder Quick Action on a project folder.** Right-click
`~/Documents/Projects/Foo` → "Copy Unli Rice context". Zero UI added to the
app, and the trigger sits where the work is. Costs a new app-extension target
in `project.yml`, its own entitlements, and a new item in the App Store review
surface for a convenience feature. ~1–2 days plus review risk.

**C — In-app button.** On the existing Mirror Export tab (or Home): "Copy
context for…" → project picker → clipboard gets `Profile: guardrails` +
`Project: <name>` + `MEMORY.md` capsule. Reuses `NSPasteboard`, which the app
already drives for MCP config blocks and cleanup prompts
(`PROJECT_NOTES.md:1217`). No new target, no new entitlement, no new review
surface. ~2 hours.

**Pick: C.** It's a button on a screen that already exists, doing exactly what
a human just asked and nothing more — which is the "checking a security camera,
not feeding a pet" test, passed literally. Ship C; if reaching the window
proves to be the friction rather than the copying, A is a cheap follow-up on
top of the same clipboard code.

Worth noting: once the CLI ships, `unlirice context <project> | pbcopy` comes
free and covers the founder's own case without any UI at all. C is for
everyone else.

---

## 6. Beginner-friendliness — a different problem with a different answer

**These two goals do not want the same fix, and the CLI is the wrong tool for
the beginner one.**

What a new user actually sees today, verified: first launch seeds two guide
notes and opens Setup (`Onboarding.swift:37`, USER_GUIDE §1). The AI Tools tab
says "Copy a configuration block, paste it into your tool yourself, and restart
that tool" (`ConnectView.swift:50`), and every row repeats "Unli Rice never
opens or edits this file. Merge the copied block manually, keeping any servers
already there." That refusal is a deliberate, well-reasoned decision
(PROJECT_NOTES, "The rules around writing someone else's config") and I'm not
proposing changing it. But for a non-technical user it means: find
`~/Library/Application Support/Claude/claude_desktop_config.json`, open it in
something, merge JSON by hand without breaking what's there, restart the app.
That is a real cliff, and it is the *first* thing the app asks of them.

The sharpest defect isn't the paste — it's the silence afterward.
**`ConnectView` has no success state.** It never reads `ConnectionActivity`,
despite `unlirice-mcp` already recording a `recordContextDelivery` on every
`initialize` (`main.swift:64`). That data surfaces in exactly two places: a
health signal on Home, and the Trust Center client list — and Trust Center is
gated behind **advanced mode** (USER_GUIDE §6). So a beginner who pastes
correctly and a beginner who mangles the JSON see the identical screen, and the
proof that it worked is behind a toggle they have no reason to find.

Would a CLI help them? No. `unlirice note add "..."` is strictly harder than
pasting JSON for someone who doesn't open a terminal. The CLI is a founder and
power-user fix. Saying so plainly is better than pretending one project serves
both.

**Ship these regardless of anything above, in this order:**

1. **Per-row connection status in `ConnectView`** — "✓ Claude Desktop, last
   seen 2 minutes ago" / "not seen yet". The data already exists and is already
   loaded into `AppStore.connectionActivities`; this is plumbing, not a
   feature. ~half a day, and it's the highest-leverage change in this whole
   document for non-founder users.
2. **A "nothing has connected yet" empty state** on that same screen with the
   two things that are actually wrong 90% of the time (didn't restart the tool;
   pasted into the wrong file), plus a "Check again" button.
3. **Promote Mirror Export in onboarding.** This is the real beginner story and
   it is *already built*: a user with ChatGPT and no MCP client can attach a
   folder and get value in one step, with no config file anywhere. Today it's
   tab 4 of 5 in Setup, framed as a fallback for tools that can't do the real
   thing. It should be offered on first run as a peer path — "connect a tool"
   *or* "just point any AI at this folder."

Item 3 is where the two problems briefly touch: fixing Mirror Export's
freshness (§7, step 1) makes it a better beginner on-ramp *and* a better
cross-LLM read channel. That's the only overlap. Everything else diverges.

---

## 7. Recommended order

| # | Work | Rough effort | Serves |
| --- | --- | --- | --- |
| 1 | `ConnectView` connection status + empty state | ~0.5 day | Beginners |
| 2 | Regenerate Mirror Export from the routine tick, not just `.onAppear` | ~2 h | Both |
| 3 | "Copy context for…" button (§5 option C) | ~2 h | Founder, some users |
| 4 | `unlirice` CLI, mirroring the 14 MCP tools | ~1 day | Founder, power users |
| 5 | Mirror Export offered as a peer path on first run | ~0.5 day | Beginners |
| 6 | `unlirice project init` + Projects-folder bookmark + `PROJECT_NOTES.md` template | ~1–2 days | Founder |
| — | `INBOX.md` drop zone | deferred | ~nobody, today |

Steps 1–3 are all small, all independently shippable, and two of the three are
plumbing over data and code that already exist. Step 4 is the actual answer to
"can this work without MCP" — and the answer is *yes for reads today, yes for
writes once the CLI ships, with MCP still the better path whenever it's
available.*

**One honest gap:** whether a model reliably reaches for a CLI it was told
about in House Rules — instead of ignoring it the way it might ignore any
prose instruction — is unverified. That is exactly the kind of predicted
failure mode `evals/` exists for, and all eight cases there are still
`origin: predicted` with no recorded transcript. Before building step 4, it's
worth one cheap experiment: put a fake `unlirice` command in House Rules, run a
real Codex session, and record whether it gets called. That's a fixture, not a
guess.
