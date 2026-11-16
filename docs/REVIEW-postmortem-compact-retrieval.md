# REVIEW — post-mortem of the compact retrieval build

**Requested by:** the founder, 2026-11-16 ("Approve, carry on")
**Planner:** claude. **Reviewer:** codex, on its best model.

**This is a post-mortem, not a build.** Append exactly one turn, headed
`## codex — post-mortem — 2026-11-16`, to the end of
`docs/dialogue/compact-retrieval.md`. Do not edit any earlier turn or the header.
Change nothing else: no code, no tests, no config, no other docs, no `memory.md`,
no commits. Don't edit this brief. Don't start a nested `codex` run. Don't fix
anything you find; report it. Don't call any Unli Rice connector tool and don't
open any real `events.jsonl`.

## What you are reviewing

The shipped diff on this branch: `git diff 699d3bd..6244070` (fixed snapshot
`6244070`). Read it against:

- `docs/SPEC-compact-retrieval.md` (the requirements and their checks)
- `docs/PLAN-compact-retrieval.md` (decisions, tasks, build notes, §9)
- your own pre-mortem and the planner's response in `docs/dialogue/compact-retrieval.md`
- `docs/BENCH-compact-retrieval.md` (the recorded benchmark)

Code: `Sources/UnliRiceCore/CompactRetrieval.swift`,
`Sources/UnliRiceCore/NoteService.swift`, `Sources/UnliRiceCore/MCP/MCPToolCatalog.swift`,
`Sources/unlirice-mcp/ToolCatalog.swift`, `Sources/unlirice-mcp/ToolDispatcher.swift`.
Tests: `Tests/UnliRiceCoreTests/CompactRetrievalTests.swift`,
`CompactRetrievalBenchmarkTests.swift`, `NoteServiceTests.swift`,
`MCPToolCatalogTests.swift`, `MCPProcessTests.swift`.

You may run `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-codex`
and `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-codex`. Known:
in your sandbox 18 cases in `NativeCloudEnvironmentMigrationTests` and
`NativeCloudTransportTests` fail on temporary cloud file operations; the planner's
run outside the sandbox is 682 tests, 0 failed, 2 skipped. Report any failure
outside those two suites as a finding. If the benchmark test is skipped in your
run, say so; do not treat a skip as a pass.

## What to answer

Number your findings, give each a severity (blocker, should fix, note) and cite
`file:line`. Separate what you observed from what you infer. Mark anything you
could not check "unverified".

1. **Spec conformance.** For each of S1–S9, Q1–Q12, B1–B7 and M1–M5: is it
   implemented as written, and does a test actually exercise it (not merely exist
   with that name)? List every requirement whose test is weak, vacuous or missing.
2. **Bugs.** Try to break the code: the revision in every branch of
   `refreshProjectionLocked`; cursor decoding and its check order; the search fill
   loop's early exit (can a longer page fit after a shorter one failed?); the
   minimal-form path; excerpt placement and `excerpt_at`; batch fill, the skip for
   notes that cannot fit alone, and `retry_max_bytes`; strict argument parsing;
   anything that could exceed `max_bytes`, drop an id silently, leak text from an
   excluded note, or append an event.
3. **Existing behaviour.** Did anything in the 15 existing tools, `searchNotes`,
   `projectionSnapshot`, or any other caller of `NoteService` change?
4. **Divergence from the plan.** What was built differently from the plan and spec,
   including the choices listed under "Build notes"? Were any of them design calls
   a builder should not have made, and are they right?
5. **Benchmark honesty.** Does `docs/BENCH-compact-retrieval.md` state anything the
   test output does not support? Is the "where compact is worse" list complete? Is
   any conclusion stronger than an oracle procedure on made-up notes allows?
6. **What the plan should have said.** Lessons for the next plan.

End with a one-line verdict: fit to merge, fit to merge after the listed fixes, or
not fit to merge.
