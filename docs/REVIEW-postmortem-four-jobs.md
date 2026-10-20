# REVIEW — post-mortem of docs/PLAN-four-jobs.md

**Requested by:** the founder, 2026-10-20
**Reviewer:** codex, on its best model
**This is a post-mortem, not a build.** Append exactly one turn to
`docs/dialogue/four-jobs.md`, headed `## codex — post-mortem — 2026-10-20`, and change
nothing else: no code, no config, no other docs, no `memory.md`, no commits. Don't edit
earlier turns or the `State:` line (the file is append-only; the planner owns `State:`).
Don't edit this brief or the plan. Don't start any nested `codex` run. Running the build
and tests is welcome: `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build`
and `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`. If the sandbox
blocks them, say so; don't count that as a failure. Do not launch the app.

## What shipped

Read the plan (`docs/PLAN-four-jobs.md`, revised against your pre-mortem, including its
Build notes and §6 Record) and the whole dialogue, then compare them with what was built.

- Code: `git diff f0c0b47..HEAD -- Sources README.md` (B1 `f9b34dc`, B2 `99fef65`,
  B3 `0b9a4cc`, B4 `ff3066b`, B5 `26dbb1a` and `b20ccf2`, walk fixes `68131cf`).
- Records: the plan's Build notes and §6, `memory.md`.
- The manual walk (B6) was done by Claude in an isolated QA copy; its results and its
  unverified items are listed in the plan's §6 Record. You can't repeat the walk; judge
  the code and the record.

## What to look for

1. **Divergence.** Where does the code differ from the plan as settled, beyond the
   deviations the Build notes already declare? Check B1's transition table writer by
   writer, B2's rows and active states, B3's tab fallback, B4's card structure and copy,
   B5's routes.
2. **Breakage.** Anything now unreachable, stale, or reading a `showing…` reader in a way
   that changed meaning (e.g. `showingMore` now true for `.archived`/`.notices`; the
   note-list branches that read `showingArchived`; `showingProfileManager`/`showingAutomation`
   readers). Any state where background work runs with its switch hidden. Copy that
   claims something the code doesn't do.
3. **Your pre-mortem findings.** Was each accepted finding actually honoured in code?
4. **Record honesty.** Do the §6 ticks and "Verified" claims overreach what the evidence
   shows? Anything marked verified that should be unverified, or vice versa?
5. **What the plan should have said.** Lessons for the next navigation change.

Number every finding with severity (blocker / should-fix / nit), cite `file:line` or a
commit, and mark anything you can't check as unverified. Then stop.
