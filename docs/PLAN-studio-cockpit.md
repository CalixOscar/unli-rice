# PLAN — Studio cockpit

**Intent:** `docs/intent/INTENT-001-studio-cockpit.md`
**Stage:** 2 (Claude's plan). **Not built.** Next stop is Codex's pre-mortem, then a stage-4
revision, then the swarm. Nothing in this file has been implemented.
**Date:** 2026-09-02

## The two findings that shape everything below

Both came out of the intent's open questions, and both change the design rather than
decorating it.

**1. The app is sandboxed, so it cannot run `git`.** Unli Rice has shipped on the Mac App
Store since 2026-08-01. An App Store build cannot exec arbitrary binaries, and reading
`~/Documents/Projects` at all needs a user-granted security-scoped bookmark. Three ways out,
and only one survives contact with the constraints:

| Approach | Verdict |
|---|---|
| Ship git plumbing in-process (parse `.git` directly) | Reimplements ahead/behind, stash and status inside a sandbox, for a read-only dashboard. Large, subtly wrong, and a maintenance liability forever. **No.** |
| Non-sandboxed helper / XPC service | Cannot ship in an App Store build. Would fork the product into two distributions. **No.** |
| **`check-repos.sh` writes JSON; the app reads one file** | The script already exists, already works, and already runs outside the sandbox. The app reads one small JSON file from its own App Group container — a path it is already permitted. **Yes.** |

So: **add `--json` to `check-repos.sh`**, have a LaunchAgent run it on a schedule, and let
the app render the result. This is also the honest division of labour — the scripts stay the
enforcement layer and keep working with the app closed, exactly as the intent requires.

**2. An MCP server cannot inject anything into a client's system prompt.** MCP exposes
tools, resources and prompts; the *client* decides what to invoke. There is no server-side
hook that prepends text to an agent's context. So "MCP guardrail injection" as briefed is
not implementable, and shipping it as a tool the agent may or may not call is not
enforcement either. Two mechanisms actually work, and they are complementary:

- **An MCP resource** (`unlirice://studio/guardrails`, `unlirice://project/<name>/memory`) —
  the correct MCP primitive for "content the client may read". Discoverable, no new
  mutation surface, and honest about being pull-not-push.
- **The `UserPromptSubmit` hook** — `Scripts/unlirice-prompt-hook.py` already exists in this
  repo and is registered in no settings file, so it currently does nothing. A hook *does*
  reach the model's context on every prompt. It is the only push mechanism available, and
  it is per-machine configuration rather than something the app can grant itself.

Say this plainly in the UI rather than implying the app can bind agents it cannot bind.

## Scope

Four components. Each is independently shippable and independently useful; do not treat this
as one feature.

### A. `check-repos.sh --json` + LaunchAgent  *(no app code)*
- Add a `--json` mode emitting `{generated_at, projects: [{name, path, branch, modified,
  untracked, stashes, ahead, upstream, has_repo}]}`. Keep the human output byte-identical —
  it is the fallback when the app is closed and must not regress.
- Write to the existing App Group container next to `connections.json`, so the app reads a
  path it already has. Write to a temp file and `mv` it into place; a half-written JSON read
  mid-scan is the obvious first bug.
- LaunchAgent modelled on the existing `Config/LaunchAgents/com.calmdownoscar.unlirice.agent.plist`.
  Interval, not `WatchPaths` — watching every `.git` in every project is a file-descriptor
  problem for a report nobody reads more than a few times a day.
- **Stale data is a first-class state.** The app shows the scan's age and says so when it is
  old. A dashboard confidently showing yesterday's git state is worse than showing nothing.

### B. Git panel  *(app, read-only)*
- One row per project: branch, dirty count, untracked count, stashes, ahead count, and the
  two loud states — **no upstream** and **not a git repo**. Those two are what the
  2026-09-02 scan actually found and they are the ones that mean work exists nowhere else.
- Sorted by severity, not alphabetically. Clean projects collapse out of the way.
- **No action buttons.** Not commit, not push, not even "open in terminal" as a first cut.
  The intent excludes it and the sandbox makes it awkward; revealing the folder in Finder is
  the most it should do.
- Fails the product philosophy if it is somewhere you sit. It is a glance: if nothing is
  outstanding it should say one line and get out of the way.

### C. Context provider  *(MCP + app)*
- MCP **resources**, not tools: `unlirice://studio/guardrails` (reads the vault's
  `_AI Context/04_Guardrails.md`) and `unlirice://project/<name>/memory` (reads that
  project's `memory.md`). Read-only, no new write path — locked decision #3 holds.
- Serving a 32,000-char `memory.md` is exactly what its cap exists to make safe. Serve
  `PROJECT_NOTES.md` through this only if a size guard is enforced at the boundary;
  119,551 characters must never be handed to a client because it was asked for.
- Ordering matters for the client's prompt cache: guardrails (stable for weeks) before
  `memory.md` (changes several times a session). Document it on the resource; the server
  cannot enforce what the client assembles.
- **Wire up `Scripts/unlirice-prompt-hook.py`** as the push half, and document that it is
  per-machine settings the user installs — not something the app does for them.

### D. Artifact reporter  *(app, reporting only — not an enforcer)*
Named deliberately. Locked decision #3 is that this codebase proposes rather than applies,
and the same logic that made `resolve_review` a human action applies here: an app that
blocks the founder's own workflow on a missing file will be worked around within a week.
- Reports per project: `memory.md` present and within 32,000 chars; `PROJECT_NOTES.md`
  present; at least one `docs/intent/INTENT-*.md`; studio hooks installed and not drifted
  (shell out is impossible, so read `install-studio-hooks.sh --check`'s JSON from the same
  scan file as A); `private/` correctly ignored.
- The blocking already exists and is in the right place — the pre-commit hook. This panel
  tells you which repos will fail *before* you spend a session there.

## Sequence

A → B → D → C. A and B are the whole of the intent's "what solved looks like" for the git
half, and A has no app code at all, so it can land and be useful before any UI exists. C is
last because it is the piece whose mechanism changed most from the brief and therefore the
one most worth re-examining after A–B are real.

## Test criteria

- `check-repos.sh --json | python3 -m json.tool` parses, and its `ahead`/`stashes` values
  match `git rev-list --count` and `git stash list` for a repo with each state (the
  2026-09-02 run gives a known-good fixture: Unli Rice ahead 22, Nuptia 1 stash, five
  projects with no upstream).
- Human output of `check-repos.sh` with no flag is byte-identical to today's.
- A scan file truncated mid-write renders as "scan unavailable", never as "all clean".
- A scan file older than its interval renders its age prominently.
- The MCP resource for a project with no `memory.md` returns a clean not-found, not an empty
  string that reads as "no current state".
- Existing suite still green (296 tests, zero failures as of the last note entry —
  unverified in this session).

## Declined / deferred

- **In-process git.** Reason above. If A's scheduled-scan latency ever becomes the real
  complaint, revisit — but latency has not been a complaint, invisibility has.
- **Any write action from the cockpit.** Excluded by the intent, and by locked decision #3.
- **Guardrail rules stored in the app.** The vault stays the single source of truth. The app
  reads; it never becomes a second place a rule is written.
- **Blocking on a missing artifact.** See D.

## For the pre-mortem (stage 3)

The weakest assumption here is that a scheduled scan is fresh enough to be trusted. If the
founder makes a commit and the panel still shows the old state for ten minutes, the panel
teaches him not to believe it — and an untrusted dashboard is worse than none. Attack that
first. Second: whether `docs/intent/` earns its place at all, or whether one intent doc
written on 2026-09-02 is a convention that exists only because it was proposed today.
