<!-- MEMORY CONTRACT — this file, not the vault, is what binds you.
     memory.md holds CURRENT WORKING STATE ONLY, capped at 32,000 characters
     (~8,000 tokens) and enforced by Scripts/lint-memory.sh in pre-commit.

     * The seven fields below are atomic: Status, Task, Files touched, Next step,
       Gotchas, To-dos, Left by — in that order, no repeats, **Left by:** carries a
       YYYY-MM-DD date. They describe ONE moment in time. Update all seven or none;
       changing one in isolation produces a file that contradicts itself in
       adjacent lines, which reads as current and is worse than a stale file.
     * **To-dos:** at every checkpoint, file what you deferred and close what you
       finished in the Unli Rice to-do list (notes tagged `todo`), then record it in
       that field: "filed 2 (...); closed 1 (...)" or "none this checkpoint". The
       procedure is in AGENTS.md § "At every handoff".
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

**Status:** On **`feature/todo-widget`** (off `main` at `6918f2d`), local only, not pushed.
`main` was fast-forwarded to `6918f2d` on 2026-09-19 (the copy fix + widget docs), also not
pushed. Swarm dispatch 1 landed `900398d`..`eda7af1`: Part A (shared core + tests), Part C
(MCP instructions), and the B0 spike widget. 414 tests, 0 failures, 2 skipped (verified:
`swift test --scratch-path /tmp/unlirice-spm` 2026-09-19). `xcodebuild` of `UnliRice` with
the embedded `UnliRiceWidget.appex` succeeded, signed team `22SNGN5JYD` (verified 2026-09-19,
`/tmp/unlirice-b0`). Both 1.2 builds still unarchived; App Store install is 1.1 (4).
**Task:** The to-do widget, `docs/PLAN-todo-widget.md` (settled). Build is split in two
because B0 is a human-run gate. Dispatch 1 is done and verified against `git diff` and my own
build and test run; its report (`docs/BUILD-todo-widget-1-REPORT.md`) misdescribes some of
its own code (source names, subtitle format), but the code matches the plan.
**Files touched:** Swarm: `Sources/UnliRiceCore/{StudioTodo,TodoWording,TodoHandoff,TodoLink,
TodoPrompt,WidgetCorpus,EventStore,Agent/AgentSettings}.swift`, both To Do panes,
`AppStore+TodoPrompt.swift`, `unlirice-mcp/main.swift`, `Sources/UnliRiceWidget/SpikeWidget.swift`,
`UnliRiceWidget.entitlements`, `project.yml`, six new test files. Claude: `memory.md`,
`docs/BUILD-todo-widget-1.md` (moved from the repo root).
**Next step:** **The founder runs B0** (steps in this session's walkthrough, summarised in
plan §4 B0): quit the App Store copy, `open "/tmp/unlirice-b0/Build/Products/Debug/Unli Rice.app"`,
add the "Unli Rice Spike" widget. (a) The default folder must show `Notes: N`. (b) A throwaway
folder chosen **in the test copy**, then a restart: `Notes: 0` or `logMissing` = pass,
`folderFailed` = fail. Claude measures the widget's memory (`footprint`), with 30 MB the stop line.
Then point the test copy back at the default folder. The result picks dispatch 2 (B1–B6) or a
plan revision.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable, so git
state is read by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/`
directly, and every "fix" the UI offers is copied text, never an action. Do
NOT pass `.skipsHiddenFiles` to an enumerator under `.git` — it is itself
hidden and yields nothing. Security-scoped bookmarks are bound to the signing
identity, so re-signing invalidates every folder grant. **`swift test` can fail to codesign the test bundle in this iCloud folder** ("resource fork, Finder information … not allowed"), intermittently: use `swift test --scratch-path /tmp/unlirice-spm`, never a `.build` symlink. **Adding a file under
`Sources/` requires `xcodegen generate`** — `swift test` globs sources and
passes while Xcode fails; `.xcodeproj` is gitignored so the regeneration is
local-only and never arrives via `git pull`. **The sandbox makes `~/Documents`
mean something else:** it resolves inside
`~/Library/Containers/com.calmdownoscar.unlirice/Data/Documents/`, so any copy
naming `~/Documents` as a place the user can visit is wrong for the App Store
build and right for `swift run UnliRiceApp`. **App Store Connect can be ahead of
`project.yml`** — check ASC's actual last-uploaded build per target before ever
setting `CURRENT_PROJECT_VERSION`. `/Applications/Unli Rice.app` is the **App
Store install** (`_MASReceipt`); `dist/` is the local one. `deleteCapture`
purges `events.jsonl` via `TrashService`, so "no destructive delete" is true of
the Mac's note tools but **not** of the phone. `Sources/UnliRiceCapture/
Resources/Assets 2.xcassets` is still a stray duplicate, left for the founder
to delete. **This file's Next step has gone stale before and cost real time** —
check `git log -10` before acting on anything here. macOS screenshot filenames
contain a narrow no-break space (U+202F) before `AM`/`PM`, so a normal space in
a shell path silently fails as "No such file" — glob them (`*10.32.22*`).
**Screenshot filenames in `Screenshots/AppStore-Mac-2026-09-03/` do not match
their contents:** `02-setup-tools.png` is All Notes and `03-map.png` is the
Repos branch graph; check before citing one by name. **The Antigravity MCP
bridge takes a bare filename only** — a path in `planFileName` is rejected, so
the brief lands at the repo root and has to be moved into `docs/` afterwards;
and it creates its result JSON **empty at dispatch**, so "the file exists" is
not a completion signal — wait on the `agy` pid instead.
**To-dos:** None filed or closed: this session's Unli Rice MCP connection reported 0 notes,
so it is not the real store. Would have filed: "Add the to-do field to the UnliDisk and
Butter Smooth notes" (unlidisk, butter smooth); "Commit the linter script updates waiting in
Architecturally, Butter Smooth and UnliDisk" (those three).
**Left by:** Claude Opus 5 2026-09-19

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
- **The app may disagree with itself about where the Unli Rice folder is.**
  `PROJECT_NOTES.md` records `openMirrorFolderInFinder()` being pointed at
  `~/Documents/Unli Rice/` and away from "hidden `Group Containers`", while the
  Connect card displays the sandbox container path. Under the App Sandbox those
  may be the same place or two different places depending on how each resolves.
  Confirms if the Finder button opens a different folder than the path shown on
  the Connect screen; kills if they land in the same directory. One launch
  settles it. If they differ it is a real bug, not a copy problem.

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
- **`docs/PLAN-copy-that-overstates.md` also went to the swarm without a Codex
  pre-mortem**, by explicit founder instruction on 2026-09-07. Two of its three open
  questions were answered by the swarm and one was resolved in the brief; none were
  reviewed by a second tool. Same caveat as the AI-todo feature above: the code works,
  the judgement in it is unreviewed.
