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

**Status:** On `codex/project-garden`. G1/G1R/G1P accepted: the completed ProjectGarden core suite independently passes 22 tests, zero failures (`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build --filter ProjectGardenTests`, 2026-10-19). Native UI is not yet implemented. Baseline full suite was 383 tests, 2 skipped, zero failures. No release or version change.
**Task:** Build the native Garden quick overview per `docs/PLAN-project-garden.md`; Claude pre-mortem is settled. The core is an in-memory report over existing folder grants, notes and optional repository snapshots.
**Files touched:** `Sources/UnliRiceCore/ProjectGarden.swift`, `Tests/UnliRiceCoreTests/ProjectGardenTests.swift`, `docs/PLAN-project-garden.md`, `memory.md`, `PROJECT_NOTES.md`.
**Next step:** Dispatch G2 to the build profile, review the native UI diff, independently build/test, regenerate Xcode, run isolated UI QA, and obtain Claude's approved post-mortem.
**Gotchas:** Both builder runs verified gpt-reserve / medium. G1R left broader boundaries under-tested; planner-owned G1P settled the remaining source ownership decisions and added coverage, now 22 tests. Do not double-count a note when joining providers. Snapshot next-step date belongs to its snapshot even alongside live Git. Live vault tools/reads remain unavailable. Use disposable vault/agent settings and an isolated app ID for UI QA. No push/main merge/upload/version bump in scope.
**Left by:** Codex 2026-10-19

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
The House Rules gallery is More → "What your AI should always do". The editable draft
is More → Setup & Tools → House Rules → Edit; the gallery preview is read-only.
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
