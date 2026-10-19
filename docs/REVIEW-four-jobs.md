# REVIEW — pre-mortem of docs/PLAN-four-jobs.md

**Requested by:** the founder, 2026-10-19
**Reviewer:** codex, on its best model
**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/four-jobs.md`. Change nothing else: no code, no config, no other docs,
no `memory.md`, no commits. Don't edit `docs/PLAN-four-jobs.md`, the intent doc or this
brief. Don't start any nested `codex` run. Running the build or tests is optional; if
you do, use `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` (and
the same flags for `swift test`). If the sandbox blocks it, say so; don't count that as
a failure.

## What you are reviewing

`docs/PLAN-four-jobs.md` is Claude's plan to simplify the Mac app around four jobs —
context, guardrails, security, projects. Read `docs/intent/INTENT-006-four-jobs.md`
first (founder-approved), then the plan. The branch is `claude/four-jobs`, cut from
`codex/project-garden` at `06ef490`, so your own Garden work is in the tree.

In short: one `Pane` enum replaces 18 `showing…` flags (B1); a sidebar with four headings
and 10 rows (B2); More's chip bar removed, with `MoreView` kept as a host and Setup's tabs
reduced (B3); the `routinesEnabled` switch shown in Setup outside Advanced Mode (B4);
Projects = Garden + Repos behind a segmented control, plus a Needs-you/notices merge,
year-so-far notices off, Zip/PDF out of the export menu, and copy fixes (B5).

## Try to break it

Check the plan against the code. The code wins over the plan.

1. **Routing (B1).** Does the `Pane` mapping preserve every current behaviour? Look
   hard at the combined flags (`showingMore` + `showingSetup`, `showingArchived`
   surviving `selectNote`, `showingReviewQueue`, `showingGetStarted`,
   `showingProfileBuilder`, `showingFirstRun`) and every place that reads a
   `showing…` flag outside `ContentView`, including `ContentView.swift:317,332,345,370,722,827`.
   Is anything left that a computed get-only property would break (a binding, `$store.showing…`)?
2. **Nothing unreachable.** Name any page, sheet, notice destination, menu command or
   button that, after the plan, points somewhere with no door or no way back. Include
   `FirstRunView`, `ProfileBuilderView`'s exits, `ConnectView`'s storage and folder
   flows, `showNotesFolder`, the corpus-fallback banner, and Capture promo flows.
3. **Nothing runs invisibly (B4).** With the plan applied, can any background work
   (routines, background agent, janitor, ingest, Claude session import) be on while its
   switch is hidden? Is the B4b copy true against `RoutineDriver.swift`, the agent and
   `IngestRunner`? Does hiding `AdvancedModeToggleCard` strand anything that only
   Advanced Mode exposed (similarity engine, embedding server)?
4. **Persisted state.** The plan claims no stored format changes. Check that
   `monthlyReviewEnabled: false` only changes the agent-settings value and nothing a
   locked decision protects, and that removing chips loses no saved preference.
5. **Projects merge (B5).** Does putting `RepoPaneView` and `ProjectGardenView` behind
   one segmented control break either one's `.task`/refresh, zoom `@AppStorage` or
   scroll behaviour? Is anything in Repos missing from what Garden shows that the
   founder's "keeping track of things like gits" needs?
6. **Builder choices.** Name anything a `build` builder would still have to decide
   because the plan leaves it open (layout, wording, ordering, where a helper lives).
7. **Unprotected invariants.** There are no app-target tests. Name anything the plan's
   §6 acceptance would let through broken, and suggest the cheapest check that would
   catch it.

## Output format

Create `docs/dialogue/four-jobs.md` following `docs/dialogue/README.md`:

```markdown
# Dialogue — four-jobs

**Plan:** docs/PLAN-four-jobs.md
**Planner:** claude
**Reviewer:** codex
**State:** open

## codex — pre-mortem — 2026-10-19

1. <finding, with file:line evidence, and what the plan should say instead>
2. ...
```

Number every finding. Mark severity (blocker / should-fix / nit). Cite `file:line` or
mark it unverified. Then stop.
