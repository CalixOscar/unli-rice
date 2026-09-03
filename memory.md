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

**Status:** On `main`, everything pushed through `f58f40f`, working tree clean apart from
two untracked screenshot folders. 375 tests, 0 failures, 2 skipped (verified: `swift test`
2026-09-03). Both Xcode targets build — Mac `UnliRice` and `UnliRiceCapture` for the iOS
Simulator (verified: `xcodebuild` 2026-09-03).
**Task:** `docs/PLAN-keyboard-capture.md` is **built** — typing a note on the phone, which
previously could only start as speech. Built by Claude directly at the founder's
instruction because the swarm was occupied with the Clean-up toast; that is a deviation
from the usual stage-5 split and was explicit, not drift. The toast feature it was running
is also verified and committed (`2b84461`).
**Files touched:** `Sources/UnliRiceCapture/{CaptureStore,CaptureView,NoteDetailView,
ArchivedNotesView}.swift` and the new `TypedNoteSheet.swift`;
`Sources/UnliRiceCore/Sync/ShardWriter.swift` (the `transcript:` → `text:` rename on both
public APIs); `Tests/UnliRiceCoreTests/{ShardSyncTests,ShardWriterTests,NoteServiceTests}
.swift`.
**Next step:** Run the by-hand UI journeys in `docs/PLAN-keyboard-capture.md` §3, tests
4-14 — **none of them have been run.** The ones that matter most are 12 (a spoken note
still works end to end), 13 (a voice append still appends and creates no new capture) and
14 (a failed transcription still produces exactly one empty note with playable audio),
because the extraction rewrote control flow in `finishRecording`. Also still open: the two
untracked screenshot folders need a founder decision, and the 1.2 gate work is unstarted —
both `MARKETING_VERSION` values are still "1.1" (`project.yml:64` and `:187`),
`Screenshots/AppStore/` predates every current pane, `Screenshots/AppStore-iOS/` has 2
marketing images in screenshot slots (a known rejection cause), and
`_AI Context/07_Prelaunch_Post_Mortem.md` has not been run. Do NOT bump a version or
archive for distribution without an explicit founder go.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable, so git state is read
by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/` directly, and every "fix" the UI
offers is copied text, never an action. Do NOT pass `.skipsHiddenFiles` to an enumerator
under `.git` — it is itself hidden and yields nothing. Security-scoped bookmarks are bound
to the signing identity, so re-signing invalidates every folder grant. **Adding a file
under `Sources/` requires `xcodegen generate`** — `swift test` globs sources and passes
while Xcode fails; `.xcodeproj` is gitignored so the regeneration is local-only and never
arrives via `git pull`. **`ShardWriter` writes to the phone's own `shards/` directory, but
`sync()` publishes from `events.jsonl`** — so with a shared folder configured the shard
write is a dead end and that log is the only route to the Mac. `/Applications/Unli
Rice.app` is the **App Store install** (`_MASReceipt`, v1.1) — the shipped product, not a
stale build; `dist/` is the local one. The eight Xcode schemes are distinct targets from
`project.yml`, not duplicate apps. A corrupted `DerivedData/.../XCBuildData/build.db` fails
with `disk I/O error` and reads exactly like a code error. `deleteCapture` purges
`events.jsonl` via `TrashService`, so "no destructive delete" is true of the Mac's note
tools but **not** of the phone. `Sources/UnliRiceCapture/Resources/Assets 2.xcassets` is
still a stray duplicate, left for the founder to delete.
**Left by:** Claude Code 2026-09-03

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
- `docs/PLAN-keyboard-capture.md` is **built** (`f58f40f`) but its by-hand UI journeys are
  unrun. Treat the voice path as verified-by-compiler-only until §3 tests 12-14 pass.
- The AI-todo feature (`docs/PLAN-ai-todo-actions.md`) is now **built and independently
  verified**, but it still went to the swarm without a Codex pre-mortem. Verification
  caught no bugs, but it did not re-litigate the design calls in the plan's §5 — those
  are still unreviewed judgement, not settled fact, even though the code behind them
  works. The hook's Python fold of `events.jsonl` duplicates `Projector.swift` in a
  second language; the agreement test (`StudioTodoTests.swift`) is real and passes, but
  it will not catch a *new* `EventKind` added later without someone remembering to
  extend `KNOWN_EVENT_KINDS` in the Python file too.
