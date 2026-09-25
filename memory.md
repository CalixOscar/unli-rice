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

**Status:** Unli Rice 1.3 (build 7) — the To Do widget plus the plain-language To Do list — is uploaded to TestFlight for internal testing only and not submitted for review; it needs installing from the TestFlight app. Technical: uploaded 2026-09-26 00:31 via `xcodebuild -exportArchive` with `testFlightInternalTestingOnly` (verified: "Upload succeeded"). 1.2 (6) was already uploaded and 1.2 is **approved** at App Store Connect, so the 1.2 train is closed; the founder chose 1.3. On **`feature/todo-widget`**, local only, not pushed, at `826e288`. 431 tests, 0 failures, 2 skipped (verified: `swift test --scratch-path /tmp/unlirice-spm` 2026-09-26). `UnliRice` and `UnliRiceCapture` build (verified: `xcodebuild` Debug 2026-09-26). The widget has not yet been seen drawing real notes (a development-signed copy is refused the app group container; see Gotchas). AI sessions under `~/Documents` now use the installed App Store app's MCP helper, so AI to-dos land in the store the app reads (516 open notes, 6 to-dos, verified via the app's `unlirice-cli` 2026-09-26).
**Task:** The to-do widget, `docs/PLAN-todo-widget.md`: B1–B6 built directly by Claude, not the swarm (founder: "just build it", 2026-09-25), plus plain wording across the To Do list so a non-developer can read it, then a TestFlight build so it can run (founder asked, 2026-09-26). B0 test (b) was skipped by the founder; the widget is fail-closed instead.
**Files touched:** `Sources/UnliRiceWidget/` (TodoWidget, TodoTimelineProvider, MarkTodoDoneIntent; spike removed), `Sources/UnliRiceCore/` (TodoWidgetList, StudioTodo, TodoEmptyState, TodoPrompt), `Sources/UnliRice/` (AppStore+TodoWidget, AppStore, AppStore+TodoPrompt, UnliRiceApp, ContentView, TodoPaneView), `Sources/UnliRiceCapture/TodoView.swift`, `UnliRice-Info.plist`, `UnliRiceWidget-Info.plist`, `project.yml`, `.mcp.json`, tests `TodoWidgetListTests.swift` and `StudioTodoTests.swift`, `memory.md`, `docs/PLAN-todo-widget.md` (build notes).
**Next step:** Founder: install Unli Rice 1.3 from the TestFlight app once Apple has processed it, then add the "To do" widget to your desktop.

Then, on that build, run plan §7's hand checks (empty state; tap-through with the app closed, open and in two windows; Fix with AI copies the fenced handoff; Done updates an open To Do pane; double Done = one archive; bad `unlirice://` links do nothing; renamed log → "Can't read"; VoiceOver "Mark done: …") and record which reload path worked (Darwin notification or becoming active). The next Mac upload needs a build above 7 (and a version above 1.3 once 1.3 is approved); Capture is a separate record, still 1.2 (6).
**Gotchas:** **A development-signed build cannot open the app group container on this Mac.** Xcode signs Debug with "Mac Team Provisioning Profile: *", which carries no `application-groups`; macOS then refuses `group.com.calmdownoscar.unlirice` with EPERM and no prompt ("Event log file is unavailable"). `-allowProvisioningUpdates` does not create an explicit Mac development profile, and XcodeGen serialises a target `attributes: SystemCapabilities` entry as a string, which Xcode ignores. Only the App Store/TestFlight build (its Store profile has the group) can test the widget against real notes. **`NSExtension` has no `INFOPLIST_KEY_*` mapping:** the widget's point identifier must live in `UnliRiceWidget-Info.plist`, or the .appex is built without it and never registers (the B0 spike appears to have been built that way). **There are two note stores.** `~/Documents/events.jsonl` (395 open notes) is the old development store every AI session wrote to until 2026-09-25; the app has only ever read the app group store. The old store is left untouched; its 11 AI-written notes were copied across. **`check-repos.sh --publish` can't write the app group container from Claude's shell** (TCC); the founder's own Terminal can. The app is sandboxed: `Process`/`NSTask` is unavailable, so git
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
**To-dos:** filed 2 ("Refresh the project check so your To Do list is up to date", "Put the new version of Unli Rice on your Mac to get the To Do widget" — updated 2026-09-26 with the install steps); closed 0. Also: rewrote the 4 open to-dos in plain words and copied them, with 7 other AI-written notes, from the old `~/Documents` store into the app's store; archived the 2 replaced Vercel items in the old store as "replaced, not done"; took the "To-Do: Capture Inbox" note off the list (its 2 open items are now separate to-dos).
**Left by:** Claude Opus 5.5 2026-09-26

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
- **`docs/PLAN-copy-that-overstates.md` also went to the swarm without a Codex
  pre-mortem**, by explicit founder instruction on 2026-09-07. Two of its three open
  questions were answered by the swarm and one was resolved in the brief; none were
  reviewed by a second tool. Same caveat as the AI-todo feature above: the code works,
  the judgement in it is unreviewed.
