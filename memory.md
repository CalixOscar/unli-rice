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

**Status:** On `main`, everything pushed through `828c19b`. Working tree clean apart from
two untracked screenshot folders. 373 tests, 0 failures, 2 skipped (verified: `swift test`
2026-09-03, up from 366 — the AI-todo arc's 7 new tests, including a Python-fold-vs-
`Projector` agreement test that actually shells out to `python3`). Both Xcode targets build
— Mac `UnliRice` and `UnliRiceCapture` for the iOS Simulator (verified: `xcodebuild`
2026-09-03, both schemes, after the swarm's changes). Zero commits exist on no remote
(verified: `git rev-list --count --all --not --remotes` = 0).
**Task:** `docs/PLAN-ai-todo-actions.md` — the "flagged by AI" To Do section — was built by
the Antigravity swarm without its Codex pre-mortem (deliberate founder-directed skip) and
is now **independently verified, not just trusted on its SUCCESS line**: 7 new tests pass,
both targets build, and the end-to-end scenario was hand-run — filing a note tagged
`todo`+`calmdownoscar` and reading it back via `Scripts/unlirice-prompt-hook.py` from that
project's directory produces the correct injected context, with the ask-before-batching
sentence intact. Fail-open was verified against an unrecognized event kind (drops to the
static line, stderr diagnostic, valid JSON, no crash) using a synthetic corpus — not the
real 499-note log, since the event log is append-only and a test note would be permanent.
`docs/PLAN-keyboard-capture.md` is still queued at stage 2, unbuilt, un-pre-mortemed.
**Files touched:** This session — `AGENTS.md`, `Scripts/unlirice-prompt-hook.py`,
`Sources/UnliRice/TodoPaneView.swift`, `Sources/UnliRiceCapture/{CaptureStore,
TodoView}.swift`, `Sources/UnliRiceCore/StudioTodo.swift`,
`Tests/UnliRiceCoreTests/StudioTodoTests.swift` — built by the swarm from
`docs/PLAN-ai-todo-actions.md`, verified as above, about to be committed. One deviation
from the plan, harmless: `derive()` re-filters `tags.contains("todo")` itself instead of
trusting the caller's pre-filter the plan specified — redundant, not wrong.
**Next step:** Two things the build explicitly does NOT do and the founder still must:
install `Scripts/unlirice-prompt-hook.py` into a settings file (registered nowhere today —
confirmed `~/.claude/settings.json` has no `hooks` key), and decide whether the Python
event-log fold in the hook is safe enough to keep long-term, given it duplicates
`Projector.swift` in a second language. `docs/PLAN-keyboard-capture.md` still awaits its
Codex pre-mortem before any dispatch. Still open and untouched: the two untracked
screenshot folders (`Screenshots/app-panes/`, `Screenshots/repos-pane/`, 5 files each,
2026-09-02) need a founder decision, and the 1.2 gate work is unstarted — both
`MARKETING_VERSION` values are still "1.1" (`project.yml:64` and `:187`),
`Screenshots/AppStore/` holds Mac shots from 2026-07-22-24 that predate every current pane,
`Screenshots/AppStore-iOS/` has 2 marketing images in screenshot slots (a known rejection
cause), and `_AI Context/07_Prelaunch_Post_Mortem.md` has not been run. Do NOT bump a
version or archive for distribution without an explicit founder go.
**Gotchas:** The app is sandboxed: `Process`/`NSTask` is unavailable, so git state is read
by parsing `HEAD`, `refs/`, `packed-refs` and `worktrees/` directly, and every "fix" the UI
offers is copied text, never an action. Do NOT pass `.skipsHiddenFiles` to an enumerator
under `.git` — it is itself hidden, and the enumerator then yields nothing. Security-scoped
bookmarks are bound to the signing identity, so re-signing invalidates every folder grant;
`make-app.sh` signs with the Developer ID for this reason. **Adding a file under `Sources/`
requires `xcodegen generate`** — `swift test` globs sources and passes while Xcode fails on
a stale project; this has now bitten four times, and `.xcodeproj` is gitignored so the
regeneration is local-only and never arrives via `git pull`. `/Applications/Unli Rice.app`
is the **App Store install** (`_MASReceipt`, v1.1, root-owned) — it is the shipped product,
not a stale build; `dist/` is the local one. The eight Xcode schemes are distinct targets
generated from `project.yml`, not duplicate copies of the app. A corrupted
`DerivedData/.../XCBuildData/build.db` fails the build with `disk I/O error` and reads like
a code error; clean the build folder. `Sources/UnliRiceCapture/Resources/Assets 2.xcassets`
is still a stray duplicate, flagged and deliberately left for the founder to delete.
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
- `docs/PLAN-keyboard-capture.md` is **stage 4 and settled** — Codex's ten objections were
  all confirmed against `a962a26` and accepted. Note it now repairs two existing voice-path
  defects before adding typed capture: `finishRecording`'s single `catch` treats a
  persistence failure as a transcription failure and writes a second empty note, and the
  mirror into `events.jsonl` swallows both its errors while being the ONLY route to the Mac
  (the shard write goes to a local directory the publisher never reads).
- The AI-todo feature (`docs/PLAN-ai-todo-actions.md`) is now **built and independently
  verified**, but it still went to the swarm without a Codex pre-mortem. Verification
  caught no bugs, but it did not re-litigate the design calls in the plan's §5 — those
  are still unreviewed judgement, not settled fact, even though the code behind them
  works. The hook's Python fold of `events.jsonl` duplicates `Projector.swift` in a
  second language; the agreement test (`StudioTodoTests.swift`) is real and passes, but
  it will not catch a *new* `EventKind` added later without someone remembering to
  extend `KNOWN_EVENT_KINDS` in the Python file too.
