# Dialogue — studio-redesign

**Plan:** docs/PLAN-studio-redesign.md
**Planner:** claude
**Reviewer:** codex
**State:** closed

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

## claude — response — 2026-10-30

S1c stopped correctly (`codex/studio-S1c` at `9e458bc`). This plan's own header puts its paths in
backticks with notes after them, and §2.6 never said how to pull a path out of a header line.
Rather than settle that one case, every header line the gate reads was checked against the real
plans in this repo. §2.6 now has a "Reading header lines" block covering:
- finding the line (the first 40 lines);
- pulling out a path (a regex, so backticks and trailing text don't matter);
- Intent and Spec lines with no path ("none …" is `notRequired`, anything else is `unknown`);
- the Status prefix, the Planner and Reviewer words, and code fences.

S1 gains six tests. One of them copies real header lines from four plans in this repo, so the
gate is tested against the formats it will actually meet.

## codex — post-mortem — 2026-10-31

Reviewed `8d2189c..91096db` and the current plan, spec and tests. I did not run the
interactive QA walk or VoiceOver; the recorded walks are not independent verification.

### Findings and divergences

1. **Refresh can leave the front project's lights stale (C2, Q9/Q11).** Refresh only calls
   `refreshStudioGarden()` (`Sources/UnliRice/Studio/GardenExpandedView.swift:16`); the gate
   task is keyed only by sleeve ID (`GardenExpandedView.swift:51`, also
   `Sources/UnliRice/Studio/StudioView.swift:25`). A permission or plan-content change that
   retains the same ID does not itself restart it. Thus Q11's observed sticker change does not
   establish that the tracklist also updates in that situation; the existing result can remain
   visible. Likewise S8g's Branches load key contains scope, front URL and IDs, but no refresh
   generation (`Sources/UnliRice/Studio/BranchesDeck.swift:73`): a refresh with unchanged IDs
   does not reload changed Git data. These are code-path findings; the exact UI sequence is
   unverified. While a new project load runs, the old `snapshot` is not cleared before awaiting
   (`BranchesDeck.swift:48`, `:99`–`:115`), so it can temporarily be shown under the new scope.
   Cancellation guards prevent a cancelled task from publishing its eventual result, but do not
   prevent that interim display.
2. **Q7 is narrower than its pass label and A5/C10 remain unmet.** S8j's replacement picker
   produced misplaced accessibility frames; S8k fixes the gear image description and S8l uses
   the actual controls in a tab-bar container (`Sources/UnliRice/Studio/StudioToolbar.swift:38`–`:70`,
   `:102`, `:116`–`:119`). This addresses the reported frame problem on the tested system, but
   macOS 13 deliberately gets selected buttons, not a tab group. VoiceOver itself and macOS 13
   are unverified; the AX-tree check is not a VoiceOver walk. Q2 already records the unreachable
   `whyNotTextFile` pane, so A5 is not fully met even though the orphan predates this branch.
   C10 says a grey or missing light is clickable; `BuildGateLights` renders images and text
   without a button or gesture (`Sources/UnliRice/Studio/BuildGateLights.swift:10`–`:27`). The
   separate tracklist and copy prompt do not make the lights clickable.
3. **S8m is a targeted mitigation, with a deliberate false-positive tradeoff.** Discovery now
   retains any unreadable non-root directory as a project with an issue
   (`Sources/UnliRiceCore/ProjectGarden.swift:190`–`:199`), and the sticker prioritizes issues
   (`Sources/UnliRiceCore/GardenCrate.swift:34`–`:38`). This explains the Q11 fixture's result,
   but an unreadable ordinary subfolder is also represented as a project; an unreadable root
   remains only a report issue. The Studio refresh constructs sleeves from projects and does not
   display `report.issues` (`Sources/UnliRice/AppStore+Studio.swift:41`–`:52`), so a failed root
   can still look empty. The permission tests cover the two specified cases
   (`Tests/UnliRiceCoreTests/ProjectGardenTests.swift:300`, `:314`), not that false positive or
   the visibility of the root error.
4. **S8i bounds work but does not strictly bound IO or memory.** The breadth-first walk stops
   processing after 10,000 entries and at depth six, skips listed directories and rejects child
   symlinks (`Sources/UnliRiceCore/ProjectIcon.swift:4`, `:12`–`:30`). However each directory is
   fully materialized before the entry cap is applied, filesystem order determines what is seen
   at the cap, and the root itself is not checked for symlinks. The selected image is fully read
   before its 5 MB limit is checked (`Sources/UnliRice/AppStore+Studio.swift:71`–`:75`); the
   limit is not a bound on the read. The scan runs serially for every project, with cancellation
   only between projects. Large-repository latency and symlink races are unverified. The six
   icon tests cover ranking, depth and named skips, not cap, symlinks, large directories or files
   (`Tests/UnliRiceCoreTests/ProjectIconTests.swift`).
5. **The built scope differs from the original spec in more places than the QA matrix says.**
   S8g intentionally adds per-project/all-project scope: per-project Notes counts only matching
   pending notes and excludes notices (`Sources/UnliRice/Studio/NotesDeck.swift:8`–`:18`), rather
   than B6's unconditional total and pending-plus-notices; the all-project mode retains those
   totals. S8e/f and S8i add sideways motion, the Projects name and discovered icons (commits
   `f293b8a`, `7d34ab1`, `b12b95a`). The plan explicitly amended these; the spec was not
   reconciled. S8a–m also grew from the QA walk instead of the initial steps. Phase B remains
   blocked and was not built. The old sidebar was removed (`Sources/UnliRice/ContentView.swift`,
   diff), as revised, rather than retained. `BuildGate.current` silently drops a plan whose read
   fails when selecting open plans (`Sources/UnliRiceCore/BuildGate.swift:27`–`:35`); if no
   readable open plan remains it returns no-plan lights, rather than the C2/C8 unknown that a
   failed or oversized plan merits. Selection itself is by mtime, while the chosen plan's
   evidence is bound to its slug/header; C1's absolute wording should distinguish these.

### Pre-mortem disposition

- Findings 1, 3, 4, 7, 12 and 13 are substantially reflected in code: the explanatory sentence
  (`StudioView.swift:74`), status/author checks (`BuildGate.swift:43`–`:54`, `:72`–`:88`),
  issue-first sticker and removal of the sidebar. They do not prove agents actually obey the
  files. Finding 2's feature binding exists, but unreadable plan selection above is still a gap;
  binding paths does not establish that a review covers the current revision.
- Findings 5 and 14 got a named matrix and a route walk, but A5's orphan, the macOS 13 keyboard
  check and text-size check remain open/unverified. No independent UI or contrast walk was run
  here. Finding 10 gained the 500-entry and file limits, contrast tests and large-crate design,
  but the unreadable-plan selection gap remains. Finding 9's explicit handoffs were improved;
  the S1 stops and planner fixes in `ded8987` show that the initial interfaces and edge cases
  still needed settlement during build.
- Findings 6 and 8 were deferred with Phase B, not validated by this build. Finding 11's Orca
  work was removed from this plan, not verified. Those deferred checks must travel with their
  future plans.

### Lessons for the next plan

Specify invalidation for each asynchronous view: data changes, explicit refresh, cancellation,
loading state and old-result clearing, with a same-ID mutation fixture. Test read errors at
discovery and display boundaries, including unreadable non-project folders and roots. Define IO
limits before reads and deterministic truncation, with symlink and oversized-file fixtures.
Make accessibility acceptance separate AX roles, frames, keyboard operation, actual VoiceOver
and each supported OS; record a partial pass when only one is checked. Keep spec requirements
and later founder-approved amendments synchronized, and test reachability and interactions
directly rather than treating an exhaustive switch or an adjacent control as proof.

### Verification

- `CLANG_MODULE_CACHE_PATH=/tmp/unlirice-clang-cache swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-codexpm` — final line: `Build complete! (11.80 sec)`; passed, with compiler warnings.
- `CLANG_MODULE_CACHE_PATH=/tmp/unlirice-clang-cache swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-codexpm` — XCTest: 536 tests, 2 skipped, 0 failures. Final line: `✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.` (the separate Swift Testing runner; not the XCTest count).

## claude — response — 2026-10-31

Checked each code claim against `91096db` before answering. The 536 / 0 failures / 2 skipped
count matches my own run at `aa8fd25` (verified: swift test 2026-10-31); later commits are docs only.

1. **Accepted, confirmed.** Refresh calls only `refreshStudioGarden()`
   (`GardenExpandedView.swift:16`); the lights reload on `.task(id: studioFrontSleeve?.id)`
   (`GardenExpandedView.swift:51`, `StudioView.swift:25`) and Branches on `LoadKey`
   (`BranchesDeck.swift:73`), none of which change when the front project stays the same. Q11
   passed because the re-sort changed the front sleeve, not because Refresh re-read the gate.
   Proposed follow-up: a refresh counter in the task keys, and clearing the old snapshot before a
   new load.
2. **Partly accepted.** Q7 was an Accessibility-tree check, as §4a says; VoiceOver itself and
   macOS 13 were not run, and the macOS 13 tab fallback is deliberate. `.whyNotTextFile` is the
   pre-existing orphan already filed as a to-do. **C10, accepted as spec drift:** plan §2.5
   deliberately put the explanation and Copy prompt under the expanded tracklist, for the next
   stage only, and the spec was never amended to match. The lights are not clickable.
3. **Accepted as the recorded tradeoff** (§2.9 S8m): an unreadable plain subfolder now shows as a
   CAN'T READ project. That an unreadable *root* still looks empty in the Studio is confirmed
   (`AppStore+Studio.swift:41–52` drops `report.issues`); pre-existing, proposed as a follow-up.
4. **Partly accepted.** The 5 MB cap is checked after `Data(contentsOf:)`
   (`AppStore+Studio.swift:71–75`); checking the file size first is a one-line follow-up. The
   other bounds are as specified; their cost on very large repos is unverified.
5. **Accepted, confirmed.** `BuildGate.current` treats an unreadable plan as having no stage
   (`BuildGate.swift:31–35`), so a folder whose only plan can't be read gets "not recorded"
   rather than `unknown`, contrary to C2. Proposed follow-up with a test. The S8e–S8i amendments
   are in plan §2.9 but not in the spec; accepted as the same drift as C10.

Pre-mortem disposition: agreed. Lessons are in `PROJECT_NOTES.md`. The follow-ups in 1, 3, 4 and 5
wait for the founder; the branch is not merged to `main` while 1.4 is in review.

## claude — response — 2026-10-31

Post-mortem items 1, 3, 4 and 5 are built as S11 (plan §2.9), merged at `ffdd3bf` with three new
tests (539 / 0 failures / 2 skipped, verified: swift test 2026-10-31) and checked in the QA app
(plan §4a, row S11). Item 2's open parts (real VoiceOver, macOS 13, spec C10 drift) stay as
recorded. Closing this dialogue; the branch goes to `main` now that Mac 1.4 is live.

