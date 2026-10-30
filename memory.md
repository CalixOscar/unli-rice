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

**Status:** Mac 1.4 (9) **submitted for App Review** 2026-10-29 at the founder's explicit request; App Store Connect showed "1.4 Waiting for Review" that day (not rechecked since). On `claude/studio-redesign`: **Phase A's code is built** (S1, S2, S4–S7 merged) plus a polish merge `a3b9ae3` that fixed three defects seen in the running app: the gear menu filled the toolbar, glass buttons drew a system button inside the capsule, and a project with no `docs/` showed every light as "?". 516 tests, 0 failed, 2 skipped; Xcode Debug build succeeded; both tabs checked on screen against a throwaway vault (verified by Claude 2026-10-30). Nothing here merges to `main` until 1.4 resolves.
**Task:** Studio redesign, Phase A. Next is **S8, the QA matrix (plan §4, Q1–Q13 and K1)**, walked with the founder one row at a time and recorded as pass, fail or "not run, because …". Then S9 (`docs/USER_GUIDE.md` copy sync), S10 (`PROJECT_NOTES.md`/`memory.md`, Codex post-mortem through `codex exec` read-only, one file). Phase B (native Idea Clinic) stays blocked on a shared `clinic.json` on the website.
**Files touched:** `Sources/UnliRice/Studio/StudioToolbar.swift`, `StudioDeck.swift`, `GardenCrateView.swift`, `GardenExpandedView.swift`, `SleeveBackView.swift`, `GuardrailsGroundingView.swift` (plain button style under glass), `Sources/UnliRiceCore/BuildGate.swift` (missing `docs/` is no plan), `Tests/UnliRiceCoreTests/BuildGateTests.swift` (`testNoDocsFolderGivesNotRecorded`), `memory.md`.
**Next step:** Run S8 with the founder and walk plan §4 one row at a time. A QA wrapper already exists: `Unli Rice Studio QA.app` (bundle id `com.calmdownoscar.unlirice.studio-qa`, unsigned debug binary, `LSEnvironment` pointing `UNLIRICE_DATA_PATH` and `UNLIRICE_AGENT_SETTINGS` at a throwaway vault, scan root set with `defaults write com.calmdownoscar.unlirice.studio-qa unliRice.scanRoots -array <garden>`); it lived in the session scratchpad, so rebuild it the same way if it is gone. Q1's 960×600 scroll check has never been run. For 1.4: wait for App Review; on approval merge and push the website branch `claude/unlirice-1.4`, release if manual release is set; on rejection read the reason first. Next Mac build number is 10.

**Gotchas:** A window of a bare `.app` launched with `open -g` stays mid-animation (screencapture gives a skewed 214×222 image) until the app is activated once with plain `open`. A borderless `Menu` fills the width it is offered; pin it with `.fixedSize()` and a frame. `liquidGlassCapsule` on a default-style `Button` draws a system button inside the glass; use `.buttonStyle(.plain)` with padding. **`codex exec` hangs on "Reading additional input from stdin..." when run from a background shell; always redirect `< /dev/null`.** S6's builder drew the sleeve transforms in `if`/`else` modifier branches, which gives each position its own view identity, so the flip crossfaded instead of rotating; keep motion modifiers in one unconditional chain. S5's review stops were builder-added `minHeight`s; §2.5a and §2.7a now forbid any size not listed. Two Claude sessions drove this build at once on 2026-10-30 (an Orca one and a desktop-app one); the founder chose the desktop-app session to drive. The Xcode-built debug `.app` shares the App Store bundle id and its `profiles.json` write into the App Group is refused by the sandbox: harmless, but run the unsigned `swift build` binary (`/tmp/unlirice-spm-build/debug/UnliRiceApp` with `UNLIRICE_DATA_PATH` set) for anything beyond a build check. Never toggle "Keep working with the window closed" in a debug build: it registers a real login item. `Screenshots/AppStore-Mac-2026-09-03/` filenames do not match their contents; check before citing one. **INTENT-008 (shared spec) exists only on Codex's local branch `codex/shared-spec`**; reconcile it with INTENT-009 before planning either. The vault's `04_Guardrails.md` wins over the new build-gate rule in `AGENTS.md` until it is updated.
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
