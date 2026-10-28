# REVIEW — post-mortem of docs/PLAN-codex-builder-contract.md

**Requested by:** the founder's approved plan, step 6, 2026-10-17
**Reviewer:** codex, on its best model
**This is a post-mortem, not a build.** Append exactly one turn to
`docs/dialogue/codex-builder-contract.md`, and change nothing else: no code, no
config, no other docs, no commits. Don't edit earlier turns (the file is
append-only). Don't start any nested `codex` run. You don't need to run this
project's build or tests unless you want to check a claim. If you do, use
`--disable-sandbox --scratch-path /tmp/unlirice-spm-build`.

## What shipped

Read the plan (`docs/PLAN-codex-builder-contract.md`, revised against your
pre-mortem) and the whole dialogue, then compare them with what was actually built.

- **In this repo:** commits `66b70c4` (step 1, preset and test), `5564919` (step 3,
  `AGENTS.md` contract), `7fabe61` (step 4, Claude's agent files and `CLAUDE.md`), and
  `9942802` (step 6, records). Use `git show <sha>`.
- **Outside the repo (step 2):** the bridge, `~/.tools/codex-mcp-bridge/`
  (`index.js`, `runner.mjs`, new `test/smoke.mjs`). Its pre-change copy is
  `~/.tools/codex-mcp-bridge.bak-2026-10-17/`. Use `diff -u` between the two.
  `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` is the step's test. Run it if your
  sandbox allows. If the sandbox blocks it (it spawns processes and writes into the
  bridge's `logs/`), say so, and don't count that as a failure.
- **Step 5:** vault edits you can't read. Mark them unverified.

The planner's claimed evidence: 383 tests, 0 failures, 2 skipped; smoke 13/13; and a
real `build-light` dispatch whose Codex session record
(`~/.codex/sessions/2026/10/17/rollout-2026-10-17T11-13-39-01a147d9-cf3c-7d40-b5bf-e38661125d4a.jsonl`)
shows `gpt-6-luna` / `low`. Check what you can rather than trusting it.

## What to write

Append `## codex — post-mortem — <today's date>` to
`docs/dialogue/codex-builder-contract.md`, covering:

1. **What diverged** from the plan as approved, with `file:line` or commit evidence.
   That includes anything a builder decided that the plan didn't specify. The planner
   knows of one: the invalid-profile-name message wording.
2. **What broke, or would break**, that the plan's Verification didn't catch.
3. **What the plan should have said** to prevent each of those.
4. Whether each of your pre-mortem findings 1–7 was actually fixed as the planner's
   response promised: fixed / partly / not, with evidence.

Evidence or **unverified** for every claim. End with "No objection" for the areas you
checked and found sound.
