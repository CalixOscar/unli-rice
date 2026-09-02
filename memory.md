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

**Status:** On `main`, everything pushed through `d0fc83f`. Working tree clean apart from
two untracked screenshot folders. 366 tests, 0 failures, 2 skipped (verified: `swift test`
2026-09-03). Both Xcode targets build — Mac `UnliRice` and `UnliRiceCapture` for the iOS
Simulator (verified: `xcodebuild` 2026-09-03). Zero commits exist on no remote (verified:
`git rev-list --count --all --not --remotes` = 0).
**Task:** Codex's post-mortem was triaged rather than actioned as a checklist — five of its
findings survived re-verification at HEAD, and they turned out to be one bug class: an
unknown silently becoming a positive claim. `docs/PLAN-unknown-stays-unknown.md` went
through a Codex pre-mortem, a stage-4 revision, and the Antigravity swarm; it is **built,
verified and pushed**. Two plans are now queued at stage 2, neither pre-mortemed:
`docs/PLAN-keyboard-capture.md` (typing a note into Capture) and, new this session,
`docs/PLAN-ai-todo-actions.md` (a section in the To Do pane, Mac and Capture, for action
items an LLM in any project files via `create_note`/`tag_note` — no new MCP tool, no
schema change). Both are plan-only per the studio pipeline; neither is built.
**Files touched:** Built this arc — `Sources/UnliRiceCore/{StudioTodo,TodoEmptyState,
NoteService}.swift`, `Sources/UnliRiceCore/MCP/{MCPToolCatalog,UnwrittenClients,
ConnectionActivity}.swift`, `Sources/UnliRice/{TodoPaneView,AppStore,HomeView,MoreView,
ContentView,ProfileBuilderView,WhyNotTextFileView}.swift`,
`Sources/UnliRiceCapture/TodoView.swift`, `Sources/unlirice-mcp/ToolDispatcher.swift`,
`Scripts/unlirice-prompt-hook.py`, and six test files under `Tests/UnliRiceCoreTests/`.
Planned only, not built: `docs/intent/INTENT-003-keyboard-capture.md` +
`docs/PLAN-keyboard-capture.md`, and `docs/intent/INTENT-004-ai-todo-actions.md` +
`docs/PLAN-ai-todo-actions.md`.
**Next step:** `docs/PLAN-ai-todo-actions.md` is **with the Antigravity swarm**, dispatched
2026-09-03 at founder direction **without its Codex stage-3 pre-mortem** — a deliberate
pipeline skip, recorded in the plan's header. When it reports, check `git diff`, not its
SUCCESS line. Two things the swarm is explicitly NOT doing and the founder must: install
`Scripts/unlirice-prompt-hook.py` into per-machine settings (it is registered nowhere
today), and decide whether the Python event-log fold in §2.6 is safe enough to keep.
`docs/PLAN-keyboard-capture.md` is still stage 2 awaiting its own pre-mortem. Still open
and untouched: the two untracked
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
- `docs/PLAN-keyboard-capture.md` is stage 2 and **not settled** — it has not had its Codex
  pre-mortem, so it must not be dispatched to the swarm yet.
- `docs/PLAN-ai-todo-actions.md` went to the swarm **without a Codex pre-mortem**, at
  explicit founder direction. Treat its output with more suspicion than usual, and read
  §5 "For the pre-mortem" as a list of things nobody checked rather than things settled.
  Its §2.6 Python fold of `events.jsonl` duplicates `Projector.swift` in a second
  language and is the named top risk.
