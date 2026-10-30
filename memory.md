<!-- MEMORY CONTRACT — this file, not the vault, is what binds you.
     memory.md holds CURRENT WORKING STATE ONLY, capped at 32,000 characters
     (~8,000 tokens) and enforced by Scripts/lint-memory.sh in pre-commit.

     * The six fields below are atomic: Status, Task, Files touched, Next step,
       Gotchas, Left by — in that order, no repeats, **Left by:** carries a
       YYYY-MM-DD date. They describe ONE moment in time. Update all six or none;
       changing one in isolation produces a file that contradicts itself in
       adjacent lines, which reads as current and is worse than a stale file.
     * No dated headings. Nothing here is a log. Finished work moves to
       PROJECT_NOTES.md; design detail goes to docs/ and is referenced by path.
     * A claim carries its own evidence or is marked unverified:
       "296 tests, zero failures (verified: swift test 2026-09-02)" or "(unverified)".
     * Checkpoint as you go. Commit and update these fields at every
       meaningfully-complete sub-step, not at the end of the session — a
       usage-limit cutoff ends a session with no warning.
     * If this file and the repo disagree, the repo wins. Check against
       `git log -10` and `git status` before building on anything here.
     * Using the `unlirice` MCP tools rather than reading about them? Read
       AGENTS.md as well — title discipline, tagging, flag-vs-resolve.
-->

# Unli Rice — Working Memory

**Status:** Mac 1.4 (9) **submitted for App Review** 2026-10-29 at the founder's explicit request; App Store Connect showed "1.4 Waiting for Review" that day (not rechecked since). On `claude/studio-redesign`: S1, S2, S4 and **S5 (the Studio tab) are now merged** — 515 tests, 0 failed, 2 skipped; `xcodegen generate` and the Xcode Debug build succeeded (verified independently 2026-10-30, not just the builder's pasted output). Per `docs/BUILD-studio-redesign-HANDOFF.md` (founder, 2026-10-30: "I am tired of copy pasting"), **Claude Code is now planner AND build driver** — Codex is used only as the CLI builder per step (`codex -p build`), never as a copy-paste relay, and later as the post-mortem reviewer. Nothing here merges to `main` until 1.4 resolves.
**Task:** Studio redesign, Phase A. Next is **S6, the Garden crate** (plan §2.5): `SleeveBackView`, `GardenExpandedView`, swapping the `.projects` route from `ProjectsPane()` to `GardenExpandedView()`, Copy prompt and Reduce Motion. Per the handoff's loop, write a `§2.5a exact changes` section (files, types, properties, symbols, sizes, palette tokens, `file:line` checked against the current tip) before handing it to a Codex builder — every builder stop so far came from a plan that left a choice open. Then S7 (Guardrails & Grounding), S8 (QA matrix, needs the founder's eyes), S9 (`docs/USER_GUIDE.md` sync), S10 (`PROJECT_NOTES.md`/`memory.md`, Codex post-mortem). Phase B (native Idea Clinic) stays blocked on a shared `clinic.json` on the website.
**Files touched:** `Sources/UnliRice/AppStore.swift` (four stored properties), `Sources/UnliRice/AppStore+Studio.swift` (new), `Sources/UnliRice/Studio/StudioView.swift`, `Sources/UnliRice/Studio/StudioToolbar.swift` (back button), `Sources/UnliRice/Studio/StudioDeck.swift` (new), `Sources/UnliRice/Studio/StudioColor.swift` (new), `Sources/UnliRice/Studio/BuildGateLights.swift` (new), `Sources/UnliRice/Studio/GardenCrateView.swift` (new, placeholder), `Sources/UnliRice/Studio/BranchesDeck.swift` (new), `Sources/UnliRice/Studio/NotesDeck.swift` (new), `docs/BUILD-studio-redesign-S5-REPORT.md`, `docs/PLAN-studio-redesign.md` (Layout correction, §2.3a/§2.4a settled earlier), `memory.md`.
**Next step:** Write plan §2.5a, checked against `claude/studio-redesign` tip `946e28b`. Cut `codex/studio-S6` from `origin/claude/studio-redesign`, hand it to a Codex builder with the §7-style handoff, review the diff and rerun tests/build myself, merge `--no-ff`, push, update this file and the plan's `**Stage:**` line again. For 1.4: wait for App Review; on approval merge and push the website branch `claude/unlirice-1.4`, release if manual release is set; on rejection read the reason first. Next Mac build number is 10.

**Gotchas:** **S5's two review stops were both about layout, not logic:** a builder had put `minHeight: 300`/`220` on the deck container and deck content, and the plan requires decks to size to content with only the 320pt branch graph and 180pt notes ring fixed — removing those three `minHeight` modifiers was the whole fix (now in plan §2.4a "Layout correction"). A fourth cited item, a 7×7pt legend-dot `.frame`, was **not** a height constraint and didn't need changing — read what a stop actually names before extending a fix to it. The Xcode-built debug `.app` (from `xcodegen generate` + `xcodebuild`) shares the App Store build's bundle id (`com.calmdownoscar.unlirice`) and writes `profiles.json` into its App Group container, which the sandbox refuses (`NSPOSIXErrorDomain Code=1`) — harmless and expected, not a crash; this is why memory previously said to run the unsigned `swift build` binary (`/tmp/unlirice-spm-build/debug/UnliRiceApp` with `UNLIRICE_DATA_PATH` set) instead of the Xcode `.app`, for anything beyond a build check. Orca Computer Use needs Accessibility permission granted to "Orca Computer Use" in System Settings; it was not granted in this session, so no screenshot of the running debug build was taken — check `orca computer permissions --json` before assuming it's available. Never toggle "Keep working with the window closed" in a debug build: it registers a real login item. Garden's native QA (Codex, 2026-10-19) is partly covered now: Projects opened and switched segments in the walk. `Screenshots/AppStore-Mac-2026-09-03/` filenames do not match their contents (`02-setup-tools.png` is All Notes, `03-map.png` is the Repos graph); check before citing one. **INTENT-008 (shared spec) exists only on Codex's local branch `codex/shared-spec` on the Mac**; it is not on GitHub. INTENT-009 overlaps it; reconcile the two before planning either (INTENT-009 open question 6). The build-gate rule in `AGENTS.md` is new; the vault's `04_Guardrails.md` was not updated and wins where they disagree until it is.
**To-dos:** none this checkpoint.
**Left by:** Claude Code 2026-10-30
## Earlier branch follow-ups

The previous session's handoff (not revalidated in this session) left: restart Claude sessions for bridge changes; the older shipped-guardrails post-mortem; founder decision on pushing/merging chore/plan-high-build-low and its relationship with local main; committing vault changes; first two builder-model observations; and watching the sidebar before a release. These are separate from Garden and remain deferred.

## Build and release reference

**Every bridge run is told to run the project's build/tests**, even a
one-line brief; a cheap model will try. Keep briefs explicit about what *not* to do.
**The bridge prompt says "implement all tasks" in the file it writes**, so a review
brief must say "write one file, change nothing else". The bridge now refuses a missing
`planFileName` or one outside `docs/`. **A builder's pasted test output is not evidence:** `builder-light` misnamed a case in
its pasted smoke output on 2026-10-17. Rerun it yourself. **The bridge smoke test takes about a minute** (four 2 s timeouts run to
their 10 s / 15 s cleanup deadlines), and it reads the real `~/.codex/build*.config.toml`. **Codex 0.163 reads a profile only from `~/.codex/<name>.config.toml`**;
`[profiles.*]` in `config.toml` is ignored, and `-p` works only on runtime commands
(`exec`, not `doctor`). **Build with `--scratch-path /tmp/unlirice-spm-build`.** The in-tree
`.build` fails codesign ("resource fork, Finder information, or similar detritus") in
this iCloud folder; `Scripts/make-app.sh` (release) still works.
**A development-signed build cannot open the App Store build's app group container**,
so the `dist/` app shows "The House Rules state file is unavailable" and cannot see the
real vault, and the `unlirice` MCP reads the App Store copy's data, not the build under
test. To test UI that writes, run the unsigned debug binary against a throwaway vault:
`UNLIRICE_DATA_PATH=<scratch>/events.jsonl /tmp/unlirice-spm-build/debug/UnliRiceApp`.
The House Rules gallery is the sidebar row "What your AI should always do". The editable
draft is Setup › AI Tools → House Rules → Edit (`ConnectView.swift`); the gallery preview is read-only.
Built-in presets cannot be edited, so edits live in `draftText`, never in
`customPresets`. The app is sandboxed: `Process`/`NSTask` is unavailable, so git
state is read by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/`
directly, and every "fix" the UI offers is copied text, never an action. Do
NOT pass `.skipsHiddenFiles` to an enumerator under `.git` — it is itself
hidden and yields nothing. Security-scoped bookmarks are bound to the signing
identity, so re-signing invalidates every folder grant. **Adding a file under
`Sources/` requires `xcodegen generate`** — `swift test` globs sources and
passes while Xcode fails; `.xcodeproj` is gitignored so the regeneration is
local-only and never arrives via `git pull`. **App Store Connect can be ahead
of `project.yml`:** before this session's bump, ASC's TestFlight already had
Capture build **5** validated (uploaded 2026-08-13) while `project.yml` still
said `CURRENT_PROJECT_VERSION "4"` for both targets — something incremented
and uploaded a Capture build without committing the number back. Check ASC's
actual last-uploaded build per target before ever setting
`CURRENT_PROJECT_VERSION`; don't trust `project.yml` alone. `/Applications/Unli
Rice.app` is the **App Store install** (`_MASReceipt`, was v1.1) — the shipped
product, not a stale build; `dist/` is the local one. The eight Xcode schemes
are distinct targets from `project.yml`, not duplicate apps. `deleteCapture`
purges `events.jsonl` via `TrashService`, so "no destructive delete" is true of
the Mac's note tools but **not** of the phone. `Sources/UnliRiceCapture/
Resources/Assets 2.xcassets` is still a stray duplicate, left for the founder
to delete. **This file's Next step went stale and cost real time:** it still
said "commit the `project.yml` bump" after `92be76e` had committed it, and a
session was spent re-deriving that. Check `git log -10` before acting on
anything here. macOS screenshot filenames contain a narrow no-break space
(U+202F) before `AM`/`PM`, so a normal space in a shell path silently fails as
"No such file" — glob them (`*10.32.22*`) rather than typing the name. Plans dated before
2026-10-16 say "the swarm builds it": read that as the planner's builder models.
The `builder` subagents load only when Claude Code starts in the repo root.

## Open hypotheses

<!-- Live guesses about a current problem, and what would confirm or kill each one.
     Delete an entry the moment it is settled — the answer belongs in
     PROJECT_NOTES.md's Decisions Log, not here. -->

- Sidebar pane-switching lag ("click it four times"): hypothesized cause is the
  three blurred `GeometryReader` circles re-rendering on every `@Published`
  write from `closeAllPanes()`. The fix for exactly that is now **applied**
  (`51ffb83`, `BackgroundBlobs` + `.drawingGroup()`), so the hypothesis is
  testable but **still untested** — nobody has watched the running app. Confirms
  if single clicks now land reliably; kills if the lag persists, which points at
  the 17 `@Published` writes themselves rather than the cost of each redraw.
  Delete this entry once someone has actually clicked the sidebar.

## Active constraints

<!-- Things that would change today's design decisions and are not obvious from
     the code. Not project background — that is PROJECT_NOTES.md. -->

- **Locked architecture decisions are not up for revisiting** without an explicit founder
  decision: the append-only JSON-Lines event log is the source of truth, `Note` is a rebuilt
  projection, there is no destructive delete (only reversible `archive_note`), and
  structural changes are propose-only — the janitor may tag and flag but never apply. See
  `PROJECT_NOTES.md` § "Locked-in architecture decisions".
- The app is shipped on the Mac App Store, so anything on this branch is a submission
  candidate and the pre-launch gate (`_AI Context/07_Prelaunch_Post_Mortem.md`) applies
  before it goes out.
- **The public guide and the app's own copy are now expected to agree.** The guide at
  `calmdownoscar.com/unlirice/user_guide.html` was audited against the code, so a string
  changed in the app without changing the guide re-opens the divergence that
  `docs/PLAN-copy-that-overstates.md` exists to close. Changing either means checking the
  other.
- **The Mirror folder is bidirectional, in one narrow way.** Exported files are
  regenerated copies and edits to them are lost, but `Notes for Unli Rice/` is a drop box
  that `RoutineDriver` ingests on every tick (`RoutineDriver.swift:164`). "The folder is
  read-only" is wrong; "a tool can add a note but not edit one" is right.
- **The widget build (B1–B6) had no swarm and no Codex review of the code**, by founder
  instruction on 2026-09-25 ("just build it"). The plan itself was pre-mortemed; the
  implementation was checked only by its author's tests and builds.
- `docs/PLAN-note-contract.md` is a settled stage-2 plan that has not been built yet.
- `docs/IOS_CAPTURE_RELEASE.md` §1.6 ("Decide iPad, deliberately") is **resolved**:
  keep `TARGETED_DEVICE_FAMILY: "1,2"`. The doc itself still poses it as an open
  question with a "drop to 1" recommendation — that text is now stale and should be
  updated to match, but hasn't been edited yet.
- The AI-todo feature (`docs/PLAN-ai-todo-actions.md`) is built and independently
  verified, but it still went to the swarm without a Codex pre-mortem. Verification
  caught no bugs, but it did not re-litigate the design calls in the plan's §5 — those
  are still unreviewed judgement, not settled fact, even though the code behind them
  works. The hook's Python fold of `events.jsonl` duplicates `Projector.swift` in a
  second language; the agreement test (`StudioTodoTests.swift`) is real and passes, but
  it will not catch a *new* `EventKind` added later without someone remembering to
  extend `KNOWN_EVENT_KINDS` in the Python file too.
