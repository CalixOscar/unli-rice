# REVIEW — post-mortem of docs/PLAN-bridge-hardening.md

**Requested by:** the founder's approved plan, step 2, 2026-10-17
**Reviewer:** codex, on its best model
**This is a post-mortem, not a build.** Append exactly one turn to
`docs/dialogue/bridge-hardening.md`, and change nothing else: no code, no config, no
other docs, no commits. Don't edit earlier turns (the file is append-only). Don't
edit anything under `~/.tools/` or `~/.codex/`. Don't start any nested `codex` run.
You don't need to run this project's Swift build or tests: the plan touched no app
code.

## What shipped

Read the plan (`docs/PLAN-bridge-hardening.md`, revised against your pre-mortem) and
the whole dialogue, then compare them with what was actually built.

- **Outside the repo (step 1):** the bridge, `~/.tools/codex-mcp-bridge/`
  (`index.js`, `runner.mjs`, `test/smoke.mjs`). Its pre-change copy is
  `~/.tools/codex-mcp-bridge.bak-2026-10-17-hardening/`. Use
  `diff -u` between the two. `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` is the
  step's test. Run it if your sandbox allows. If the sandbox blocks it (it spawns
  processes and writes into the bridge's `logs/`), say so, and don't count that as a
  failure. Its cleanup now deletes only files its own runs report.
- **In this repo (step 2, records):** commits `09f4002` (settled) and `b989f15`
  (built: `memory.md`, `PROJECT_NOTES.md`, State lines). Use `git show <sha>`.

The planner's claimed evidence: smoke 26/26 with exit 0, `logs/` listed identically
before and after the run, no `smoke-sentinel-*` file left, no leftover stand-in or
runner process, and a bridge diff holding only 1a–1e. Check what you can rather than
trusting it.

The builder reported three choices the plan left open, all in `test/smoke.mjs`:
1. `call` records every summary path it finds before throwing on a missing label.
2. One shared `makeStandDir()` serves `withBridge` and `runRunner`.
3. Case 25 checks `model: \S+ (pinned from profile)` rather than naming the models.

## What to write

Append `## codex — post-mortem — <today's date>` to
`docs/dialogue/bridge-hardening.md`, covering:

1. **What diverged** from the plan as approved, with `file:line` evidence. That
   includes anything the builder decided that the plan didn't specify.
2. **What broke, or would break**, that the plan's Verification didn't catch.
3. **What the plan should have said** to prevent each of those.
4. Whether each of your pre-mortem findings 1–7 was actually fixed as the planner's
   response promised: fixed / partly / not, with evidence.

Evidence or **unverified** for every claim. End with "No objection" for the areas you
checked and found sound.
