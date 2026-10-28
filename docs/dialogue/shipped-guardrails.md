# Dialogue — shipped-guardrails

**Plan:** docs/PLAN-shipped-guardrails.md
**Planner:** claude
**Reviewer:** codex
**State:** built

## claude — settled — 2026-10-16

No pre-mortem. The founder chose to skip it for Phase 1 and to build straight away;
the plan's header records the skip. Phase 2 (writing the hook into user repos) was
**not** built and still needs a pre-mortem here before anyone starts it.

Built: one new built-in House Rules preset, `engineering-guardrails`
(`Sources/UnliRiceCore/HouseRulesPreset.swift`), and two tests
(`Tests/UnliRiceCoreTests/HouseRulesTests.swift`). Both build steps went to Haiku
builders, and the planner reviewed the diff. **Unverified:** it was built in a cloud
container with no Swift, so nothing has been compiled or run.

For the post-mortem, the three calls most worth attacking:

1. The preset opens with the note-safety basics, because choosing a preset replaces
   the House Rules. Is that duplication right, or should presets compose?
2. The plan-high, build-low workflow ships as a generic rule. Does it read as
   sensible to a user with only one assistant, or as noise?
3. Plan §"Phase 1 as built", Verification check 4 (an edit survives a relaunch, and
   the built-in is unchanged) is still only a code-reading claim.
