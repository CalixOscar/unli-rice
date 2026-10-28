# REVIEW — pre-mortem of docs/PLAN-codex-builder-contract.md

**Requested by:** the founder, 2026-10-17
**Reviewer:** codex, on its best model
**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/codex-builder-contract.md`. Change nothing else: no code, no config,
no other docs, no commits, and don't edit `docs/PLAN-codex-builder-contract.md`.
Don't start any nested `codex` run.

## What you are reviewing

`docs/PLAN-codex-builder-contract.md` is Claude's plan to fix the findings from your
earlier review. Read that review and Claude's response first:
`docs/dialogue/codex-builder-setup.md`. The plan has six steps:
1. `build-light`: a preset text fix plus a test.
2. `build`: bridge checks and the process-group timeout kill.
3. `planner`: a Builder contract in `AGENTS.md`.
4. `planner`: Claude's agent files point at that contract.
5. `planner`: vault edits.
6. `planner`: verify and record.

The files it touches outside this repo are `~/.tools/codex-mcp-bridge/index.js`,
`~/.tools/codex-mcp-bridge/runner.mjs`, `~/.codex/*.config.toml`, and (step 5 only)
the vault, which you can't read. Read what your sandbox allows, and mark the rest
**unverified**.

## Try to break it

Check the plan against the repo and the bridge code. `git log` and `git diff`: the
repo wins over the plan. In particular:

1. **Exact text.** Step 1 is `build-light`, so its old strings must match the source
   exactly, once each, and its new test must compile and pass. Is "383 tests, 0
   failures, 2 skipped" the right expectation?
2. **Bridge feasibility.** Do step 2's items 1–4 fit the actual structure of
   `index.js` and `runner.mjs`? Note that `index.js` already spawns the runner
   detached. Does `detached: true` plus `process.kill(-pid)` in the runner actually
   reach Codex's descendants? Does making `planFileName` required break any existing
   caller? Can `test/smoke.mjs` exercise the MCP handler without a real Codex?
3. **The contract.** Does the `AGENTS.md` Builder contract (step 3) contradict
   anything already in `AGENTS.md`, `CLAUDE.md`, `docs/dialogue/README.md`, or the
   shipped preset? Would a Claude subagent actually read `AGENTS.md` when
   `builder.md` tells it to (step 4)? Is anything a builder needs missing from the
   handoff fields?
4. **Labels.** Does the `build` / `build-light` / `planner` scheme leave any step
   un-labellable, or clash with `build` as a word used elsewhere, such as the bridge's
   "build" wording or the `build` profile name?
5. **Declined items.** Claude declined a bridge step selector and a relaxed
   dirty-tree check. Challenge those reasons if they are wrong.
6. **Unprotected invariants.** Name anything the plan's Verification section would
   let through broken.

## Output format

Create `docs/dialogue/codex-builder-contract.md` following `docs/dialogue/README.md`:

```markdown
# Dialogue — codex-builder-contract

**Plan:** docs/PLAN-codex-builder-contract.md
**Planner:** claude
**Reviewer:** codex
**State:** open
```

Then add one turn, `## codex — pre-mortem — <today's date>`, as numbered findings,
each with `file:line`, a commit, or a command and its output as evidence, or marked
**unverified**. Rank them by how badly they would hurt the build. End with "No
objection" for any area you checked and found sound, so silence isn't mistaken for
approval.
