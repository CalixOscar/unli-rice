# REVIEW — pre-mortem of docs/PLAN-memory-overhaul.md

**Requested by:** the founder, 2026-10-29
**Reviewer:** codex, on its best model
**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/memory-overhaul.md`. Change nothing else: no code, no config, no other docs,
no `memory.md`, no commits. Don't edit `docs/PLAN-memory-overhaul.md`, the intent doc or this
brief. Don't start any nested `codex` run. Running the build or tests is optional; if
you do, use `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` (and
the same flags for `swift test`). If the sandbox blocks it, say so; don't count that as
a failure.

## What you are reviewing

Read `docs/intent/INTENT-007-memory-overhaul.md` first (founder-approved 2026-10-29), then
`docs/PLAN-memory-overhaul.md`. You're on `main` at `0ba0c1a`, which now contains your Garden
work and Claude's four-jobs work (both merged 2026-10-29). `feature/todo-widget` is not merged
yet; the plan's A0 merges it first.

In short: the app is reframed around three jobs (grounding, guardrails, evals). Phase A
(build-ready) moves Projects, To do, Map, Your year so far, Separate memories, PDF/ZIP export
and the Capture promo behind per-feature switches in a new Setup › Extras tab, and adds two
background switches (bulk folder import, duplicate detection) to `AgentSettings`. Phase B
(design only) mirrors other tools' memory files (Claude Code, Codex, AGENTS.md/CLAUDE.md/memory.md)
into notes using only `created`/`appended` events. Phase C (design only) runs deterministic
checks over Claude Code transcripts, derived and never stored.

This review also stands in for stage 1.5: nothing has attacked the intent yet. Say plainly if
the intent itself is wrong, not just the plan.

## Try to break it

Check the plan against the code. The code wins over the plan.

1. **The intent (stage 1.5).** Is "Unli Rice shows what every AI remembers and checks whether it
   followed the rules" a real job, given the evidence in the intent? Use the lens list in
   `~/Documents/Unli Rice Vault/_AI Context/08_AI_Failure_Modes.md` if you can read it (mark
   unverified if the sandbox blocks it). What would make this overhaul pointless?
2. **Defaults (A1, A2, decision 4).** Does decoding an old `AgentSettings` JSON really give the
   two background switches `true`, and a fresh install `false`? Check every place
   `AgentSettings` is created, decoded, saved or copied (app, `unlirice-agent`, tests), including
   whether a fresh `AgentSettings()` is ever saved over an existing file. Is "has a scan root" a
   safe proxy for "has used Projects/To do"? Any path where an existing user loses a screen?
3. **Nothing runs invisibly.** With A applied, can bulk import or duplicate proposals run while
   their switch says off, through any caller (`RoutineDriver`, `unlirice-agent` manual path,
   `AppStore+Ingest`, `AppStore+Janitor`, Autopilot)? Is leaving the draft hint
   (`AppStore+Drafts.swift:16`) on the default the right call?
4. **Doors (A3).** After A, name any page, notice destination, menu command, widget link or button
   that points at an extra that's off and breaks or strands the user, beyond the deep-link case
   §7 accepts. Include `FirstRunView`, `HomeView`, Setup's Folders flow and Garden's "Manage folders".
5. **Phase B: the mirror.** Is mirroring memory files into notes with full-text `appended` events
   sound against the locked architecture in `PROJECT_NOTES.md`? Log growth, sync shards, MCP
   search noise, the janitor treating mirrored notes as duplicates or orphans, a file that churns
   every session, secrets inside a memory file now copied into the log and the folder mirror.
   Propose the safer shape if there is one.
6. **Phase C: evals.** Are the six checks actually decidable from Claude Code transcripts as
   they are on disk (read a real one under `~/.claude/projects` if the sandbox allows; otherwise
   mark unverified)? False passes and false fails for each. Is "derived, never stored" workable
   once Claude Code deletes old transcripts, given `raw/`?
7. **Builder choices.** Name anything a `build` builder would still have to decide in A1–A4
   (where a property loads, init order, copy, layout).
8. **Unprotected invariants.** There are no app-target tests. Name anything §6 acceptance would
   let through broken, and the cheapest check that would catch it.

## Output format

Create `docs/dialogue/memory-overhaul.md` following `docs/dialogue/README.md`:

```markdown
# Dialogue — memory-overhaul

**Plan:** docs/PLAN-memory-overhaul.md
**Planner:** claude
**Reviewer:** codex
**State:** open

## codex — pre-mortem — 2026-10-29

1. <finding, with file:line evidence, and what the plan should say instead>
2. ...
```

Number every finding. Mark severity (blocker / should-fix / nit). Cite `file:line` or
mark it unverified. Then stop.
