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

**Status:** On `main`, everything pushed, working tree clean apart from two untracked
screenshot folders. 343 tests, 0 failures, 2 skipped (verified: `swift test` 2026-09-02).
Mac scheme builds under Xcode; `UnliRiceApp` builds under SwiftPM. **Zero commits exist on
no remote** (verified: `git rev-list --count --all --not --remotes` = 0) — the 13 local
branches without an `origin/` counterpart are merged, not at risk, and the previous version
of this file was wrong to call them 6 unbacked commits.
**Task:** The studio cockpit, points 3–7 of the research doc. Shipped: a Repos pane reading
git refs directly (no subprocess — the sandbox forbids `Process`), a branch graph with
tapered turnouts and zoom, a derived to-do list that cannot be ticked off, "Fix with AI" on
declared next steps, and a milestone-laddered rating prompt. Point 2 (moving `Projects` into
the vault) was explicitly deferred by the founder and is NOT in scope.
**Files touched:** `Sources/UnliRiceCore/{GitRepoScanner,StudioTodo,ReviewPrompt}.swift` and
`Sources/UnliRiceCore/Sync/RepoSnapshotFile.swift` (v3 schema); `Sources/UnliRice/`
`{BranchGraphView,RepoPaneView,TodoPaneView,AppStore+TodoPrompt,AppStore+Rating}.swift`;
`Sources/UnliRiceCapture/{ReposSnapshotView,TodoView}.swift`;
`Tests/UnliRiceCoreTests/{StudioTodoTests,ReviewPromptTests,RepoSnapshotFileTests}.swift`.
Canonical scanner scripts live in the vault at `~/Documents/Unli Rice Vault/scripts/`.
**Next step:** Decide the two untracked screenshot folders — `Screenshots/app-panes/` and
`Screenshots/repos-pane/` (5 files each, captured 2026-09-02) are the new panes and are not
committed. Then, if a 1.2 submission is wanted, the gate work: both `MARKETING_VERSION`
values are still "1.1" (`project.yml:64` and `:187`), `Screenshots/AppStore/` still holds
Mac shots from 2026-07-22–24 that predate every pane above, `Screenshots/AppStore-iOS/`
holds 2 marketing images in screenshot slots (a known rejection cause), and
`_AI Context/07_Prelaunch_Post_Mortem.md` has not been run. Do NOT bump a version or
archive for distribution without an explicit founder go — see `docs/IOS_CAPTURE_RELEASE.md`.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable and no entitlement
exists, so git state is read by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/`
directly, and every "fix" the UI offers is copied text, never an action. Do NOT pass
`.skipsHiddenFiles` to an enumerator under `.git` — it is itself hidden, and on a real
volume the enumerator then yields nothing (13 packed branches found where 21 exist).
Security-scoped bookmarks are bound to the signing identity, so re-signing invalidates
every folder grant; `make-app.sh` signs with the Developer ID for this reason. **Adding a
file under `Sources/` requires `xcodegen generate`** — `swift test` globs sources and
passes while the Xcode build fails on a stale `.xcodeproj`; the pre-commit hook now warns,
and it has caught this three times. `Sources/UnliRiceCapture/Resources/Assets 2.xcassets`
is still a stray duplicate, flagged and deliberately left for the founder to delete.
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
