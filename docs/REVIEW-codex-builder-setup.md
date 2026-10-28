# REVIEW — the Codex builder setup

**Requested by:** the founder, 2026-10-17
**Reviewer:** codex, on its best model
**This is a review, not a build.** Write exactly one file,
`docs/dialogue/codex-builder-setup.md`. Change nothing else: no code, no config, no
other docs, and no commits.

## Context

On 2026-10-17 the studio moved to "plan high, build low". Claude and Codex are both
planners. Each plans on its best model and hands build steps to cheaper models, then
reviews the diff and runs the tests itself. The other tool reviews the plan with a
pre-mortem and the shipped diff with a post-mortem, in `docs/dialogue/<slug>.md`.

Claude's builder side is written down:
- `.claude/agents/builder.md`: Sonnet, multi-file steps marked `sonnet`.
- `.claude/agents/builder-light.md`: Haiku, small, fully specified edits marked `haiku`.

Codex's builder side is much thinner:
- `AGENTS.md` § "How work moves — plan high, build low" says Codex builds with a
  smaller model, chosen per step with `codex -p build` or `codex -p build-light`.
- The profiles are `~/.codex/build.config.toml` (`gpt-reserve`, `medium`) for
  multi-file steps and `~/.codex/build-light.config.toml` (`gpt-6-luna`, `low`) for
  small mechanical edits. Verified 2026-10-17: `codex -p <name> exec` reports those
  models and efforts. The base `~/.codex/config.toml` defaults to `gpt-6.1-sol` at
  `ultra`, which neither smaller model supports. Reportedly, an unknown profile name
  is ignored without an error (unverified).
- The Codex MCP bridge (`~/.tools/codex-mcp-bridge/index.js`, tool
  `write_and_trigger_codex`) has just gained a `profile` option that passes
  `--profile`. It is outside this repo. If your sandbox can't read it, say so and
  review from this description.
- The rules every builder must follow live only in Claude's agent files: stay on the
  plan's branch, never commit, don't edit `memory.md` / `PROJECT_NOTES.md` /
  `CLAUDE.md` / `AGENTS.md` / `docs/`, stop and report on any ambiguity, and run the
  tests before reporting.

## What to review

Read the files above, plus `docs/dialogue/README.md` and
`docs/PLAN-shipped-guardrails.md` (the first change built this way). Then answer:

1. **Parity.** When Codex is the planner, what tells its builder model the rules that
   Claude's builders get from `builder.md` / `builder-light.md`? If nothing does, say
   exactly where the gap is and what the smallest fix is: an `AGENTS.md` section, a
   prompt the planner pastes, a Codex-side agent or profile instruction, or something
   else.
2. **Dispatch.** How does a Codex planner actually hand a step to the `build` or
   `build-light` profile? Is there a mechanism that works today, and does the bridge's
   new `profile` option fit it, or is the bridge only for Claude → Codex?
3. **Labels.** Plans label steps `sonnet` / `haiku`. Is "or the Codex equivalent"
   clear enough, or should plans use tool-neutral labels such as `build` and
   `build-light`?
4. **Model choice.** Do `gpt-reserve` (medium) and `gpt-6-luna` (low) suit those two
   jobs, based on what `~/.codex/models_cache.json` says about them? Mark it
   unverified where you are judging rather than citing.
5. **Failure modes.** What goes wrong first when a cheap Codex model builds from a
   Codex plan with nobody watching? Consider the circuit breaker in the vault
   guardrails ("Execution circuit breaker"), which you can't read: say so rather than
   guess its contents.

## Output format

Create `docs/dialogue/codex-builder-setup.md` following `docs/dialogue/README.md`.
Use this header:

```markdown
# Dialogue — codex-builder-setup

**Plan:** docs/REVIEW-codex-builder-setup.md
**Planner:** claude
**Reviewer:** codex
**State:** open
```

Then add one turn, `## codex — pre-mortem — <today's date>`, as numbered findings.
Each finding cites `file:line`, a config key, or a commit, or is marked
**unverified**. End with a short ranked list of recommended changes. Don't make any
of them.
