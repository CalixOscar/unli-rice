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

**Status:** Mac 1.5 (11) is **submitted: Waiting for Review** (submitted 2026-10-31 about 23:13, verified in App Store Connect; submission `68ca3580`). It replaces 1.5 (10), whose submission was cancelled on the founder's word the same evening. Build 11 (`447bb4e`) carries the Engineering Guardrails template refreshed from guardrails `7cf36bd`; the founder uploaded it from Xcode's Organizer (the command-line upload still fails with "Failed to Use Accounts"). App Store Connect has all seven screenshots in order 01-07 with the new 05 (`d84990f`). Release is automatic once approved, to all users immediately. 540 tests, 0 failed, 2 skipped (verified: `swift test` 2026-10-31). GitHub release `v1.5` is still build 10's source.
**Task:** None in flight. Waiting on App Review.
**Files touched:** `Sources/UnliRiceCore/HouseRulesPreset.swift`, `Scripts/check-template-drift.sh` (new), `APP_STORE_SUBMISSION.md` (checklist step 1), `project.yml` (build 11), `Screenshots/AppStore-Mac-2026-10-31/05-house-rules.png`, `PROJECT_NOTES.md`, `memory.md`.
**Next step:** Wait for Apple's review email; nothing is needed from the founder before then.

If approved: check the App Store page shows 1.5 and the new screenshot 05, and decide with the founder whether GitHub release `v1.5` should move to build 11's source. If rejected: read the resolution notes before changing anything. Later (1.6), unchanged: premortem takeaways 1, 3, 4, 5; Developer ID for a downloadable build; fix the command-line upload; keywords still include "second brain".
**Gotchas:** App Store screenshot 05 (`Screenshots/AppStore-Mac-2026-10-31/05-house-rules.png`) shows the Engineering Guardrails template: the refresh keeps its four visible paragraphs word for word, but the corner counter changes from ~869 tokens · 3,472 characters to ~900 tokens · 3,593 characters, so re-shoot 05 with any build that carries it. Chrome's file picker is a separate macOS service the accessibility tree can't see: open it from the page, then drive it with `orca computer … --restore-window` keys (Cmd+Shift+G, path, Return, Cmd+A, Return); header clicks fail with window_not_focused. App Store Connect keeps the picker's display order, and the picker sorts by Date Added, newest first, so stage files newest-last (copy 07 first, 01 last, a second apart). `dgo.sh`-style real mouse clicks in the demo app landed on the wrong controls; `dpress` (AXPress) is reliable. Run `fit.py` without `python3 -I`, which hides Pillow. Embedded views must not call `dismiss()`: in the main window it closes the whole window (the House Rules gallery did, fixed in `1a971b4` with an `onDone` closure). "New Note" in Notes creates a permanent "Untitled Note"; demo or review steps use the "New note title…" field and **Add**. The jev browser drives App Store Connect even with the screen locked; `browser_type` replaces a textarea's whole value, and the character counter (Notes: 4000 minus length) is the cheap check that a save stuck. The site's `.shot` images fade in on scroll (`assets/motion.css`); a screenshot taken too early looks dimmed. Demo screenshots: separate wrapper apps with their own bundle ids and `defaults` (scanRoots, exportFolderPath under `/tmp/unlirice-demo`) keep the debug default `~/Documents/Unli Rice` untouched; the 2026-10-31 demo scripts are in that Orca session's scratchpad (`demo/`). `.accessibilityRepresentation` lays its content out at its own size, so its Accessibility frames can land far from the drawn view (S8j's tabs ran past the window); check frames, not just roles. A borderless `Menu` takes its AX description from the symbol image's own description; set it with `NSImage(systemSymbolName:accessibilityDescription:)`, since `.accessibilityLabel` only sets the title. A container with `.accessibilityElement(children: .contain)` and `.isTabBar` (macOS 14+) gives a tab group with correct frames. `.accessibilityElement(children: .ignore)` without a trait gives `AXUnknown`; add `.isStaticText`. Test fixtures under `FileManager.default.temporaryDirectory` come back from `contentsOfDirectory` as `/private/var/…`; compare resolved paths. Accessibility display settings can't be written with `defaults` (domain is protected); toggle them in System Settings (`open "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Motion"` or `?Display`) and read them back with `NSWorkspace.accessibilityDisplayShouldReduceMotion`. To give a throwaway QA note a tag, append a `"kind":"tagged"` event to the QA vault's `events.jsonl`, not to `shards/` (that folder is this device's outgoing copy and is not read back). A `.buttonStyle(.plain)` row is only clickable where something is drawn; a `Spacer()` gap needs `.contentShape(Rectangle())`. Q4 fixture gardens (`q4-g0` … `q4-g60`) are in this session's scratchpad; switch the QA app's garden with `defaults write com.calmdownoscar.unlirice.studio-qa unliRice.scanRoots -array <dir>` and relaunch. BSD `seq 1 0` counts down (prints 1 and 0). Tab focus on macOS needs System Settings › Keyboard › Keyboard navigation (`AppleKeyboardUIMode`, unset by default on the founder's Mac); it was set to 2 for Q3 and deleted after, with the founder's OK. `.accessibilityElement(children: .ignore)` on a `Button` removes its button role and keyboard focus; a `Button` is already one element. The QA helpers (scratchpad of the 2026-10-31 Orca session: `qa-shot.sh`, `scroll`, `click`, `axdump`, `go.sh`) click real mouse events at Accessibility positions; SwiftUI views don't show up in System Events' `entire contents`, so `axdump` walks `AXChildren` itself. Menus live under the app element, not the window (`axdump --menus`). An open menu blocks AppleEvents (`activate` times out); close it first. AGENTS.md's builder table names `gpt-reserve` for `build`, but `~/.codex/build.config.toml` says `gpt-6.1-terra` (medium); S8b ran on that. Codex builders need their own `--scratch-path` when two run at once, and their sandbox needs `CLANG_MODULE_CACHE_PATH` under `/tmp`. Driving the QA app from Claude: `osascript` + System Events can move, resize and send keys; scroll with a CGEvent scroll-wheel helper, but `activate` the app in the same command or Stage Manager brings another window forward and the scroll lands there. The first `screencapture` raised a macOS "bypass the private window picker" prompt for Orca, which the founder allowed. A window of a bare `.app` launched with `open -g` stays mid-animation (screencapture gives a skewed 214×222 image) until the app is activated once with plain `open`. A borderless `Menu` fills the width it is offered; pin it with `.fixedSize()` and a frame. `liquidGlassCapsule` on a default-style `Button` draws a system button inside the glass; use `.buttonStyle(.plain)` with padding. **`codex exec` hangs on "Reading additional input from stdin..." when run from a background shell; always redirect `< /dev/null`.** S6's builder drew the sleeve transforms in `if`/`else` modifier branches, which gives each position its own view identity, so the flip crossfaded instead of rotating; keep motion modifiers in one unconditional chain. S5's review stops were builder-added `minHeight`s; §2.5a and §2.7a now forbid any size not listed. Two Claude sessions drove this build at once on 2026-10-30 (an Orca one and a desktop-app one); the founder chose the desktop-app session to drive. The Xcode-built debug `.app` shares the App Store bundle id and its `profiles.json` write into the App Group is refused by the sandbox: harmless, but run the unsigned `swift build` binary (`/tmp/unlirice-spm-build/debug/UnliRiceApp` with `UNLIRICE_DATA_PATH` set) for anything beyond a build check. Never toggle "Keep working with the window closed" in a debug build: it registers a real login item. `Screenshots/AppStore-Mac-2026-09-03/` filenames do not match their contents; check before citing one. **INTENT-008 (shared spec) exists only on Codex's local branch `codex/shared-spec`**; reconcile it with INTENT-009 before planning either. The vault's `04_Guardrails.md` wins over the new build-gate rule in `AGENTS.md` until it is updated.
**To-dos:** filed none; closed none (`BC9A8A42` stays open).
**Left by:** Claude Code (Orca session, Opus) 2026-10-31
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
