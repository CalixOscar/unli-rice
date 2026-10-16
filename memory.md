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

**Status:** On branch `chore/plan-high-build-low` off `main` (the repo is
**public**: `github.com/CalixOscar/unli-rice`). This pass changed docs and agent
config only, no Swift. App state is unchanged from the last pass: 380 tests, 0
failures, 2 skipped (verified: `swift test` 2026-09-03; not re-run this pass because
no source changed, and the cloud container has no `swift`). Both targets are set to
**1.2 (6)**. **Neither has been archived or uploaded.** The App Store install is
still Mac **1.1 (4)**.
**Task:** The founder changed the pipeline to **plan high, build low**. Claude and
Codex both plan on their best models and build with cheaper ones: Claude through
`.claude/agents/builder.md` (Sonnet) and `builder-light.md` (Haiku), Codex through a
smaller Codex model. Antigravity leaves the pipeline. Whichever tool didn't plan a
feature writes its pre-mortem and a new **post-mortem**, both in
`docs/dialogue/<slug>.md`, the Claude-Codex bridge. Decision recorded in
`PROJECT_NOTES.md` § "Plan high, build low". Still unreleased from earlier passes:
the sidebar lag fix `51ffb83` (never watched in the running app), plus `46da148`,
`958d9fd`, `1b01fb3`, `92be76e`, `37b4258`.
**Files touched:** `CLAUDE.md` (the "What Claude does here" section rewritten);
`AGENTS.md` (new "How work moves" section, and the note-contract pointer no longer
says swarm); `.claude/agents/builder.md`, `.claude/agents/builder-light.md` (new);
`docs/dialogue/README.md` (new); `.gitignore` (`.claude/agents/` is now
tracked, the rest of `.claude/` is still ignored); `PROJECT_NOTES.md` (one
appended section);
`memory.md`.
**Next step:** (1) The founder updates the vault's `_AI Context/04_Guardrails.md`.
This session could not reach the vault, so the "tool roles" and "pipeline"
sections there still describe the five-stage swarm pipeline, **and the vault wins
over this repo until that changes.** The replacement text was drafted in the
session. If it is lost, rebuild it from `PROJECT_NOTES.md` § "Plan high, build low"
and `docs/dialogue/README.md`. Then re-run `install-studio-hooks.sh` if any script
changed. (2) Add a `build` profile with a smaller model to `~/.codex/config.toml` on
the Mac. (3) Carried over: watch the sidebar in the running app before archiving
(step 2 of `docs/PLAN-sidebar-pane-switch-lag.md` if it still lags), then the
founder archives and uploads both targets. `_AI Context/07_Prelaunch_Post_Mortem.md`
has still not been run before distribution.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable, so git
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
**Left by:** Claude Opus 5.5 2026-10-16

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
