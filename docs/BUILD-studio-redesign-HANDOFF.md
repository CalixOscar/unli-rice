# Handoff: Claude runs the Studio redesign build on the Mac (in Orca)

The founder asked for this on 2026-10-30: "I am tired of copy pasting." From here on, **Claude
Code on the Mac is both planner and build driver**. Nobody relays messages between tools. Codex
is still used, but only as the builder through its CLI, and later as the post-mortem reviewer.
Read this file, then `docs/PLAN-studio-redesign.md` (the plan), `AGENTS.md` § "Builder contract",
and `memory.md`.

## Where things stand

- **Branch:** `claude/studio-redesign`. Never `main`: Mac 1.4 (9) is in App Review, and nothing
  merges to `main` until that resolves.
- **Merged and verified** (515 tests, 0 failed, 2 skipped; the Xcode build succeeded):
  - S1, `BuildGate`;
  - S2, `GardenCrate` and `StudioPalette`;
  - S4, the navigation shell.
- **S5 (Studio tab)** is on `codex/studio-S5`. Codex was applying the planner's layout
  correction (plan §2.4a, "Layout correction"). Run `git fetch`:
  - If S5 has a new commit, review it. If it is still at `31e10c4`, apply the correction
    yourself in the S5 worktree.
  - Then run the checks below, and merge S5 into `claude/studio-redesign`.
- **Still to do:** S6 (Garden crate), S7 (Guardrails & Grounding tab), S8 (QA matrix, with the
  founder), S9 (copy sync with `docs/USER_GUIDE.md`) and S10 (`PROJECT_NOTES.md`, `memory.md`,
  and asking Codex for the post-mortem).
- **Phase B** (the native Idea Clinic) stays blocked; see plan §6.

## The loop, per step

1. **Settle before handoff.** This is the main lesson so far: every builder stop came from a plan
   that left a choice open. Before S6 and S7, write a `§2.xa exact changes` section, the way §2.3a
   and §2.4a were written. That means exact files, types, properties, actions, symbols, sizes and
   palette tokens, and the existing `file:line` it builds on, checked against the current tip. If
   a choice is really the founder's (anything the intent doesn't already settle), ask the founder
   and don't guess.
2. **Build with Codex, from the terminal.** In a new worktree on `codex/studio-S<n>`, cut from
   `origin/claude/studio-redesign` (an Orca workspace is fine), run
   `codex -p build exec --cd "<worktree>" --sandbox workspace-write "<handoff>"` with the §7
   handoff. Check the `model:` and `reasoning effort:` lines against the `AGENTS.md` table.
3. **Review it yourself.**
   - `git diff --stat` shows only the step's files.
   - Read the whole diff against the step's section.
   - Run `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`.
   - For app steps, also run `xcodegen generate`, then
     `xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/unlirice-studio-derived CODE_SIGNING_ALLOWED=NO build`.
   - A small, exact deviation: fix it yourself. Anything bigger: settle the plan and rerun the
     builder. Two failed builder attempts on one step, and you take the step yourself.
4. **Merge.** Commit on the step branch, merge it `--no-ff` into `claude/studio-redesign`, and
   push. Update `memory.md` (all six fields) and the plan's `**Stage:**` line. Commit at every
   step, because a usage limit can end the session without warning.
5. **Look at it.** After S5, S6 and S7, launch the debug app against a throwaway vault
   (`UNLIRICE_DATA_PATH=<scratch>/events.jsonl /tmp/unlirice-spm-build/debug/UnliRiceApp`, or the
   bundled QA `.app` described in `memory.md`). Take a screenshot if computer use is available.
   Tell the founder in two lines what they can see now.

## Rules that still apply

- Builders never make design calls. You, the planner, do, within the approved intent.
- Never commit to `main`, push to `main`, upload to App Store Connect or bump the version.
- Never toggle "Keep working with the window closed" in a debug build. It registers a real login
  item.
- The pre-commit hooks run the secret scan and the lint checks on `memory.md` and
  `PROJECT_NOTES.md`. Don't bypass them.
- Orca: keep agent permissions on **Ask** (the founder's setting). Don't switch to yolo.
- When Claude's usage is nearly gone: stop at a merged step, update `memory.md` with the exact
  next action, push, and tell the founder which step to resume.

## When Phase A is done

S8 needs the founder's eyes. Walk them through the plan §4 matrix one row at a time, and record
each row as pass, fail or "not run, because …". Then S9 and S10. For the post-mortem, run
`codex exec` (best model, read-only) with a brief to write ONE file, its turn in
`docs/dialogue/studio-redesign.md`, and change nothing else.
