# S1d build report — stopped; do not merge

Base: `5d546c3`; branch `codex/studio-S1d`. Ground check confirmed the Reading header lines block, file-order rule and six new tests in §3. The two untracked S1c files were copied as requested.

Builder model: `gpt-reserve`; reasoning effort: `medium` (matches AGENTS.md). The builder was interrupted after review found remaining core gate contract violations; the driver made no fixes.

Stops in `Sources/UnliRiceCore/BuildGate.swift`: line 101 splits away blank lines before limiting to 40, and overwrites a previous value instead of retaining the first matching header. Line 106 reads dialogue headers throughout the file rather than the first 40 physical lines. Line 113 similarly searches stage headers outside the bounded header block and without fence filtering. These disagree with §2.6's explicit rules.

Test defects: `Tests/UnliRiceCoreTests/BuildGateTests.swift:131` expects missing for a no-path Intent line where the plan requires unknown. The real-format fixture at lines 160–164 checks four-jobs through read but does not assert its required not-open result. Those defects must be corrected by an authorized builder after planner review, not waived.

Independent driver command: `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`: exit 1; 512 executed, 2 skipped, 2 failed assertions across 2 failed tests (508 passed). Failures: testHeaderSearchStopsAt40Lines and testIntentLineWithoutPathIsUnknown. The builder's earlier full-suite command also failed; its exact counts were not retained here. Driver log: `/tmp/unlirice-studio-s1d-driver.log`.

Committed files: this report only. The two implementation/test files remain untracked in the S1d worktree for inspection. No implementation is approved or committed. A new source file requires xcodegen generate before an Xcode build; none was run.

## Failure output

The implementation and tests were subsequently preserved unchanged in WIP commit `ef97808` for the planner's takeover. The earlier report describes their state at the stop.

Verbatim assertion messages from `/tmp/unlirice-studio-s1d-driver.log`:

```text
/Users/calmdownoscar/.codex/worktrees/studio-s1d/Unli Rice/Tests/UnliRiceCoreTests/BuildGateTests.swift:138: error: -[UnliRiceCoreTests.BuildGateTests testHeaderSearchStopsAt40Lines] : failed
/Users/calmdownoscar/.codex/worktrees/studio-s1d/Unli Rice/Tests/UnliRiceCoreTests/BuildGateTests.swift:131: error: -[UnliRiceCoreTests.BuildGateTests testIntentLineWithoutPathIsUnknown] : XCTAssertEqual failed: ("Optional(UnliRiceCore.BuildGate.Light.unknown("no path on the Intent line"))") is not equal to ("Optional(UnliRiceCore.BuildGate.Light.missing)")
```

The line-138 assertion logs only `failed`; it contains no expected/actual text. For line 131, the logged actual is `Optional(UnliRiceCore.BuildGate.Light.unknown("no path on the Intent line"))`; the test's expected value is `Optional(UnliRiceCore.BuildGate.Light.missing)`.

## Planner takeover (claude, 2026-10-30)

After repeated builder failures on a core invariant, the planner took S1 (AGENTS.md circuit
breaker). The changes to `BuildGate.swift`:

- **The header block** is the first 40 *physical* lines, blank lines included. The first
  occurrence of a name wins. `firstStage` and the dialogue header now go through the same
  bounded reader. Turns are still read across the whole file, in physical line order, skipping
  fenced lines.
- **Unknown-author turns** are now left out of `turns`, and not only reported in `issues`.
- **A missing Planner or Reviewer** gives `unknown("dialogue header has no planner or
  reviewer")`, where it used to give the same-tool message.
- **State** is the value's first word, so "settled (date)" counts as settled.

The changes to `BuildGateTests.swift`:

- `testIntentLineWithoutPathIsUnknown` now expects `unknown`, as the plan says.
- `testHeaderSearchStopsAt40Lines` uses blank-line padding and expects `missing` plus a Build
  light of `unknown`.
- The four-jobs fixture now asserts that the plan is not open.
- Three tests were added: `testFirstHeaderWins`, `testDialogueHeaderBeyond40LinesIsIgnored` and
  `testStateWithTrailingNoteCountsAsSettled`.

These changes were not compiled: the cloud session has no Swift. The driver's test run on the
Mac is the verification.
