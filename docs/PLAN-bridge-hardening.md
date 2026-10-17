# PLAN — close the four bridge gaps from the post-mortem

**Intent:** none. This comes from Codex's post-mortem of
`docs/PLAN-codex-builder-contract.md` (findings 1–4, in
`docs/dialogue/codex-builder-contract.md`), which Claude accepted in the last
`claude — response` turn as a separate follow-up plan.
**Skips:** step 1 (intent): the four fixes were already argued and accepted in that
dialogue. **Pre-mortem:** done by Codex on 2026-10-17, in
`docs/dialogue/bridge-hardening.md` (7 findings, all answered). The post-mortem is
not skippable.
**Planner:** claude. **Reviewer:** codex.
**State:** revised against the pre-mortem; waiting for the founder's approval.
**Tier:** 1 (tooling outside the app). Every change is in the Codex bridge at
`~/.tools/codex-mcp-bridge/`. No app code, data model, persistence, server, auth or
dependency changes. The founder still approves the plan before it is built.
**Branch:** `chore/plan-high-build-low`. The bridge is not a git repo, so only this
plan and its records are committed. The bridge files are protected by a backup
(step 0).

## Why

The bridge is the small program Claude uses to hand work to Codex. The last plan
hardened it, and Codex's post-mortem found four places where it still isn't strict
enough:

1. **An empty profile name slips through.** `index.js:126` checks `if (profile)`, and
   an empty string counts as "no profile". So `profile: ""` skips the name check that
   `../x` and `Build` fail, and the run goes ahead on Codex's default (most expensive)
   model.
2. **A messy profile file is read anyway.** `readProfilePins` (`index.js:52–70`) skips
   lines it doesn't understand and keeps the first of two `model = …` lines. Codex
   showed both cases being accepted. The bridge has already written the plan by the
   time Codex itself might complain.
3. **A failed cleanup looks like a clean timeout.** When a run hits its time limit,
   `runner.mjs` signals the whole process group. But `signalGroup` (`:31–35`) hides
   every error, and the 15-second deadline (`:83`) writes the result with only
   `timedOut: true`, even if processes are still running.
4. **The smoke test can delete someone else's evidence.** `test/smoke.mjs:65,118,266`
   deletes *every* new file in the shared `logs/` folder, including a real run's logs
   if one happens at the same time. Separately, its SIGTERM check
   (`sawAliveWithoutResult`, `:229–241`) can pass before SIGTERM is even sent, so it
   doesn't prove what it claims.

## Out of scope

- **Full TOML validation, or a TOML library.** Declined in the dialogue: the profile
  files are two lines we own. Step 1 accepts a deliberately narrow subset instead.
- **A separate log folder for tests** (an environment override for `logs/`). The
  accepted fix is narrower: the test deletes only the files its own runs report.
- **An independent smoke case for an explicit `reasoningEffort` override**
  (post-mortem, pre-mortem 2 remainder). It wasn't among the accepted fixes.
- **`--disable-sandbox` in `.claude/agents/builder*.md`**: declined in the dialogue.
- **Two dispatches in the same millisecond** sharing log names (`index.js:155`). A
  bridge-wide naming issue, not one of these four. The test's no-delete guarantee
  holds only while that doesn't happen.
- **A dedicated test for ignoring ESRCH** (a group that is already gone when it is
  signalled). It can't be produced on demand; it is one comparison in `signalGroup`.
- Killing leftover processes after a *normal* Codex exit (unchanged: still recorded
  only, as `groupAliveAtExit`).

## Build steps

Labels follow `AGENTS.md` § "Builder contract": `build`, `build-light`, `planner`.

### Step 0 — `planner`: back up the bridge

`~/.tools/codex-mcp-bridge.bak-2026-10-17` already exists from the last plan and must
not be touched. Make a second backup with a different name:

```bash
test ! -e ~/.tools/codex-mcp-bridge.bak-2026-10-17-hardening && cp -R ~/.tools/codex-mcp-bridge ~/.tools/codex-mcp-bridge.bak-2026-10-17-hardening
```

If the target already exists, stop; don't overwrite it.

### Step 1 — `build`: the bridge

Files you may change: `~/.tools/codex-mcp-bridge/index.js`,
`~/.tools/codex-mcp-bridge/runner.mjs`, `~/.tools/codex-mcp-bridge/test/smoke.mjs`.
Nothing in this repo changes in this step. Its branch must still be
`chore/plan-high-build-low` with a clean tree. Line numbers below are from the
current files; the backup from step 0 is the reference.

Test names and assertion messages not given below are the builder's to write. They
don't change behaviour. Everything else here is settled.

#### 1a. `index.js`: an empty profile is refused (finding 1)

Replace line 126, `if (profile) {`, with `if (profile !== undefined) {`. Replace the
message on line 128 with exactly:

```js
return fail(`profile must match ^[a-z0-9-]+$. Got: ${JSON.stringify(profile)}`);
```

So `profile: ""` is refused with `profile must match ^[a-z0-9-]+$. Got: ""`, before
anything is written. Leave `profile || "none"` in the summary (`:217`) as it is: an
empty profile can no longer reach it.

#### 1b. `index.js`: a messy profile file is refused (finding 2)

Replace the whole `readProfilePins` function, comment included (`:50–70`), with:

```js
// Reads the root-level `model` and `model_reasoning_effort` of a profile file.
// Only lines before the first `[` table header count. Each of those must be blank, a
// comment, or a one-line `key = value` whose value is a "double-quoted" string with no
// backslash, a 'single-quoted' string, true, false, or a number. `model` and
// `model_reasoning_effort` must be quoted and set once. Anything else is refused: the
// bridge owns these files, so this is stricter than TOML on purpose.
function readProfilePins(profile) {
  const codexHome = process.env.CODEX_HOME || path.join(homedir(), ".codex");
  const profilePath = path.join(codexHome, `${profile}.config.toml`);
  const missing = `Profile ${profile} must set model and model_reasoning_effort at top level: ${profilePath}`;
  let text;
  try {
    text = readFileSync(profilePath, "utf8");
  } catch {
    return { error: missing };
  }
  const found = {};
  const lines = text.split(/\r?\n/);
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^\s*\[/.test(line)) break;
    if (/^\s*(#.*)?$/.test(line)) continue;
    const m = line.match(
      /^\s*([A-Za-z0-9_-]+)\s*=\s*(?:"([^"\\]*)"|'([^']*)'|true|false|[+-]?[0-9][0-9_]*(?:\.[0-9_]+)?)\s*(?:#.*)?$/,
    );
    const pinned = m && (m[1] === "model" || m[1] === "model_reasoning_effort");
    if (!m || (pinned && m[2] === undefined && m[3] === undefined)) {
      return { error: `Profile ${profile} has a top-level line the bridge can't read (line ${i + 1}): ${profilePath}` };
    }
    if (!pinned) continue;
    if (m[1] in found) {
      return { error: `Profile ${profile} sets ${m[1]} more than once at top level: ${profilePath}` };
    }
    found[m[1]] = m[2] ?? m[3];
  }
  if (!found.model || !found.model_reasoning_effort) return { error: missing };
  return { model: found.model, effort: found.model_reasoning_effort };
}
```

The first problem found, reading top to bottom, is the one reported. The refusal
messages are exactly the three strings in the function. The call site (`:130–131`)
is unchanged: it already refuses before the plan write at `:150–151` and the spec
write at `:188–192`. The line number is reported, not the line's text, so a refusal
never echoes file contents. A bare word such as `x = some-word`, and any backslash
inside double quotes, is refused: neither appears in a profile we write.

Both installed profiles, `~/.codex/build.config.toml` and `build-light.config.toml`,
are two comment lines plus two quoted keys, so they pass (checked 2026-10-17, and by
Codex's probe of this exact function). The smoke test re-checks them (1e, case 25).

#### 1c. `index.js`: the summary names the spec file (for finding 4)

In the summary (`:207–231`), add this line directly after the `Diagnostics:` line:

```js
`Run spec: ${specPath}`,
```

The smoke test needs every file a run creates to be named in the response, and the
spec was the only one missing. No other summary line changes.

#### 1d. `runner.mjs`: a failed cleanup is recorded (finding 3)

Replace `signalGroup` and its comment (`:30–35`) with:

```js
// Test-only, and only through the spec: test/smoke.mjs writes its own spec with
// testSignals set and runs this file directly. index.js never writes the field, so a
// real dispatch always signals for real, whatever its environment holds.
//   "drop": send no escalation signal at all.
//   "eperm": fail each one with EPERM, without sending it.
//   "send-then-eperm": send it for real, then report EPERM anyway.
const testSignals = spec.testSignals;
let signalError = null; // the first escalation-signal error that isn't ESRCH
// Signal the whole process group. ESRCH (already gone) is expected and ignored.
const signalGroup = (sig) => {
  const refused = () => Object.assign(new Error(`test: ${sig} refused`), { code: "EPERM" });
  try {
    if (testSignals === "drop") return;
    if (testSignals === "eperm") throw refused();
    process.kill(-child.pid, sig);
    if (testSignals === "send-then-eperm") throw refused();
  } catch (err) {
    if (err.code !== "ESRCH" && !signalError) {
      signalError = { signal: sig, code: err.code ?? null, message: err.message };
    }
  }
};
```

The runner reads no environment variable for this. `groupAlive` stays as it is and
is never affected by `testSignals`. It counts any error other than ESRCH as "still
alive", because only ESRCH proves the group is gone.

Add this helper directly after `groupAlive`:

```js
// What the timeout path knows about its own cleanup when it writes the result.
const cleanupFields = () => {
  const groupAliveAtResult = groupAlive();
  return { cleanupFailed: groupAliveAtResult || signalError !== null, groupAliveAtResult, signalError };
};
```

In the timeout handler, change both `finish({})` calls to `finish(cleanupFields())`:
the deadline at `:83` and the poll at `:85`. Nothing else in the runner changes: the
same 10 s SIGKILL, 15 s deadline and 250 ms poll.

Every timed-out result now carries `cleanupFailed`, `groupAliveAtResult` and
`signalError`. A clean timeout reads `false`, `false`, `null`. A normal exit's result
is unchanged: it has `groupAliveAtExit` and none of the three new fields.

#### 1e. `test/smoke.mjs`: new cases, and cleanup of its own files only (finding 4)

**Whose files this test may delete.** Only these: its own temporary folder (`work`,
from `mkdtempSync`); the five paths named in each *accepted* dispatch's summary
(`Result JSON:`, `Codex final message:`, `Event log:`, `Diagnostics:`, `Run spec:`);
and its own sentinel file (below). Nothing else in `logs/`, ever, even if it
appeared during the run. Cases 21–23 run the runner directly and keep all their
files inside `work`, so they write nothing to `logs/`.

**Rule for telling files apart in the shared `logs/`.** A new file belongs to another
run only if it can be proved: its name matches
`^(codex-.+?)\.(jsonl|err|last\.md|result\.json|spec\.json)$`, and
`<that base>.spec.json` exists, parses, and has a string `projectPath` that is not one
of this test's repos. Any other new file is a **stray**. That includes a name that
doesn't match, a missing or unparseable spec, a spec with no `projectPath`, or a spec
naming one of this test's repos. A concurrent real run can't make a stray: `index.js`
writes the spec in full before the runner creates its other files. A false failure
is acceptable; a false pass is not. Write this once, as
`strays(before, isOurs)`, where `before` is a set of file names and `isOurs(projectPath)`
decides ownership. It returns the stray names, ignoring the sentinel.

Changes:

1. **Remove** `logsBefore` (`:65`) and `logsNow` (`:118`), and the final
   sleep-and-delete loop with its comment (`:264–266`).
2. **Owned paths and runner pids.** In `call`, when the result is not an error, read
   each of the five summary labels with `^<label>: (.+)$` (multiline). If any label is
   missing, throw `summary is missing "<label>:"`, so the case fails. Push all five
   paths into a top-level `owned` array. Also read `^Runner pid: (\d+),` and push the
   number into a top-level `runners` array; a missing pid fails the case the same way.
3. **Sentinel and start snapshot.** Before the first test, record
   `startNames = new Set(readdirSync(LOG_DIR))`, then write
   `path.join(LOG_DIR, \`smoke-sentinel-${process.pid}.txt\`)`. The sentinel stands in
   for a file another run created.
4. **Cleanup** (in `finally`), in this order:
   1. Run the existing stand-in kills (`cleanups`).
   2. Wait for every pid in `runners` to be gone (`alive(pid)` false), bounded to 30 s
      in total. That replaces the 300 ms sleep: no runner may still be writing when
      files are deleted. Any runner still alive at 30 s gets `SIGKILL`, and its pid is
      kept in `stuckRunners` for case 26.
   3. `rmSync(p, { force: true })` for each path in `owned`.
   4. `rmSync(work, { recursive: true, force: true })`, as now.
5. **Case 26**, recorded after `finally` and before the summary line: "cleanup
   deletes only this run's files". It passes only if every path in `owned` is gone,
   `stuckRunners` is empty, the sentinel still exists, and
   `strays(startNames, p => p.startsWith(workReal + path.sep))` is empty, where
   `workReal = realpathSync(work)` is taken when `work` is created. Then delete the
   sentinel.
6. **No-write check.** In `expectRefused`, replace the `logsNow().length === before`
   check. Take `const before = new Set(readdirSync(LOG_DIR))` before the call, and
   after it assert `strays(before, p => p === repo)` is empty, labelled
   `<label>: no log/spec file written`. A refusal writes nothing, so any new file
   that can't be shown to be another repo's run fails the case.
7. **`runRunner({ signals })`**, a new helper for cases 21–23. It makes a repo with
   `makeRepo()` and a stand-in folder (registered in `cleanups` exactly as
   `withBridge` does), and a run folder `mkdtempSync(path.join(work, "run-"))`. In the
   run folder it writes `spec.json` with `cli: standIn`, `args: []`,
   `projectPath: repo`, `budgetSeconds: 2`,
   `baseCommit: git -C repo rev-parse HEAD`, `logPath` / `errPath` /
   `lastMessagePath` / `resultPath` as `run.jsonl` / `run.err` / `run.last.md` /
   `run.result.json` in the run folder, and `testSignals: signals`. It spawns
   `process.execPath` with `[path.join(BRIDGE_DIR, "runner.mjs"), specPath]`,
   `stdio: "ignore"`, and `env: { ...process.env, STANDIN_DIR: standDir, STANDIN_MODE: "timeout" }`.
   It pushes the runner's pid into `runners`, then returns `{ standDir, resultPath }`.
8. **The stand-in's `timeout` mode** changes its trap to
   `trap 'touch "$STANDIN_DIR/term.seen"; exit 0' TERM`, so the test knows when
   SIGTERM arrived. The group is signalled all at once, so the descendant got it too.
9. Import `homedir` from `node:os` alongside `tmpdir` (case 25).

Timing is measured with the result's own `durationSeconds` (the runner's clock), never
with the test's observation time.

Cases. The existing 13 stay, with the changes noted. New ones are marked **new**:

1–3. Profile file missing; invalid names `../x`, `Build`. The two invalid-name
   cases now also check the message `profile must match ^[a-z0-9-]+$. Got: "../x"` /
   `… Got: "Build"`.
4. **new** — `profile: ""` is refused, with `profile must match ^[a-z0-9-]+$. Got: ""`,
   and the same no-write checks. Add `""` to the invalid-name loop; use
   `JSON.stringify(bad)` in the test name.
5–6. Missing key; model only under a `[table]` (unchanged).
7. **new** — duplicate `model`: fixture
   `model = "a"\nmodel = "b"\nmodel_reasoning_effort = "low"\n`, refused with
   `Profile build sets model more than once at top level`.
8. **new** — duplicate effort: fixture
   `model = "m"\nmodel_reasoning_effort = "low"\nmodel_reasoning_effort = "high"\n`,
   refused with `Profile build sets model_reasoning_effort more than once at top level`.
9. **new** — an unreadable line: fixture
   `model = "m"\nmodel_reasoning_effort = "low"\ninvalid = [\n`, refused with
   `Profile build has a top-level line the bridge can't read (line 3)`.
10. **new** — an unquoted model: fixture
    `model = gpt-reserve\nmodel_reasoning_effort = "low"\n`, refused with
    `Profile build has a top-level line the bridge can't read (line 1)`.
11. **new** — a bare word: fixture
    `model = "m"\nmodel_reasoning_effort = "low"\nother = definitely-not-toml\n`,
    refused with `Profile build has a top-level line the bridge can't read (line 3)`.
12. **new** — a backslash in double quotes: the fixture's first line is
    `model = "gpt\u002dreserve"` with a literal backslash (in the JS source,
    `'model = "gpt\\u002dreserve"\nmodel_reasoning_effort = "low"\n'`), refused with
    `Profile build has a top-level line the bridge can't read (line 1)`.
13–15. `planFileName` omitted, `PLAN.md`, `docs/../x.md` (unchanged).
16. `docs/a/b.md` accepted (unchanged).
17. Profile pins model and effort (unchanged).
18. Explicit model wins (unchanged).
19. **new** — other root keys are allowed: fixture
    `\n# c\nmodel = "gpt-reserve"\n\nsandbox_mode = "workspace-write"\nhide_agent_reasoning = true\nmodel_context_window = 200000\n\nmodel_reasoning_effort = 'medium'\n[tools]\nweird = [1,\n`
    is accepted, and the summary says
    `model: gpt-reserve (pinned from profile), effort: medium (pinned from profile)`.
    Lines after the first table header aren't checked.
20. Timeout, rewritten, through the bridge as now. 2 s budget, `timeout` mode. Wait
    (bounded, 30 s) for `term.seen`. At that moment assert the descendant is alive
    and the result file does not exist ("descendant survived SIGTERM, result held
    back"). Then poll as now until the result exists, asserting the descendant is
    gone when it does. The result has `timedOut: true`, `durationSeconds >= 11`
    (SIGKILL comes 10 s after the 2 s budget), `cleanupFailed: false`,
    `groupAliveAtResult: false`, `signalError: null`. Remove `sawAliveWithoutResult`.
21. **new** — cleanup failed, signals dropped. `runRunner({ signals: "drop" })`. Wait
    (bounded, 30 s) for the result: it arrives about 17 s in. Assert
    `timedOut: true`, `durationSeconds >= 16` (the 15 s deadline after the 2 s budget),
    `cleanupFailed: true`, `groupAliveAtResult: true`, `signalError: null`. Wait
    (bounded) for the descendant pid in `<standDir>/desc.pid` and assert it is still
    alive. The `finally` kills it.
22. **new** — cleanup failed, signal error. As 21, with `signals: "eperm"`. Assert
    `cleanupFailed: true`, `groupAliveAtResult: true`, and `signalError.signal` is
    `"SIGTERM"` and `signalError.code` is `"EPERM"`. SIGKILL also fails, so this
    checks that the *first* error is the one kept.
23. **new** — a signal error after the group is gone.
    `runRunner({ signals: "send-then-eperm" })`. Both signals really are sent, so the
    group dies and the poll writes the result. Assert `timedOut: true`,
    `durationSeconds >= 11`, `groupAliveAtResult: false`, `cleanupFailed: true`,
    `signalError.signal === "SIGTERM"`, `signalError.code === "EPERM"`, and the
    descendant is gone.
24. Normal exit with a leftover descendant (unchanged). Also assert the result has
    none of the keys `cleanupFailed`, `groupAliveAtResult`, `signalError`.
25. **new** — the installed profiles still pass. One test, looping over `build` and
    `build-light`: copy `path.join(homedir(), ".codex", "<name>.config.toml")` into
    a fresh fixture home and dispatch with that profile. The file is read, never
    written. Assert accepted, with `(pinned from profile)` for both model and effort.
    Fail with `installed profile <name> missing` if the file doesn't exist.
26. **new** — "cleanup deletes only this run's files" (item 5 above).

Expected: `26 passed, 0 failed`, exit 0. The new runner cases add about 50 s to the
run.

Change nothing else in the bridge. Stop and report if any of 1a–1e needs a wider
change, or if a line number above doesn't hold the code described.

Verify: `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` prints `26 passed, 0 failed`
and exits 0.

### Step 2 — `planner`: verify and record

1. `diff -ru -x logs -x node_modules ~/.tools/codex-mcp-bridge.bak-2026-10-17-hardening ~/.tools/codex-mcp-bridge`
   shows only the hunks in 1a–1e. `grep -n CODEX_BRIDGE ~/.tools/codex-mcp-bridge/*.js ~/.tools/codex-mcp-bridge/*.mjs`
   finds nothing: the test switch is a spec field, not an environment variable.
2. Before running the smoke test, list `logs/` into a file. Run it myself:
   `26 passed, 0 failed`. List `logs/` again. The two lists match exactly, and no
   `smoke-sentinel-*` file remains.
3. In `memory.md`, remove the gotcha "Don't run the bridge's `test/smoke.mjs` while a
   real dispatch is running", and update all six fields. Append a `PROJECT_NOTES.md`
   entry. Commit on `chore/plan-high-build-low` through the hooks.
4. Dialogue: `State: built`, then ask Codex for the post-mortem.
5. The bridge loads at session start, so Claude Code sessions must be restarted to
   use the new code.

## Verification

- Smoke test: **26 passed, 0 failed**. That includes `profile: ""`, both duplicate
  keys, an unreadable line, an unquoted model, a bare word, a backslash, all three
  cleanup-failed results, the post-TERM liveness check, complete summaries, and the
  sentinel and stray check after cleanup.
- The installed `build` / `build-light` profiles still pass (case 25). Nothing in
  `~/.codex/` is changed.
- `logs/` holds exactly the same files before and after the smoke run (step 2.2).
- The bridge diff against the step 0 backup holds only 1a–1e. No code reads a
  `CODEX_BRIDGE_*` environment variable.
- **Not covered by a test:** a process group that survives a *real* SIGKILL, and a
  group that is already gone when signalled (ESRCH). Neither can be produced on
  purpose. Cases 21–23 reach the same `cleanupFields` code through `testSignals`.
