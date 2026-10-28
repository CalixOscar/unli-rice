# REVIEW — post-mortem of docs/PLAN-memory-overhaul.md, Phase A

**Requested by:** the founder, 2026-10-29
**Reviewer:** codex, on its best model
**This is a post-mortem, not a build.** Append exactly one new turn,
`## codex — post-mortem — 2026-10-29`, to the end of `docs/dialogue/memory-overhaul.md`.
Change nothing else: no code, no config, no other docs, no `memory.md`, no commits. Don't
edit the plan, the intent, earlier dialogue turns or this brief. Don't start any nested
`codex` run. Running the build or tests is optional; if you do, use
`swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` (and the same flags
for `swift test`). If the sandbox blocks it, say so; don't count that as a failure.

## What you are reviewing

Phase A of `docs/PLAN-memory-overhaul.md` is built on branch `claude/memory-overhaul`,
commits `2324516..2e516a5`, on top of `b35b0c9` (local `main` after merging
`feature/todo-widget`; that merge included three fixes Claude made, described in its commit
message). Your pre-mortem and Claude's answers are already in `docs/dialogue/memory-overhaul.md`.
The plan's Build notes record what was verified in a running app and what was not.

Phases B and C were not built and are out of scope, except where Phase A's code makes them harder.

## Questions

1. **Diff against the plan.** Read `git diff b35b0c9..HEAD -- Sources Tests`. Where does the code
   diverge from Phase A as settled (A1–A4, decisions 4–5, the copy table)? Is each divergence
   recorded in Build notes?
2. **Your pre-mortem findings 2–9 and 21.** For each, does the code actually do what Claude's
   response promised? Cite file:line.
3. **The merge fixes in `b35b0c9`.** The widget's handoff link and To do's Open button lost
   `closeAllPanes()`; Engineering Guardrails gained a to-do paragraph and lost its `memory.md`
   example. Is anything now wrong (a note opening behind another pane, archived view state, the
   preset's own tests or intent)?
4. **Nothing runs invisibly, now in code.** Any path where bulk import or duplicate detection runs
   while its switch is off; any way an existing user loses a screen on upgrade.
5. **The unverified items in Build notes.** Which are riskiest, and what's the cheapest way to
   verify each before merging to `main`?
6. **What the plan should have said.** Lessons for Phases B and C.

## Output format

Append to `docs/dialogue/memory-overhaul.md`:

```markdown
## codex — post-mortem — 2026-10-29

1. <finding, severity (blocker / should-fix / nit), file:line evidence, suggested fix>
2. ...
```

Number every finding. Cite `file:line` or mark it unverified. Then stop.
