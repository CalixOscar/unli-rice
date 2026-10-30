# docs/dialogue — the Claude ↔ Codex bridge

Claude and Codex plan on their best models and build with cheaper ones. For any one
plan, one of them is the **planner** and the other is the **reviewer**. This folder
is where they talk to each other. It is a plain set of files, so it works when the
`unlirice` MCP server isn't running, and it is versioned with the code it discusses.

## One file per plan

`docs/dialogue/<slug>.md`, where `<slug>` matches `docs/PLAN-<slug>.md`. The
reviewer creates it with the pre-mortem. After that, both sides append to it, and
the post-mortem goes into the same file once the build ships.

```markdown
# Dialogue — <slug>

**Plan:** docs/PLAN-<slug>.md
**Planner:** claude | codex
**Reviewer:** codex | claude
**State:** open | settled | built | closed

## codex — pre-mortem — 2026-10-16

1. <finding, with file:line evidence>
2. ...

## claude — response — 2026-10-16

1. Accepted: plan §3 revised.
2. Declined: <reason>.

## claude — settled — 2026-10-16

Plan revised to match. Building.

## codex — post-mortem — 2026-10-20

<what diverged from the plan, what broke, what the plan should have said>

## claude — response — 2026-10-20

<reply; lessons moved to PROJECT_NOTES.md>
```

## Before a pre-mortem is asked for

The planner checks that the approved intent, the spec (`docs/SPEC-<slug>.md`) and the target
repo's `AGENTS.md` exist, and names them in the request. `CLAUDE.md` is optional. The reviewer attacks all
three, not only the plan. A missing spec is itself a finding.

**The build waits for `settled`.** No `build` or `build-light` step is handed over while
`State:` is `open`. A founder skip goes in the plan header, never in this file.

## Rules

- **Append only.** Never edit or delete the other side's turn, and never edit your
  own once the other side has replied. A correction goes in a new turn.
- **Turn kinds:** `pre-mortem`, `response`, `settled`, `post-mortem`, `rebuttal`.
  `settled` is a planner-only turn.
- **Evidence or "unverified".** A finding cites `file:line`, a commit, or a test.
  Anything that can't be checked from the repo is marked unverified.
- **The planner updates `State:`**, and that header line is the only text anyone
  edits in place.
- **Disagreement isn't settled by persistence.** After one rebuttal each way, an
  open point goes to the founder, and the turn says so.
- The dialogue is not the record of decisions. Decisions belong in
  `PROJECT_NOTES.md`, and this file is the argument that led to them.
