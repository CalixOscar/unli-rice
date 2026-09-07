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

**Status:** On **`feature/copy-that-overstates`**, three commits ahead of `main`,
**local only — not pushed, not merged**. `main` is at `ddae139` and is pushed
(the repo is **public**: `github.com/CalixOscar/unli-rice`). 380 tests, 0
failures, 2 skipped (verified: `swift build` and `swift test` 2026-09-07, after
the swarm's `cbfa54a`). The sibling site repo `CalmdownOscar` is on `main` and
pushed, four commits, live on `calmdownoscar.com`. Carried unchanged from the
previous pass: **both targets ship as 1.2 (6)** (`MARKETING_VERSION "1.2"`,
`CURRENT_PROJECT_VERSION "6"`), the App Store install is still **1.1 (4)**, and
**neither 1.2 build has been archived or uploaded** — that is the founder's
step, not a session's.
**Task:** A documentation audit that turned into an app fix. Three parts.
(1) The public user guide (`CalmdownOscar:unlirice/user_guide.html`) was audited
claim by claim against `1f49c0f`; **fourteen claims did not survive**, six of
them flatly wrong. Corrected and live (`CalmdownOscar@92a6870`, `d6f02d5`,
`40e4a53`). The worst was the MCP paste instruction: the app copies a *complete*
JSON file including the `mcpServers` wrapper, and the guide said to paste it
inside an existing `mcpServers` object, which nests one inside the other and
fails silently.
(2) The app repo README gained the guide link and three screenshots
(`c4a6b87`, `ddae139`).
(3) **Four of the fourteen were the app's own strings, not the guide's** — the
guide was repeating them faithfully. Planned in
`docs/PLAN-copy-that-overstates.md` (`1c906a9`), dispatched to the Antigravity
swarm, built in `cbfa54a`. Copy and doc comments only; no logic changed.
Verified against `git diff` and a real build rather than the swarm's `SUCCESS`.
**Files touched:** This repo — `PROJECT_NOTES.md` and `memory.md`;
`docs/PLAN-copy-that-overstates.md` and `docs/PLAN-copy-that-overstates-BUILD.md`
(both new); `README.md`; `Screenshots/connect-screen.png` (new);
`Scripts/lint-project-notes.sh` (synced from the vault, `4cc77a6`). Changed by
the swarm in `cbfa54a`: `Sources/UnliRice/TodoPaneView.swift`,
`Sources/UnliRice/ConnectView.swift`, `Sources/UnliRice/AppStore.swift`,
`Sources/UnliRiceCore/StudioTodo.swift`. Sibling repo `CalmdownOscar` —
`unlirice/user_guide.html`. No test file changed; no `Sources/` file added, so
no `xcodegen generate` was needed.
**Next step:** **Watch the To Do pane and the Connect screen in a running
build**, then merge `feature/copy-that-overstates` and push. The one judgement
call nobody has looked at is fix 4's placement: the JSON merge hint is three
sentences of 10.5pt secondary text under every connector row, and the swarm
judged it "fits comfortably" from code, not from looking. If it reads as a wall
of grey, move the two cases into `snippetBlock` (shown after **Copy
Configuration** is pressed) — do *not* shorten the string back into ambiguity,
which is how the original one-liner got written. Still outstanding from the
previous pass and untouched: watch the **sidebar** in the running app to decide
whether `51ffb83` actually fixed the pane-switch lag, and
`_AI Context/07_Prelaunch_Post_Mortem.md` has still not been run before any
future distribution action.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable, so git
state is read by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/`
directly, and every "fix" the UI offers is copied text, never an action. Do
NOT pass `.skipsHiddenFiles` to an enumerator under `.git` — it is itself
hidden and yields nothing. Security-scoped bookmarks are bound to the signing
identity, so re-signing invalidates every folder grant. **Adding a file under
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
**Left by:** Claude Opus 5 2026-09-07

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
