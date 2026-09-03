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

**Status:** On `main`, everything pushed through `37b4258`, working tree clean.
380 tests, 0 failures, 2 skipped (verified: `swift test` 2026-09-03). Both Xcode
targets build — Mac `UnliRice` and `UnliRiceCapture` for the iOS Simulator, iPad
Pro 13" included (verified: `xcodebuild` 2026-09-03). `project.yml` is now
`MARKETING_VERSION "1.2"` for both targets, `CURRENT_PROJECT_VERSION "6"`
(Capture) and `"5"` (Mac) — not applied yet: **neither has been archived or
uploaded.** `xcodegen generate` has been re-run since the bump.
**Task:** Four independent pieces landed this session. (1) A confirmation toast
on `AITodoMenu`/`AIReviewMenu` ("Fix with AI…" / "Resolve with AI…") — picking a
target used to close the menu with zero visible feedback; matches the toast
`CleanupMenu` already had (`46da148`). (2) Committed a rating-prompt feature
that was already fully written and tested in the working tree at session start
(not authored this session) — `ReviewPrompt`/`offerRatingIfEarned()` existed but
were dead code, never called; now wired to a completed Mac ingest and a durable
Capture save, plus a permanent "Rate" row on both apps that opens the App
Store's write-review URL directly rather than the rate-limited `requestReview`
(`958d9fd`). (3) Resolved `docs/IOS_CAPTURE_RELEASE.md` §1.6's open "decide iPad,
deliberately" question — its premise was stale: `CaptureView` already has a real
two-column `horizontalSizeClass == .regular` layout, confirmed live on an iPad
Pro 13" simulator. Kept `TARGETED_DEVICE_FAMILY: "1,2"`, fixed the leftover
phone-only copy ("Keep on this phone only", "nothing leaves this phone", etc.)
to device-neutral text, verified on-device (`1b01fb3`). (4) Replaced both stale
App Store screenshot sets — old Mac set showed the retired `Brain map / Setup /
Looking back` sidebar; old iPhone set had two marketing banners in screenshot
slots (one a Mac window composited into an iPhone frame) plus four shots
predating `621ccea`'s type-a-note fix. Recaptured a same-day iPad-13 set
(2064×2752) and reorganized both device folders under one dated parent
(`37b4258`).
**Files touched:** `Sources/UnliRice/{ContentView,TodoPaneView}.swift` (toast);
`Sources/UnliRice/{AppStore+Ingest,AppStore+Rating,MoreView,UnliRiceApp}.swift`,
`Sources/UnliRiceCapture/{CaptureApp,CaptureStore,CaptureReviewPrompt}.swift`,
`Sources/UnliRiceCore/ReviewPrompt.swift`,
`Tests/UnliRiceCoreTests/ReviewPromptTests.swift` (rating); `Sources/
UnliRiceCapture/{CaptureView,CapturePlayer,ReposSnapshotView,
WelcomeSplashView}.swift` (device-neutral copy); `Screenshots/` (full
reorganization — see `37b4258`); `project.yml` (version bump, this pass,
uncommitted).
**Next step:** Commit the `project.yml` version bump — it is applied and both
targets build, but not yet committed. After that, the founder archives and
uploads both targets themselves; this session did not and will not. Separately,
the founder reported the sidebar (To do / Repos / etc.) sometimes needing
several clicks to switch panes. Diagnosed by reading code only — screen access
to the running app was declined, so this is **unverified against the real
app**: `ContentView.body` observes `store` directly and re-evaluates on every
`@Published` write, and a single sidebar click fires through `closeAllPanes()`
(`AppStore.swift:1095`, 17 Bool writes) plus the destination's own `show*()` —
each of those turns re-runs the three `GeometryReader` `Circle()` blurs at
radius 80-95 in `ContentView.swift:13-34`, which sit behind `.liquidGlass` on
the sidebar. Cheapest next step: comment out that block and see if the lag
goes away; if so, pull it into a view that doesn't observe `store` (so SwiftUI
skips re-rendering it) plus `.drawingGroup()`. The 17-Bool pane-tracking is a
deeper cause (wants a single `@Published enum Pane`) but that is swarm-shaped,
not a quick fix. `_AI Context/07_Prelaunch_Post_Mortem.md` still has not been
run before any future distribution action — unrelated to the sidebar issue,
carried over from before this session and not touched.
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
to delete.
**Left by:** Claude Sonnet 5 2026-09-03

## Open hypotheses

<!-- Live guesses about a current problem, and what would confirm or kill each one.
     Delete an entry the moment it is settled — the answer belongs in
     PROJECT_NOTES.md's Decisions Log, not here. -->

- Sidebar pane-switching lag ("click it four times"): hypothesized cause is the
  three blurred `GeometryReader` circles in `ContentView.swift:13-34`
  re-rendering on every `@Published` write from `closeAllPanes()`. Confirms if
  removing that block (temporarily) makes single clicks reliable; kills if the
  lag persists with the block removed, which would point at something in the
  destination pane's own `body` instead.

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
