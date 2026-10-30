# Dialogue — studio-redesign

**Plan:** docs/PLAN-studio-redesign.md
**Planner:** claude
**Reviewer:** codex
**State:** settled

## codex — pre-mortem — 2026-10-30

Reviewed against `f0a95b6`. This is an intent read first, then the spec and
plan. No build or UI walk was run; the mockup was not independently inspected.

1. **Must fix — the intent promises enforcement that a read-only display cannot provide.** `INTENT-009:121–124` correctly says the app enforces nothing, but then calls instructions an enforcement point. `AGENTS.md:43–60` is text read by an agent, not an execution boundary. A planner can skip reading it or use another client. State that the lights report observed artifacts and the rules request a workflow; only claim a block where a specific tested dispatcher or hook actually blocks. Distinguish the founder's desired rule from observed compliance.
2. **Must fix — mixed unrelated work can become a green pipeline.** `PLAN:185–203` selects the newest plan by filesystem modification date and independently searches for an idea, intent, spec and dialogue. An old settled review or another feature's idea can be combined with the latest plan; copying files can change mtimes. Bind all stages to an explicit feature and linked paths/revisions; ambiguous, stale, unreadable or truncated evidence must not turn green. Add fixtures for two simultaneous plans, wrong-feature and old reviews, superseded intent, and copied timestamps.
3. **Must fix — a draft spec is called done.** `SPEC:49–50` and `PLAN:190–193` accept any spec naming the intent, including this branch's own `SPEC:4` which says only ready for pre-mortem. Specify a verifiable approval/ready state and differentiate draft, missing, skipped and unknown. Likewise `PLAN:197–203` accepts any later settled or post-mortem line without checking role, feature or current revision; a stale or quoted heading is insufficient proof. Test malformed, duplicate, wrong-author, skipped and stale artifacts.
4. **Must fix — the state mapping contradicts the spec.** `SPEC:35` says a project without readable status is “can't read”; `PLAN:140–143` calls it unreadable only when it also has no repository. A Git repo with an unreadable status can therefore become “fine”. `ProjectGarden.swift:33` derives attention only from counts and does not establish read health. Specify separate missing, failed and known-clean states, including unreadable repository and notes.
5. **Must fix — the note and route requirements are not all checkable as stated.** `SPEC:21` permits at most one number and one label per collapsed deck, while `PLAN:130–132` requires an open count, a needs-you count, newest source and five titles. `SPEC:22` requires arrow keys for the crate without a version exception, but `PLAN:159` removes them on supported macOS 13. Resolve both and define keyboard focus and a macOS 13 test. A `Pane` switch compiling (`PLAN:33–34`) proves cases are handled, not that a person can reach them; explicitly walk all destinations and return paths.
6. **Must fix — sandbox access and seed persistence are underspecified.** `INTENT-009:128–135,142–143` requires saving a brief and subsequently finding a seed anywhere the app can read, while saying no new write path. A save panel is a user-authorized write and a selected save location is not automatically among persistent scan roots. Define the grant/bookmark lifecycle, restart, denied access, out-of-root saves and how a new seed is found; describe the write honestly. A root containing `docs/idea/` may also contain an existing non-Git project (`ProjectGarden.swift:179`), so the `PLAN:147–149` no-Git classification can relabel it as a seed. Test nested roots, existing memory-only projects and inaccessible directories.
7. **Must fix — Idea “not needed” is a guess.** In answer to §6.3, reject `PLAN:187–189`'s branch-count/intent heuristic: new projects can have several branches or an intent before a brief, and existing apps can have one branch. An absent marker is not proof either. Use an explicit, documented human decision with an unknown state until supplied; test both kinds of project and deliberate skips.
8. **Must fix — the Clinic parity check does not prove parity.** `PLAN:212–220` hashes the Swift tree against a checked-in constant; a consistently wrong hand-port can pass, and no pin or comparison is specified for the three prompts, routing, unknown/partial answers, escaping or path changes. In answer to §6.5, prefer one versioned, language-neutral data fixture with independent cross-language parity tests; use separate prompt fixtures or explain how prose stays in sync. A hash detects changes only relative to its chosen input, not equivalence to the website. Test all endings, changed branches, Unicode, multiline and unknowns, and verify the exact website revision before pinning it.
9. **Must fix — steps are not buildable under the builder contract.** `PLAN:262–270` lists several new files for each `build` step but omits exact API contracts, precise tests, and in places the files necessary to route or connect them. S6 needs new `Pane` routing yet excludes `AppStore.swift`/`ContentView.swift`; S7 needs actual gate/prompt integration but its file list omits shared state; S9 adds a case yet excludes the exhaustive switch (`ContentView.swift:270–302`). Builders are prohibited from design calls or editing unlisted paths (`AGENTS.md:83–92`). Settle interfaces, ownership, exact file lists, sequence and independently runnable verification before dispatch. Parallel S1–S3 (`PLAN:275`) also requires planned integration of commits and source generation across worktrees, not shared uncommitted files.
10. **Must fix — lifecycle and capacity claims lack a runnable contract.** `PLAN:206–208` caps the combined scan at 200 entries but does not say how truncation is detected, ordered or surfaced; a partial scan cannot prove missing. `PLAN:121–122,166–168` promises 60 sleeves/dots, a crate and tracklist at 960×600 without defining scrolling, long names, zoom or accessible focus. `SPEC:25` requests 4.5:1 contrast but offers only a visual walk, not a repeatable measurement. Add deterministic truncation fixtures and measurable, keyboard/VoiceOver and scaled-text checks.
11. **Must fix — cross-tool and Orca behavior is not established.** In answer to §6.4, defer Orca detection to a separate plan: `PLAN:234–238` assumes an already granted scope covers a home config or app bundle; no such grant is established. App presence does not prove runtime, worker permissions or command validity. Also `PLAN:169–170,275` does not define task creation, exact commands, safe path quoting or how review and builder worktrees exchange revisions. Validate externally before copying commands; don't advertise them as ready. The project vault's current cross-tool contract must be reconciled with any proposed orchestration rather than silently overridden.
12. **Must fix — legacy and migration handling is absent.** `AGENTS.md:43–60` proposes a new spec and agent-file gate for every app, while `PLAN:185–203` has no legacy classification or migration for existing plans lacking these artifacts; many would show missing as if new work had failed. Define legacy/not-applicable and explicit waivers without fabricating approval. A mere occurrence of `AGENTS.md` in `CLAUDE.md` (`PLAN:194–195`) does not establish that the file was actually imported or followed.
13. **Should fix — remove, don't strand, the old sidebar.** In answer to §6.1, retain it in Git history rather than adding unreachable source. `PLAN:89–91` leaves dead UI that can drift, adds Xcode source registration and complicates route coverage without providing a tested rollback. Preserve the existing accessible destinations and verify them; a revert is recoverable from the commit.
14. **Should fix — scope, QA and cost need explicit evidence.** `PLAN:64–66,270–271,278–291` relies on one manual walk for multiple complex app behaviors, but lacks a concrete test matrix for saves, first run, partial input, long output, interruption/relaunch, permissions, accessibility and narrow windows. S9's model-only tests do not verify `UserDefaults` restoration. Add named checks, reproducible fixtures and explicit unverified results; do not claim time or token savings without a baseline. Verify all plan `file:line` claims against the final base before handoff; this review spot-checked the cited items and did not independently audit every claim.

## claude — response — 2026-10-30

All fourteen findings were checked against the plan and the code, and all are accepted. The plan
was rewritten, and the spec and intent were amended to match.

1. Accepted. The intent carries an amendment: the lights report files, and the gate is a
   request to agents, not a mechanism. Plan §2.2 adds the on-screen sentence "Lights show which
   files exist in this repo."
2. Accepted. `BuildGate.read(folder:slug:)` takes every path from the named plan's header (plan
   §2.6). The modification date only picks which open plan to show, and it never picks evidence.
   Tests: `testFeatureBindingIgnoresOtherFeaturesFiles`, `testTwoOpenPlansPicksNewestButListsBoth`
   and `testCopiedTimestampDoesNotChangeEvidence`.
3. Accepted. Spec `done` needs `**Status:** approved` and the same intent. Pre-mortem `done` needs
   the header State, the reviewer as the pre-mortem's author, and a planner `settled` turn after
   the reviewer's last turn. Code-fenced headings are ignored. Tests are listed in plan S1.
   `SPEC:4` is now `approved`, so this feature's own Spec light is truthful.
4. Accepted. `GardenCrate.state` is ordered: any `issues` means can't read, before attention
   and before "no notes yet" (plan §2.5). Spec B1 is revised. Q11 covers losing read access
   mid-session.
5. Accepted. Spec A2 is revised to one picture, one headline number and at most one list of
   five. The arrow keys use `.keyboardShortcut(.leftArrow/.rightArrow)`, which is macOS 11+, so
   there is no version exception; K1 records the macOS 13 check honestly. The routing table now
   has a "Back to" column, and Q2 and Q3 walk it by mouse and by keyboard.
6. Accepted, and moved. Saving and seeds are now Phase B (plan §6). The save panel is described
   as a user-authorized write. Seeds are found only inside scan roots, using `addScanRoot(_:)`
   for a save outside them. A folder with any project marker stays a project. Phase B gets its
   own tests for nested roots, inaccessible folders and relaunch.
7. Accepted. Idea is `done` only with `docs/idea/IDEA-<slug>.md`, `notRequired` only with an
   explicit `**Idea:** not needed — reason` plan line, and otherwise `notRecorded`. The
   heuristic is gone.
8. Accepted (§6.5). The native clinic is blocked on one versioned `clinic.json`, with fixture
   answer sets and expected outputs. Both the website (Node) and the app (Swift) render the same
   fixtures. That is a CalmdownOscar change in INTENT-008's area.
9. Accepted. Every step now lists its exact files, including the `ContentView` case each one
   touches. APIs are given as Swift signatures, and tests are named. Placeholder views in new
   files keep the switch exhaustive between steps. S1 and S2 run on separate branches, and
   Claude merges them; `xcodegen` is run only by the driver.
10. Accepted. `docs/` is capped at 500 entries, with `unknown` (not `missing`) when the cap is
    hit, and tested. Above 20 sleeves the dots become "n of N" plus the List view. Long names
    wrap to two lines, with the full name in a tooltip and in VoiceOver.
    `StudioPalette.contrastRatio` makes 4.5:1 a unit test.
11. Accepted (§6.4). Orca is removed from this plan entirely, and nothing advertises Orca
    commands.
12. Accepted. A plan with no `**Spec:**` line is an older plan, and its Spec light shows
    `notRequired("older plan")`, not a failure. `CLAUDE.md` counts only with a line equal to
    `@AGENTS.md`.
13. Accepted (§6.1). The sidebar code is deleted, and git history is the rollback.
14. Accepted. Plan §4 is now a named QA matrix (Q1–Q13, K1), each row recorded as pass, fail or
    "not run, because". No savings are claimed. The driver re-checks each step's cited
    `file:line` before handing it over (plan §7, step 1).

## claude — settled — 2026-10-30

Plan revised to match (`docs/PLAN-studio-redesign.md`, stage 3). Phase A (S1–S10) may be built by
the procedure in plan §7. Phase B stays blocked until the shared clinic data file exists.

## claude — response — 2026-10-30

The build driver stopped S1 (`codex/studio-S1` at `6f75ad0`) and S2 (`codex/studio-S2` at `35be668`)
before handing them over. Both stops were right, because the plan left design calls to builders.
Settled in the plan:

- **S1.** `BuildGate.Result` gains `issues: [String]`, with the exact strings in §2.6.
  `notRecorded` is defined for exactly two cases: Idea with no marker, and every stage except
  Agents when there is no plan. The Build light and "open" now use the plan's stage number, not
  the word "built", which "not built yet" would have matched. Four tests were added to S1's list.
- **S2.** §2.8 now gives `StudioPalette`'s API, every token's hex value in both modes, and the
  exact pairs with their minimums. The ratios were computed (lowest text 4.95, lowest glyph
  3.38). One test was added to S2's list.

The rest of the dialogue still stands. The stop branches stay as they are; the next attempt
cuts fresh branches.

## claude — response — 2026-10-30

S2 (`codex/studio-S2b` at `2a001e6`) was reviewed and merged. It matched §2.5 and §2.8. One fix
was made at merge: the contrast test's failure message had lost its `\(` interpolations.

S1b stopped correctly. The plan's "after" meant later in the file, and the builder compared
dates. §2.6 now says this explicitly ("'After' means later in the file"), and S1 gains three
tests for same-day turns. The retry may start from the S1b worktree's uncommitted files, listed
under "Changes already in the tree".
