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

**Status:** On `main`, working tree clean, everything pushed to `origin/main`
(the repo is **public**: `github.com/CalixOscar/unli-rice`). `swift build` clean
(verified 2026-09-03); full `swift test` **not re-run this pass** — the last
green run was 380 tests, 0 failures, 2 skipped (verified: `swift test`
2026-09-03, before this pass's `ContentView.swift` change). `project.yml` is
unchanged this pass and its bump is already committed in `92be76e`:
`MARKETING_VERSION "1.2"` both targets, `CURRENT_PROJECT_VERSION "6"` (Capture)
and `"5"` (Mac) — Mac build 5 is **live on the App Store**; Capture 6 has
**not** been archived or uploaded.
**Task:** Three pieces landed this pass. (1) The sidebar pane-switch lag fix —
the three blurred `GeometryReader` circles moved out of `ContentView.body` into
a standalone `BackgroundBlobs` that reads nothing from `store`, plus
`.drawingGroup()`; the body observes `store`, so those blurs were re-rendering
on all ~19 `@Published` writes a single sidebar click produces (`51ffb83`).
**Builds clean but has not been watched in the running app** — the founder had
believed this was already fixed; it never was. What *was* fixed earlier is a
different sidebar bug, `e67f29f` (`closeAllPanes` never cleared `showingRepos`).
(2) `docs/PLAN-sidebar-pane-switch-lag.md` records the mechanism, the step that
landed, and the `@Published enum Pane` collapse deliberately not attempted
(`16ae1d9`). (3) One current Mac screenshot set, 8 panes, recaptured same-day at
3024×1898 with a 2880×1800 set for App Store Connect; three blurs applied — the
founder's first name and his son's name on Home, and one unreleased project name
on To do (`01a1c3a`, `f9e0ac1`). The other project names in that shot were
checked against `origin/main` first and are already public there.
Everything from the previous pass (`46da148` toast, `958d9fd` rating prompt,
`1b01fb3` iPad copy, `92be76e` version bump, `37b4258` screenshots) is committed
and still **unreleased** — it ships whenever the founder next archives.
**Files touched:** `Sources/UnliRice/ContentView.swift` (`BackgroundBlobs`, the
blur moved out of the observing body); `docs/PLAN-sidebar-pane-switch-lag.md`
(new); `Screenshots/AppStore-Mac-2026-09-03/` (8 shots plus the
`padded-2880x1800/` set, replacing the 4-shot set); `memory.md`. No test file
and no `project.yml` change this pass.
**Next step:** Watch the sidebar in the running app and decide whether
`51ffb83` actually fixed it — build, click To do / Repos / Notes / Home in
sequence, and see whether single clicks land. That observation has never been
made; every claim about this lag so far, including the fix, is code-reading
only. If it still lags, the remaining suspect is the 17 `@Published` `Bool`s
themselves (`closeAllPanes()`, `AppStore.swift:1094`) wanting a single
`@Published enum Pane` — step 2 of `docs/PLAN-sidebar-pane-switch-lag.md`,
swarm-shaped, not a quick fix. Also re-run `swift test` before any archive: the
last green run predates the `ContentView.swift` change. Then the founder
archives and uploads both targets themselves; this session did not and will
not. `_AI Context/07_Prelaunch_Post_Mortem.md` still has not been run before
any future distribution action — carried over, not touched.
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
"No such file" — glob them (`*10.32.22*`) rather than typing the name.
**Left by:** Claude Opus 5 2026-09-03

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
