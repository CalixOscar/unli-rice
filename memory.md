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

**Status:** Four features built and green. 318 tests, 0 failures, 1 skipped (verified:
`swift test` 2026-09-02). Mac app and iOS Capture both build clean. Still on
`feature/languages-and-append`, 22 ahead of `origin/main`, 6 commits on no remote.
**Task:** (1) transcription locale now follows KEYBOARDS not region; (2) mixed-language
caveat added to the picker footer; (3) Mac publishes `repos.json` into the shared folder
and Capture renders it read-only; (4) branch graph in the Mac Repos pane.
**Files touched:** `Sources/UnliRiceCore/Sync/TranscriptionLocale.swift` (injectable
default), `Sources/UnliRiceCore/Sync/RepoSnapshotFile.swift` (new),
`Sources/UnliRiceCapture/{KeyboardLocales,ReposSnapshotView}.swift` (new),
`Sources/UnliRiceCapture/{TranscriptionLanguageListView,TranscriptionLanguages,CaptureStore,CaptureView}.swift`,
`Sources/UnliRice/BranchGraphView.swift` (new), `Sources/UnliRice/RepoPaneView.swift`,
`Tests/UnliRiceCoreTests/{TranscriptionLocaleTests,RepoSnapshotFileTests}.swift` (new).
**Next step:** Screenshot the branch graph in the Mac Repos pane — the display slept before
I could. Then verify the Capture "Repos on your Mac" screen end to end: open Repos on the
Mac once to publish `repos.json`, then open the phone screen against the same shared folder.
Then push — 6 commits here and 1 each on `feature/byo-llm` and `feature/ios-share-to-ai`
are on no remote.
**Gotchas:** `KeyboardLocales` needs UIKit, so it lives in the iOS target and is injected
into Core via `effectiveLocale(for:systemDefault:)` — Core cannot compute it. **Adding a
file to an Xcode target requires `xcodegen generate`**: `swift test` globs sources and
passed, while the iOS build failed with "cannot find 'KeyboardLocales' in scope" against a
stale `.xcodeproj`. The branch graph is a REF graph, not a commit graph — lane length
carries no meaning and there are deliberately no ahead/behind counts. Capture's language
picker still spins forever in the Simulator (see below).
**Left by:** Claude Code 2026-09-02

## Open hypotheses

<!-- Live guesses about a current problem, and what would confirm or kill each one.
     Delete an entry the moment it is settled — the answer belongs in
     PROJECT_NOTES.md's Decisions Log, not here. -->

- _(none)_

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
