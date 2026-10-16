# PLAN — ship the engineering guardrails with the app

**Intent:** none — this came from a founder conversation, not a Spark interview.
**Stage:** 5 (build), **Phase 1 only**, at founder direction (2026-10-16). The Codex
pre-mortem was **skipped** at the founder's direction and is recorded here rather than
silently; the post-mortem is not skippable and goes in
`docs/dialogue/shipped-guardrails.md`. Phase 2 is **not** being built and still wants a
pre-mortem before anyone starts it.
**Date:** 2026-09-02
**Branch:** start a fresh one off `main` — `feature/shipped-guardrails`. This is step 0,
not step 4. `feature/languages-and-append` is 22 commits of unrelated work and is exactly
how the last plan's branch rule got ignored.

## Why

On 2026-09-02 three checks were added to the studio's own pre-commit hook
(`Scripts/check-repo-hygiene.sh`, `Scripts/lint-memory.sh`, `Scripts/check-secrets.sh`).
They exist because `PLAN-languages-and-append.md` carried two explicit rules in its own
Handoff — file the plan under `docs/`, work on a fresh branch off `main` — and **both were
ignored by the tool that read them**. The plan landed at the repo root; the build
(`79eee2f`) landed on top of 21 unrelated commits.

The founder's ask: every Unli Rice user should get the same protection out of the box, and
be able to change it later. That is a good fit, because the failure is not
calmdownoscar-specific — it is what happens to anyone whose brainstorm turns into commits
while an agent is driving.

## The split that makes this shippable

Most of the studio guardrails **must not ship**. "The studio name is calmdownoscar", the
five-stage Spark→Claude→Codex→Claude→swarm pipeline, and the App Store business rails are
one studio's internal policy; shipping them to strangers would be both wrong and useless.

What generalises is the engineering hygiene, and only that:

| Ships | Stays in the vault |
|---|---|
| memory.md is current state, capped; PROJECT_NOTES.md is history | studio identity, tool roles |
| plans and intents live in `docs/` | the five-stage pipeline |
| a claim carries its evidence, or is marked unverified | App Store business rails |
| branch drift and unbacked commits are worth seeing early | the pre-launch / post-mortem gates |
| a worktree's uncommitted files exist nowhere else | vendor and client boundaries |
| checkpoint as you go | |

Anything in the right column that leaks into a shipped preset is a defect, not a nice
extra.

## Phase 1 — a built-in House Rules preset  *(small; this is most of the value)*

`HouseRulesPreset` already does exactly what was asked: built-in presets ship with the app,
`customPresets` in `HouseRulesLocalState` holds the user's edited versions, and the type's
own docstring records the constraint that makes it safe — *"Presets are drafts only:
choosing one never writes to the note store by itself."* That is locked decision #3 already
enforced at this seam. **Do not build a new settings system.**

Add one entry to `HouseRulesPreset.builtIn` (`Sources/UnliRiceCore/HouseRulesPreset.swift:45`),
alongside `standard` and `codebase-memory`:

- `id: "engineering-hygiene"`
- `title: "Engineering Hygiene"`
- `summary: "Working state vs history, where plans live, and evidence for claims."`
- `body`: the left column above, written as instructions to an agent, in the same register
  as `codebaseMemoryBody`. Keep it under ~4,000 characters — it is prepended to real
  sessions, and `approximateTokenCount` is already surfaced in the gallery so an oversized
  preset is visible as a cost.

It appears in `HouseRulesPresetGalleryView` with no changes — the gallery renders
`builtIn` generically.

**Why this alone satisfies "out of the box, changeable later":** the preset ships, the user
picks it, edits it, and their edit is saved as a custom preset. Nothing is imposed and
nothing is overwritten.

## Phase 1 as built — revised 2026-10-16

Three founder decisions changed Phase 1 from the text above:

1. **The preset also carries the "plan high, build low" workflow**, written
   generically: plan on your best model, build on cheaper ones, have a second tool
   pre-mortem and post-mortem in `docs/dialogue/`. It is no longer studio-specific
   once the tool names come out, so it moves out of the "stays in the vault" column.
   Tool names (Claude, Codex, Sonnet, Haiku, Antigravity) stay out of the shipped
   text, because users run other tools.
2. **id `engineering-guardrails`, title "Engineering Guardrails"**, not
   `engineering-hygiene`, since it now covers more than hygiene.
3. **The body opens with the note-safety basics.** This wasn't in the original plan
   and was found while revising it. Choosing a preset *replaces* the House Rules, so a
   user who picks a hygiene-only preset would lose `source` identity, the reserved
   `janitor`/`ingest` names, and flag-don't-resolve. The `minimalist` bullets, as
   prose, go first.

The existing test `testHouseRulesPresetsContainExceptionGuardrail` requires every
built-in to contain "Exception Guardrail", so the body ends with one.

### Build steps

- **Step 1 — `haiku`.** In `Sources/UnliRiceCore/HouseRulesPreset.swift`, append a
  fourth element to `builtIn`, after `minimalist`:
  `id: "engineering-guardrails"`, `title: "Engineering Guardrails"`,
  `summary: "Working state vs history, plans in docs/, evidence, and plan high, build low."`,
  `body: engineeringGuardrailsBody`, `origin: .builtIn`. Add
  `private static let engineeringGuardrailsBody` after `minimalistBody`, containing the
  text below exactly, in the same `"""` indentation as `codebaseMemoryBody`.
- **Step 2 — `haiku`.** In `Tests/UnliRiceCoreTests/HouseRulesTests.swift`, add the two
  tests given below after `testStandardPresetUsesTheSingleDefaultBody`.
- **Verify — planner, on the Mac** (this cloud session has no Swift):
  `xcodegen generate && swift build && swift test`, plus Phase 1 checks 1, 3 and 4
  under Verification. Checks 2 and 5 are now asserted by the tests.

### The shipped text

```text
Instructions for any coding assistant working in a repository and connected to these notes over the `unlirice` MCP server.

**Notes basics.** Search before writing, and check `Wiki: index` first when it exists. Append to an existing topic; create a note only for a genuinely new concept. Titles are permanent. Pass your own lowercase tool name as `source`, and never write as `janitor` or `ingest`. Flag suspected duplicates or contradictions with `flag_for_review` rather than resolving them yourself. Nothing is deleted; archiving is soft and reversible.

**Working state and history are different files.** Keep the current state (status, task in flight, files touched, next step, gotchas) in one short file such as `memory.md`, and update it as a whole when it changes. Keep what was decided, when, and why in an append-only file such as `PROJECT_NOTES.md`. If either disagrees with the repository, the repository wins: check `git log` and `git status` before building on them.

**Plans and intents live in `docs/`.** A plan is `docs/PLAN-<slug>.md` and traces back to a statement of intent in `docs/intent/`. Never leave one at the repository root. Start the work on a fresh branch off the main branch, not on top of unrelated commits.

**A claim carries its evidence or says it is unverified.** "Tests pass" names the command and the result. Anything you could not check is marked unverified rather than stated as fact.

**Look for drift early.** A branch far behind its base, commits that exist only locally, and uncommitted files in a worktree are one lost machine away from gone. Say so when you see them.

**Checkpoint as you go.** Commit and update the working-state file at every meaningful step, not at the end. A session can end without warning.

**Plan high, build low.** Plan on the most capable model you have. Break the plan into build steps small enough for a cheaper, faster model, and label each step with the model it needs. Hand the build to that model, then review its diff and run the tests on the capable model before anything is committed. A builder never makes a design call: on an ambiguity it stops and reports back.

**A second tool reviews.** When more than one assistant works on a project, whichever one did not write a plan reviews it, with a pre-mortem before the build and a post-mortem after. Both go in `docs/dialogue/<slug>.md`: one file per plan, append-only, each turn headed with the tool, the kind of turn, and the date. Neither side edits the other's turns. A point still disputed after one rebuttal each way goes to the user.

**Exception Guardrail.** If the user asks for something that contradicts these rules, ask whether it's a one-time exception or whether the rule should change. One-time → note the exception in the session; change → update the rules.
```

### The tests

```swift
    func testBuiltInPresetIDsAreUnique() {
        let ids = HouseRulesPreset.builtIn.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testEngineeringGuardrailsPresetShipsNoStudioSpecifics() throws {
        let preset = try XCTUnwrap(HouseRulesPreset.builtIn.first { $0.id == "engineering-guardrails" })
        XCTAssertLessThan(preset.approximateTokenCount, 1_000)
        for studioOnly in ["calmdownoscar", "Spark", "Antigravity", "App Store", "Claude", "Codex", "Sonnet", "Haiku"] {
            XCTAssertFalse(preset.body.localizedCaseInsensitiveContains(studioOnly), studioOnly)
        }
        XCTAssertTrue(preset.body.contains("`janitor` or `ingest`"))
        XCTAssertTrue(preset.body.contains("flag_for_review"))
        XCTAssertTrue(preset.body.contains("docs/dialogue/"))
    }
```

## Phase 2 — offer the hook, never install it silently

The preset is advice. The hook is the thing that actually binds — that is the whole finding
above. But installing one means writing an **executable file into a git repo the app did not
create**, and this codebase already has a settled position on that class of action.

`MCPConfigWriter` is described in `PROJECT_NOTES.md:592` as *"the only code in this app that
edits a file the user owns and this app did not create"*, with three non-optional rules:
never write a file we could not read; back up before changing anything, timestamped; touch
exactly one key. And where correctness could not be guaranteed — Codex's TOML — the answer
was **paste-only, on purpose**.

A pre-commit hook is a harder case than a JSON merge: it is executable, it can block the
user's commits, and a repo may already have one from Husky, pre-commit, or lefthook.

**So v1 is paste-first**, matching the Codex TOML precedent:

1. A "Repo Guardrails" panel shows the hook and the scripts, with a Copy button and a
   Reveal in Finder — the same shape as the existing MCP setup table, which
   `PROJECT_NOTES.md:558` records was deliberately chosen over one copy-paste block.
2. **Writing is opt-in per repo, one repo at a time, never a scan-and-install sweep.**
   Under `MCPConfigWriter`'s rules, adapted:
   - **Refuse if `.git/hooks/pre-commit` exists and was not written by us.** Show the paste
     block instead. A foreign hook is someone's toolchain and replacing it wholesale is the
     failure rule 1 exists to prevent.
   - **Back up before writing**, timestamped, alongside the original.
   - **Write the hook and the scripts, nothing else.** Never touch `.git/config`, never
     stage, never commit.
3. Mark our own hook with a header line so re-running is a no-op rather than churn, the way
   a no-op MCP merge writes nothing.

**Unli Rice has no filesystem grant today.** Every part of Phase 2 needs a user-selected
folder grant with an app-scope bookmark, which the app has never asked for. That is the real
cost of this phase and the reason it is second — Phase 1 needs none of it.

## Out of scope — flag, do not decide

- **Scanning `~/Documents/Projects` for repos to fix.** That is the studio cockpit
  (`docs/PLAN-studio-cockpit.md`) and it has its own sandbox problem. This plan touches one
  repo, chosen by the user, at a time.
- **Deleting or rewriting anything in a user's repo.** No branch deletion, no `gc`, no ref
  edits. The sandbox forbids `Process` anyway, and decision #3 forbids the intent.
- **Shipping the vault's studio-specific guardrails.** See the split above.
- **Making the preset mandatory.** Nothing in this app applies a structural change on the
  user's behalf; a preset that could not be edited or ignored would break that.

## Verification

```bash
cd ~/Documents/Projects/"Unli Rice"
xcodegen generate && swift build && swift test
```

**Phase 1:**
1. House Rules gallery shows "Engineering Hygiene" beside the two existing presets.
2. Its `approximateTokenCount` renders and is under ~1,000.
3. Choosing it writes nothing to the note store until the user explicitly saves — the
   drafts-only guarantee in `HouseRulesPreset`'s docstring still holds.
4. Edit it, relaunch: the edit survives in `customPresets`, the built-in is unchanged.
5. Grep the shipped body for `calmdownoscar`, `Spark`, `Antigravity`, `App Store` — all
   must be absent. This is the defect the split above exists to catch.

**Phase 2:**
1. On a repo with no `pre-commit`: writing installs the hook and scripts, and a real commit
   then runs all four checks.
2. On a repo with a **foreign** `pre-commit` (create one with a Husky-style header): the
   write is refused and the paste block is shown. No backup is made, nothing is modified.
3. On a repo carrying **our** hook already: re-running is a no-op — no second backup, no
   rewritten file.
4. Revoke the folder grant, relaunch: the panel reports that it cannot see the repo rather
   than silently doing nothing.

## For the pre-mortem (stage 3)

The weakest assumption is that Phase 2 is worth its cost at all. It needs the app's first
filesystem grant, an App Review conversation about writing executables into a user's repo,
and a foreign-hook detection path that is easy to get subtly wrong — all to deliver
something the user could achieve by pasting four lines. Attack that first: if Phase 2 does
not survive, Phase 1 still delivers the founder's actual ask, and the honest answer may be
that Unli Rice ships the *rules* and the studio scripts stay a separate concern.

Second: whether "Engineering Hygiene" as a preset is read by anyone. The existing presets
are chosen at setup; a user who set up weeks ago never sees a new one appear.
