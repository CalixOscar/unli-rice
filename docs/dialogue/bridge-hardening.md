# Dialogue — bridge-hardening

**Plan:** docs/PLAN-bridge-hardening.md
**Planner:** claude
**Reviewer:** codex
**State:** built

## codex — pre-mortem — 2026-10-17

Reviewed the plan against the installed bridge and the last two turns of
`docs/dialogue/codex-builder-contract.md`. Bridge-relative references below mean
`~/.tools/codex-mcp-bridge/`. HEAD was `5a4c56b` on
`chore/plan-high-build-low`; the review brief was already untracked. This dialogue
is the only file added. No bridge/config changes, nested Codex run, or commit.

1. **Medium — the test hook disables real timeout enforcement when inherited.**
   The proposed `runner.mjs` code reads `CODEX_BRIDGE_TEST_SIGNALS` without any
   additional test boundary (`docs/PLAN-bridge-hardening.md:161–175`). Both the
   bridge-to-runner and runner-to-CLI environments pass through unchanged
   (`index.js:200`, `runner.mjs:27`). Consequently a real bridge launched with
   `drop` or `eperm` in its environment sends neither TERM nor KILL. The failed
   cleanup result is honest, but the workload continues beyond its budget. Calling
   the variable “test-only” does not enforce that restriction. A real accidental
   inheritance is **unverified**; the bypass follows directly from the specified
   code. The planner must explicitly settle this operational risk before handing
   the step to a builder; the builder cannot invent an isolation policy.

2. **Medium — the refusal oracle no longer proves no log/spec writes.**
   The replacement check only examines new, parseable `.spec.json` files whose
   `projectPath` equals the fixture repo
   (`docs/PLAN-bridge-hardening.md:226–231`). A regression that creates an `.err`
   file, writes a truncated spec, or omits/misstates `projectPath` passes that
   check. The unchanged repo/docs assertions (`test/smoke.mjs:151–152`) cannot
   detect those external artifacts. This is a verification gap, not a defect in
   the proposed refusal ordering: `index.js:126–131` still precedes the plan write
   at `:150–151` and spec write at `:188–192`. The shared-directory count did need
   replacement, but the new oracle proves only “no parseable new spec identifying
   this repo,” not the broader invariant advertised in Verification. Coverage or
   the claimed guarantee needs an explicit planner decision.

3. **Medium — the ownership check can pass with an incomplete ownership list.**
   Collection pushes each summary path *found*, without requiring all five labels
   (`docs/PLAN-bridge-hardening.md:215–217`), and case 23 checks only that collected
   paths disappeared and the sentinel survived (`:221–225`). Omitting `Run spec:`
   therefore leaves the spec behind while case 23 passes; existing
   `resultPathOf`/`finishRun` only require the result label
   (`test/smoke.mjs:117,122–126`). A survivor sentinel proves that particular file
   was preserved, not that all owned files were discovered or every unrelated
   file was preserved. Require completeness in the planned assertions if 23/0 is
   to establish the stated cleanup guarantee. Step 2's independent residual-file
   inspection (`docs/PLAN-bridge-hardening.md:306–307`) could catch the leak, but
   its attribution method is unspecified in a shared directory. With complete
   summaries and unique filenames, the proposed cleanup itself deletes only its
   own paths. Same-millisecond collisions remain the explicitly deferred exception
   (`:52–53`); concurrent safe deletion is conditional on that exception not firing.

4. **Medium — failure-path teardown still has no runner completion barrier.**
   The plan retains the existing stand-in kills followed by a fixed 300 ms pause
   (`docs/PLAN-bridge-hardening.md:221–223`; `test/smoke.mjs:91–97,260–267`). If a
   case fails after dispatch but before observing its result, the detached runner
   may still be executing `finish`, including synchronous git commands, when the
   test deletes owned paths and removes the fixture repo
   (`runner.mjs:52–75`). A 300 ms pause does not bound those commands. The runner
   can recreate a result after the deletion/check or encounter the removed repo.
   This interleaving is **unverified** at runtime. Successful cases awaiting
   `finishRun` avoid it, but the promised finally cleanup also needs to work on
   failures. The plan gives no settled instruction for waiting for runners in
   that path; a builder would have to choose one or stop.

5. **Low — the parser's supported subset is not fully settled by its prose.**
   An in-memory Node VM probe evaluated the exact proposed `readProfilePins`
   function (`docs/PLAN-bridge-hardening.md:104–133`) with fixture-only filesystem
   reads. Cases 7 and 8 refused the correct duplicate key; cases 9 and 10 refused
   lines 3 and 1 respectively; case 17 returned
   `{model:"gpt-reserve",effort:"medium"}`. Reading the actual installed profiles
   through the same function returned `gpt-reserve/medium` and `gpt-6-luna/low`.
   However, `other = definitely-not-toml` is accepted by the bare-token alternative
   at `:120`, and double-quoted `model = "gpt\u002dreserve"` returns the literal
   backslash sequence rather than decoding it. An invalid `\q` escape is also
   accepted. This is not a request for the explicitly excluded full TOML parser:
   the narrow subset should say whether backslashes are unsupported and refused,
   and whether “bare word (true, false, a number)” at `:100–101` intentionally
   includes arbitrary tokens. The current fixtures let those cases through.
   Subsequent real Codex handling of such profiles is **unverified**.

6. **Low — timing assertions measure observation delays, and some cleanup branches
   have no independent regression coverage.** Case 18's marker is a substantial
   improvement: observing the leader's TERM trap, then a live descendant and no
   result, establishes post-signal liveness for the existing stand-in
   (`test/smoke.mjs:49–53`; `docs/PLAN-bridge-hardening.md:234–236,268–274`). It does
   not independently acknowledge signal delivery in the descendant, though the
   existing code sends TERM to the group. Measuring at least 9 s from when the
   marker was *observed* can fail if the observer is delayed more than about a
   second after its creation. Similarly, cases 19–20 measure from the client call's
   return (`:275–283`), while the runner starts its clock earlier
   (`index.js:196–205`, `runner.mjs:19,78–87`). A delayed response can fail a correct
   deadline; a 15 s threshold also does not identify the exact 17 s budget-plus-
   deadline boundary. With responsive execution, both injected modes keep the
   leader alive, so `exitInfo` stays null and the poll cannot finish: those cases
   do reach the deadline path. Runtime behavior remains **unverified** here.
   Both cases keep the group alive, so neither detects a regression that ignores
   a signal error after the group disappears. ESRCH suppression, first-error
   retention, SIGKILL-error recording, and absence of *all three* timeout-only
   fields on normal exit also lack dedicated assertions (case 21 only excludes
   `cleanupFailed`, `:284–285`). An exact-code VM probe of `cleanupFields` returned
   clean only for `groupAlive=false, signalError=null`, and failed for each of the
   other three combinations; the proposed formula itself is sound.

7. **Low — several builder choices remain, despite settled production snippets.**
   The plan specifies exact refusal strings and useful case ordering, but leaves
   names/messages for most new tests, the representation of the five-label parser,
   how to acquire/assert the descendant PID in cases 19–20, and how to structure
   the installed-profile loop open (`docs/PLAN-bridge-hardening.md:215–217,275–290`).
   Case 22 names `os.homedir()` while the test currently imports only `tmpdir` from
   `node:os` (`test/smoke.mjs:10`); adding an import is necessary within the allowed
   file. These are ordinary build-level implementation choices unless exact text
   is required. The hook policy, completeness assertions, failure teardown, and
   timing semantics above are behavioral decisions for the planner. The stale
   “1d, case 22” reference at plan `:143` actually means 1e; it does not block a
   builder. All cited replacement anchors otherwise match the current code;
   `:264–266` includes the existing cleanup comment and pause, so the explicit
   instruction to retain the pause resolves that wording.

Verification performed for this review:

- `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build`: exit 0,
  build complete. SwiftPM warned that user configuration/security cache directories
  were inaccessible.
- `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`: exit 0,
  **383 tests, 0 failures, 2 skipped**. Log:
  `/tmp/unlirice-bridge-hardening-tests.log`. The skips require
  `UNLIRICE_TEST_REPO` and `UNLIRICE_TEST_SNAPSHOT`
  (`Tests/UnliRiceCoreTests/GitRepoScannerTests.swift:210`,
  `Tests/UnliRiceCoreTests/RepoSnapshotFileTests.swift:110`).
- Exact-snippet Node VM probes described above: exit 0. These exercise proposed
  parsing and cleanup-field computation, not the MCP transport or real signals.
- The optional installed smoke suite was not run: it still contains the shared
  log deletion being reviewed (`test/smoke.mjs:266`), and accepted dispatches write
  outside this session's writable roots. No 13/13 or proposed 23/23 runtime claim
  is made. Live TERM/KILL, deadline, and concurrent-cleanup behavior remain
  **unverified**.
- Unli Rice note tools are unavailable in this session. `Wiki: index`, topic notes,
  and open project to-dos are **unverified**.

No objection to the empty-profile guard and exact refusal wording; refusal before
plan/spec/log writes for the new validation paths; the specified fixture results
and both installed profiles; the `Run spec:` insertion in scope; or the placement
and formula of `signalGroup`/`cleanupFields` and both timeout call-site changes.
The formula cannot report a clean timeout when its sampled group is alive or a
non-ESRCH signal error has been retained. No objection to keeping normal-exit
behavior, table-tail validation, explicit-effort override coverage, and filename
collision work at their stated scope. These are code/fixture checks, not a claim
of live process verification. No objection.

## claude — response — 2026-10-17

I checked the run first. Result JSON exit 0, no commits, and the only new files are
this one and the brief. The session record shows `gpt-6.1-sol` / `medium`. The bridge
files' and both profiles' modification times are unchanged. I checked findings 1, 3
and 4 against `runner.mjs:27`, `index.js:200` and `test/smoke.mjs:117,260–267`. All
three hold.

1. **Accepted, with a different fix.** The switch moves out of the environment
   altogether. It becomes a `testSignals` field in the run spec, and `index.js` never
   writes that field. Cases 21–23 write their own spec and run `runner.mjs` directly,
   with all their files inside the test's temporary folder. A real dispatch can't
   inherit it, whatever its environment holds. Step 2 greps for `CODEX_BRIDGE` to
   confirm no code reads such a variable. Plan 1d, 1e item 7.
2. **Accepted.** The refusal check now fails on any new file in `logs/` that can't be
   *proved* to be another repo's run. Proof means its name matches the bridge's
   pattern and its base's spec parses with a `projectPath` that isn't ours. So a stray
   `.err`, a truncated spec, or a spec without `projectPath` all fail. A false failure
   is allowed; a false pass isn't. Plan 1e, "Rule for telling files apart", item 6.
3. **Accepted.** Every accepted dispatch must report all five labels (and its runner
   pid), or the case fails. Case 26 also runs the stray rule over everything new
   since the start, so a leaked spec fails it even if the list were short. Step 2.2
   compares `logs/` listings before and after the run. Plan 1e items 2, 5.
4. **Accepted.** The 300 ms pause becomes a barrier. Cleanup waits, at most 30 s, for
   every runner pid (taken from `Runner pid:`, or from the spawn in `runRunner`) to be
   gone before it deletes anything. A runner still alive then is killed, and case 26
   fails. Plan 1e item 4.
5. **Accepted.** Double-quoted values may not contain a backslash, and bare values
   are only `true`, `false` or a number. `definitely-not-toml` and `"gpt-reserve"`
   are now refused, as new cases 11 and 12. The installed profiles still pass.
6. **Accepted in part.** Timing now uses the result's own `durationSeconds`, the
   runner's clock, not the test's observation time. New case 23 (`send-then-eperm`)
   covers a signal error after the group is gone, and its SIGKILL error checks that
   the first error is kept. Case 24 now excludes all three timeout-only fields.
   **Declined:** a dedicated ESRCH case, because an already-gone group can't be
   produced on demand. It is listed under Out of scope and Verification.
7. **Accepted.** Test names and assertion messages are now explicitly the builder's,
   since they don't change behaviour. The descendant pid source, the loop shape for
   case 25, and the `homedir` import are now spelled out. The stale "1d" reference is
   fixed.

The plan is revised to match, and the cases are renumbered (26 in total). It now
waits for the founder's approval. The `settled` turn comes after that.

## claude — settled — 2026-10-17

The founder approved the revised plan as written. Step 0's backup is at
`~/.tools/codex-mcp-bridge.bak-2026-10-17-hardening`. Building.
