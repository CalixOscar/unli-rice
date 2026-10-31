# Post-mortem request — studio-redesign

**Role:** reviewer (Codex). Claude was the planner. This is a **review**, not a build.
**Branch:** `claude/studio-redesign` at `91096db`, compared with `main` at `8d2189c`.
**Plan:** `docs/PLAN-studio-redesign.md` (§2 design, §2.9 the S8a–S9a additions, §3 steps, §4 QA matrix, §4a results).
**Intent:** `docs/intent/INTENT-009-studio-redesign.md`. **Spec:** `docs/SPEC-studio-redesign.md` (A1–E4).
**Dialogue:** `docs/dialogue/studio-redesign.md` — your pre-mortem and Claude's responses are already there.
**History:** `PROJECT_NOTES.md`, last entry "Studio redesign, Phase A: built and walked (2026-10-31)".

## The one task

Append exactly one turn to the end of `docs/dialogue/studio-redesign.md`:

```
## codex — post-mortem — 2026-10-31
```

followed by your post-mortem. Cover:

1. **What diverged from the plan** — compare §2/§3 and the spec ids with what `git diff 8d2189c..91096db -- Sources Tests` actually built. Cite `file:line` or a commit for each point.
2. **What broke, and whether the fix is sound** — especially S8j→S8l (accessibility tabs), S8m (unreadable folder becomes a CAN'T READ project), S8i (`ProjectIcon` folder walk: bounds, symlinks, cost on large repos), S8g (scope switch and the `BranchesDeck` task key).
3. **Your pre-mortem findings** — which ones the build actually addressed, which it did not.
4. **What the plan should have said** — concrete lessons for the next plan.
5. **Anything still wrong** that §4a marks as passing. Mark anything you could not check as "unverified".

If you run tests or builds, quote the exact command and its final line. Use `--scratch-path /tmp/unlirice-spm-codexpm` and `CLANG_MODULE_CACHE_PATH=/tmp/unlirice-clang-cache` so you don't collide with other builds.

## Hard limits

- Change **only** `docs/dialogue/studio-redesign.md`, and only by appending your one turn at the end. Do not edit earlier turns, the header, or the `**State:**` line (the planner updates it).
- Do not change any source, test, plan, notes or memory file. Do not commit, push, switch branches, or touch `main`.
- No uploads, no version bumps, no network use beyond what the build needs.
- There is nothing to "implement" here beyond writing that one turn.
