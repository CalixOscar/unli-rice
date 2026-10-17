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

**Status:** On branch `chore/plan-high-build-low` (**not merged to `main`**; its newest
commits exist only on this Mac until it is pushed). The public repo is
`github.com/CalixOscar/unli-rice`. The suite is **383 tests, 0 failures, 2 skipped**
(verified: `swift test --scratch-path /tmp/unlirice-spm-build` 2026-10-17). The bridge
smoke test passes 26/26, with `logs/` unchanged by the run, including a real
dispatch's files (verified: `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` 2026-10-17,
after the case-22 fix). Engineering Guardrails Phase 1 checks 1, 3 and 4 passed (verified
2026-10-17, on a throwaway vault). `docs/PLAN-codex-builder-contract.md` is **built and
verified**. Codex's post-mortem is in and answered (dialogue `State: closed`): four
bridge follow-ups were accepted, and `docs/PLAN-bridge-hardening.md` now closes them. It is
**built and verified**, and Codex's post-mortem is in and answered (dialogue
`docs/dialogue/bridge-hardening.md` `State: closed`). Local
`main` has 6 commits (`cbfa54a`..`6918f2d`) that are neither on `origin/main` nor on
this branch. Both targets are set to **1.2 (6)**, and neither has been archived or
uploaded.
**Task:** Four pieces on this branch, all built. (1) "Plan high, build low"
(`90f7b6e`). (2) The **Engineering Guardrails** built-in House Rules preset (`d57737c`),
whose checkpoint line now waits for review (`66b70c4`). (3) **One builder contract for
both tools**: `AGENTS.md` § "Builder contract" (`5564919`) holds the handoff fields,
"never `main`", the builder circuit breaker, and the `build` / `build-light` /
`planner` label table. Claude's `.claude/agents/builder*.md` point at it (`7fabe61`).
(4) **Bridge hardening** (`docs/PLAN-bridge-hardening.md`, built by the `builder`
subagent): `profile: ""` refused, profile files read by a strict subset, timed-out
results carry `cleanupFailed` / `groupAliveAtResult` / `signalError`, the test signal
switch is a spec field (`testSignals`), never an env var, and the smoke test deletes
only the files its own runs report. Post-mortem fix: smoke case 22 got its two missing
assertions. Known limits, accepted: repeated non-pinned keys and `1__2` pass the
parser, and an early setup failure leaves a `$TMPDIR` folder.
Outside the repo: the Codex profiles `~/.codex/build.config.toml` (`gpt-reserve`,
medium) and `build-light.config.toml` (`gpt-6-luna`, low). The bridge now refuses a
bad profile or a plan path outside `docs/`, pins the profile's model and effort, and
kills Codex's whole process group on timeout. A real `build-light` run through it used
`gpt-6-luna` / `low` (verified: Codex session record 2026-10-17). The vault's
`04_Guardrails.md` and `scripts/templates/PLAN.md` carry the new labels, **uncommitted
in the vault's git**. Phase 2 of the guardrails plan was **not** built. Still unreleased
from earlier: the sidebar lag fix `51ffb83` (never watched in the running app),
`46da148`, `958d9fd`, `1b01fb3`, `92be76e`, `37b4258`.
**Files touched:** In the repo this session: `Sources/UnliRiceCore/HouseRulesPreset.swift`,
`Tests/UnliRiceCoreTests/HouseRulesTests.swift`, `AGENTS.md`, `CLAUDE.md`,
`.claude/agents/builder.md`, `.claude/agents/builder-light.md`,
`docs/PLAN-shipped-guardrails.md`, `docs/PLAN-codex-builder-contract.md`,
`docs/REVIEW-codex-builder-setup.md`, `docs/REVIEW-codex-builder-contract.md`,
`docs/dialogue/codex-builder-setup.md`, `docs/dialogue/codex-builder-contract.md`,
`docs/PLAN-bridge-hardening.md`, `docs/REVIEW-bridge-hardening.md`,
`docs/dialogue/bridge-hardening.md`, `docs/REVIEW-postmortem-bridge-hardening.md`,
`PROJECT_NOTES.md`, `memory.md`. Outside the repo: the vault's
`_AI Context/04_Guardrails.md` and `scripts/templates/PLAN.md`;
`~/.codex/build.config.toml` and `build-light.config.toml` (`config.toml` unchanged,
backups `config.toml.bak-2026-10-17*`); `~/.tools/codex-mcp-bridge/index.js`,
`runner.mjs` and `test/smoke.mjs` (backups `~/.tools/codex-mcp-bridge.bak-2026-10-17`,
before the builder contract, and `.bak-2026-10-17-hardening`, before bridge hardening).
**Next step:** (1) Restart Claude Code sessions so the `codex-bridge` MCP server loads
the hardened bridge (this session still ran the old code). (2) Codex writes the
older post-mortem in `docs/dialogue/shipped-guardrails.md`. (3) The founder decides
whether to push this branch and merge it into `main`. Local `main`'s 6 unpushed commits
come along, and `memory.md` / `PROJECT_NOTES.md` will likely conflict. (4) The founder
commits the vault changes. (5) On the first two Codex-built steps, record in `PROJECT_NOTES.md` how
`gpt-reserve` / `gpt-6-luna` held up, and whether a nested `codex exec` works inside
the bridge sandbox. (6) Carried over: watch the sidebar before archiving, then the
founder archives and uploads both targets after `_AI Context/07_Prelaunch_Post_Mortem.md`.
**Gotchas:** **Every bridge run is told to run the project's build/tests**, even a
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
The House Rules gallery is More → "What your AI should always do". The editable draft
is More → Setup & Tools → House Rules → Edit; the gallery preview is read-only.
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
**Left by:** Claude Opus 5.5 2026-10-17

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
