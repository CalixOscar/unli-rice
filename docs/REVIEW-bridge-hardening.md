# REVIEW — pre-mortem of docs/PLAN-bridge-hardening.md

**Requested by:** the founder, 2026-10-17
**Reviewer:** codex, on its best model
**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/bridge-hardening.md`. Change nothing else: no code, no config, no
other docs, no commits. Don't edit `docs/PLAN-bridge-hardening.md` or this brief.
Don't edit anything under `~/.tools/` or `~/.codex/`. Don't start any nested `codex`
run. You don't need to run this project's Swift build or tests: the plan touches no
app code.

## What you are reviewing

`docs/PLAN-bridge-hardening.md` is Claude's plan for the four bridge fixes it
accepted from your post-mortem. Read your post-mortem and Claude's answer first: the
last two turns of `docs/dialogue/codex-builder-contract.md`. The plan has three
steps:

0. `planner`: a second backup of the bridge folder.
1. `build`: `index.js` (empty profile, strict profile reading, a `Run spec:` summary
   line), `runner.mjs` (cleanup-failed result, plus a test-only signal variable),
   and `test/smoke.mjs` (new cases, and deleting only its own files).
2. `planner`: verify and record.

The bridge is at `~/.tools/codex-mcp-bridge/` (`index.js`, `runner.mjs`,
`test/smoke.mjs`). Read what your sandbox allows. Running `test/smoke.mjs` is
optional; if the sandbox blocks it, say so and don't count it as a failure. It runs
today's code, not the plan's.

## Try to break it

Check the plan against the actual bridge code. The code wins over the plan.

1. **Exact code.** The plan gives near-exact code for `readProfilePins`,
   `signalGroup` and `cleanupFields`. Does each fit where the plan puts it? Do the
   line numbers match? Does the profile regex accept and refuse exactly the
   fixtures in cases 7–10, 17 and 22? Do the installed `~/.codex/build.config.toml`
   and `build-light.config.toml` still pass?
2. **Refusal before write.** Is every new refusal (`profile: ""`, duplicate key,
   unreadable line) reached before `index.js` writes the plan, spec or log?
3. **Cleanup evidence.** Can a timed-out result still look clean while the group is
   alive or a signal failed? Is the test-only `CODEX_BRIDGE_TEST_SIGNALS` variable a
   risk to a real run, and do cases 19–20 really reach the deadline path?
4. **File ownership.** Can the smoke test, as planned, still delete or miscount a
   file another run created? Does the sentinel case prove it doesn't? Does the
   `term.seen` check in case 18 really prove the descendant outlived SIGTERM?
5. **Builder choices.** Name anything a `build` builder would still have to decide
   because the plan leaves it open, such as wording, ordering or test structure.
6. **Unprotected invariants.** Name anything the plan's Verification would let
   through broken.

## Output format

Create `docs/dialogue/bridge-hardening.md` following `docs/dialogue/README.md`:

```markdown
# Dialogue — bridge-hardening

**Plan:** docs/PLAN-bridge-hardening.md
**Planner:** claude
**Reviewer:** codex
**State:** open
```

Then add one turn, `## codex — pre-mortem — <today's date>`, as numbered findings,
ranked by how badly they would hurt the build. Each one cites `file:line`, or a
command and its output, or is marked **unverified**. End with "No objection" for the
areas you checked and found sound, so silence isn't mistaken for approval.
