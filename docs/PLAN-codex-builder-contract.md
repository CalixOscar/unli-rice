# PLAN — one builder contract for both tools

**Intent:** none. This comes from a founder request on 2026-10-17 ("answer Codex's 7
findings and draft the fixes into a plan for me to approve"), not an intent doc.
**Skips:** step 1 (intent), at founder direction. **Pre-mortem:** done by Codex on
2026-10-17, in `docs/dialogue/codex-builder-contract.md` (8 findings, all answered).
The post-mortem is not skippable.
**Planner:** claude. **Reviewer:** codex.
**State:** revised against the pre-mortem (2026-10-17), waiting for founder approval.
**Tier:** 1 (tooling, docs, and one shipped copy string). No data model, persistence,
server, auth or dependency changes.
**Branch (step 0):** stay on `chore/plan-high-build-low`. Step 1 fixes text in the
Engineering Guardrails preset, which exists only on this unmerged branch, so the fix
must land before the merge. The branch is 8 commits ahead of `origin/main` with this
revision, and the build adds about four more. That passes the 8-commit drift
*warning*, which is a warning only; splitting the branch now would separate the
preset from its fix.

## Why

Codex's review (`docs/dialogue/codex-builder-setup.md`, findings 1–7, answered in the
`claude — response` turn) found that "plan high, build low" is only half written down:

- Claude's builders get their rules from `.claude/agents/builder.md`. Codex's builders
  get **no rules at all**: the two profiles set only a model and effort.
- Step labels are vendor model names (`sonnet` / `haiku`), so a Codex plan has no
  label of its own.
- The bridge accepts a profile name that has no file, reports "config default"
  instead of the real model, and defaults to writing a root-level `PLAN.md`.
- The bridge's timeout kills Codex but not processes Codex started.
- The shipped Engineering Guardrails preset says "commit at every step" one paragraph
  before saying the planner reviews before anything is committed.
- The circuit breaker lives only in the vault, which builders can't read, and its
  "write the diagnosis into `memory.md`" step is something builders may not do.

## Out of scope

- A step selector for the bridge (finding 2, declined: Claude never sends Codex a
  build step under the new roles).
- Relaxing the bridge's dirty-tree check (finding 3, declined: the planner commits
  each reviewed step before dispatching the next).
- Validating the model choices (finding 5): measured on real steps later, step 6.
- Rewording the bridge's "implement all tasks" prompt (pre-mortem 7). Review briefs
  stay explicit about their single output file instead.
- Killing leftover processes after a *normal* Codex exit. Step 2.4 only records them
  (`groupAliveAtExit`).
- The rest of the vault's `scripts/templates/PLAN.md`, which still describes the old
  pipeline ("Codex builds it at stage 5", `PREMORTEM-<slug>.md`). Step 5 changes only
  its build-step labels. Rewriting the template is separate work.

## Build steps

Labels use this plan's own new scheme: `build`, `build-light`, `planner`.

### Step 1 — `build-light`: the preset's checkpoint line

File: `Sources/UnliRiceCore/HouseRulesPreset.swift`, inside `engineeringGuardrailsBody`.

Replace this paragraph exactly:

```text
**Checkpoint as you go.** Commit and update the working-state file at every meaningful step, not at the end. A session can end without warning.
```

with:

```text
**Checkpoint as you go.** At every meaningful step, once its diff has been reviewed, commit and update the working-state file; don't wait for the end. Whoever planned the work does this, never the builder. A session can end without warning.
```

In the next paragraph, replace exactly:

```text
and label each step with the model it needs.
```

with:

```text
and label each step with the tier it needs: a full build step, or a small, fully specified edit.
```

File: `Tests/UnliRiceCoreTests/HouseRulesTests.swift`. Add this test directly after
`testEngineeringGuardrailsPresetShipsNoStudioSpecifics`:

```swift
    func testEngineeringGuardrailsCheckpointWaitsForReview() throws {
        let preset = try XCTUnwrap(HouseRulesPreset.builtIn.first { $0.id == "engineering-guardrails" })
        XCTAssertTrue(preset.body.contains("once its diff has been reviewed"))
        XCTAssertTrue(preset.body.contains("never the builder"))
        XCTAssertFalse(preset.body.contains("label each step with the model it needs"))
    }
```

Verify: `swift test --scratch-path /tmp/unlirice-spm-build --filter HouseRulesTests`,
then the full suite. Expect **383 tests, 0 failures, 2 skipped**.

### Step 2 — `build`: the bridge's checks and timeout

Files: `~/.tools/codex-mcp-bridge/index.js`, `~/.tools/codex-mcp-bridge/runner.mjs`,
new `~/.tools/codex-mcp-bridge/test/smoke.mjs`. The bridge is not a git repo, so the
planner copies the folder to `~/.tools/codex-mcp-bridge.bak-<date>` before handing
this step over. All of 1–3 run before the existing write at `index.js:114–115`, so a
refusal writes no plan, spec or log.

1. **A profile pins what runs.** If `profile` is given:
   - It must match `^[a-z0-9-]+$`.
   - `$CODEX_HOME/<profile>.config.toml` must exist and be readable, with
     `CODEX_HOME` defaulting to `~/.codex`.
   - Read its **root-level** `model` and `model_reasoning_effort`: only lines before
     the first `[` table header, `key = "value"` or `key = 'value'`, with
     surrounding whitespace and a trailing `# comment` allowed.
   - If either key is missing or the file can't be read, refuse:
     `fail("Profile <name> must set model and model_reasoning_effort at top level: <path>")`.
   - Otherwise pass both to Codex explicitly, as `--model <m>` and
     `-c model_reasoning_effort="<e>"`, alongside `--profile <name>`. An explicit
     `model` / `reasoningEffort` argument still wins over the profile's value.
   - Never fall back to `config.toml`.
2. **The summary reports pinned values and their source.** With a profile or explicit
   values: `Profile: build, model: gpt-reserve (pinned from profile), effort: medium
   (pinned from profile)`, or `(explicit)`. With neither:
   `model: Codex default (not pinned), effort: Codex default (not pinned)`. Never
   name a model the bridge didn't pass.
3. **Plans go in `docs/`.** `planFileName` stays optional in the schema, so the
   handler can give its own message. If it is omitted, refuse with
   `fail("planFileName is required: a .md path under docs/")`. If it doesn't match
   `^docs/[A-Za-z0-9._/-]+\.md$`, or has a `..` segment, refuse with
   `fail("planFileName must be a .md path under docs/")`. This deliberately breaks
   the old root `PLAN.md` default and non-`docs/` paths. Update the input
   descriptions for `planFileName` and `profile` (`index.js:85` still says profiles
   live in `config.toml`).
4. **A timeout kills the whole run before the result is written.** In `runner.mjs`:
   - Spawn Codex with `detached: true`, so its process group id is its pid.
   - On timeout, set `timedOut`, then `process.kill(-pid, "SIGTERM")`.
   - Don't write the result on the child's `exit` while the group is alive. Poll
     `process.kill(-pid, 0)` every 250 ms; when it throws `ESRCH`, write the result.
     At 10 s after SIGTERM, send `process.kill(-pid, "SIGKILL")`, wait for `ESRCH`
     (at most 5 s more), then write.
   - No escalation timer is `unref()`'d. Every signal call is wrapped in `try/catch`
     for `ESRCH`.
   - On a normal exit, kill nothing. Record `groupAliveAtExit: true|false` in the
     result.
5. **`test/smoke.mjs`** drives the real MCP handler. It uses the SDK's `Client` and
   `StdioClientTransport` against `node index.js`, with `CODEX_CLI_BIN` set to a
   stand-in script and `CODEX_HOME` set to a fixture folder, both passed through the
   transport's `env`. The target is a temporary repo with one commit. The stand-in
   writes its arguments to a file. For the timeout cases it starts a descendant
   (`sh -c 'trap "" TERM; sleep 600'`) and then waits. Liveness is checked with
   `process.kill(pid, 0)`, never `ps`. Cases:
   - Profile file missing, invalid name (`../x`, `Build`), or missing a key: refused,
     and no plan, spec or log file is written.
   - `planFileName` omitted, `PLAN.md`, `docs/../x.md`: refused. `docs/a/b.md`:
     accepted.
   - `profile: build` with a fixture setting `gpt-reserve` / `medium`: the recorded
     arguments contain `--model gpt-reserve` and `model_reasoning_effort="medium"`,
     and the summary says `(pinned from profile)`. With an explicit `model`, the
     explicit value is passed and the summary says `(explicit)`.
   - A fixture with `model = "x"` only under a `[table]`: refused as missing.
   - Timeout, 2 s budget: the stand-in leader exits on TERM while its descendant
     ignores TERM. The result file does not exist until the descendant is gone. The
     descendant is gone within 16 s, and the result has `timedOut: true`.
   - Normal exit with a leftover descendant: `groupAliveAtExit: true`.
   - Every wait is bounded (30 s), and every stand-in process is killed in
     `finally`.

Change nothing else in the bridge. Stop and report if any of 1–4 needs a wider
change.

Verify: `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` exits 0. Restart the
`codex-bridge` MCP server (start a fresh Claude Code session) before using it.

### Step 3 — `planner`: the builder contract in `AGENTS.md`

Builders may not edit `AGENTS.md`, so the planner makes this edit. Insert after
§ "How work moves — plan high, build low":

````markdown
## Builder contract

This applies whenever a handoff starts with `Role: builder`: Claude's `builder` /
`builder-light` subagents, and Codex runs on the `build` / `build-light` profiles. A
profile only picks a model; the handoff is what makes a run a builder. A planner
never hands a step over without one.

A handoff carries these fields, all required:

```text
Role: builder
Plan: docs/PLAN-<slug>.md
Step: <step id and title, exactly as in the plan>
Branch: <branch name, never main>
Files you may change: <paths>
Changes already in the tree: none
Verify with: <commands>
```

- Build that one step. Don't start the next one, even if it looks easy.
- Change only the files the handoff names. Needing any other file is a stop.
- Work only on the named branch, and never on `main`. If the checked-out branch isn't
  the one named, or the tree has changes the handoff didn't list, stop before
  touching anything. Never switch branches, commit, push or open a PR. The planner
  reviews your diff and commits it; checkpoints are the planner's.
- Don't edit `memory.md`, `PROJECT_NOTES.md`, `CLAUDE.md`, `AGENTS.md`, or anything
  in `docs/`.
- Make no design calls. If the step is ambiguous, contradicts the code, or leaves a
  choice open, stop and report it with `file:line`.
- **Circuit breaker.** After two failed attempts at the same problem, stop. Stop
  after one if it touches security, data integrity, a core invariant or the
  architecture. Report what is wrong, what you tried, and why each attempt failed.
  Don't try again; the planner decides.
- If you add a file under `Sources/`, say so: Xcode needs `xcodegen generate`.
- Run the handoff's verification commands before you report.

Report the files you changed, each command with its pass/fail counts, and anything
you stopped on. Your report is not evidence: the planner reads the diff and reruns
the tests.

### Step labels

| Label | The job | Claude builds with | Codex builds with |
|---|---|---|---|
| `build` | a settled implementation step that still needs care in *how* it is written, in one file or many | `builder` (Sonnet) | `codex -p build` (`gpt-reserve`, medium) |
| `build-light` | a small edit where the plan gives the exact text | `builder-light` (Haiku) | `codex -p build-light` (`gpt-6-luna`, low) |
| `planner` | anything a builder may not touch, or that needs a design call | the planner | the planner |

Older plans say `sonnet` / `haiku`; read them as `build` / `build-light`.

### Codex as planner: handing over a step

```bash
codex -p build exec --cd "<repo>" --sandbox workspace-write "$(cat <<'HANDOFF'
Role: builder
Plan: docs/PLAN-<slug>.md
Step: <id and title>
Branch: <branch>
Files you may change: <paths>
Changes already in the tree: none
Verify with: <commands>

Follow AGENTS.md § "Builder contract".
HANDOFF
)"
```

`codex` may not be on `PATH`; the app ships it at
`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`. Swift builds
inside the sandbox need `--disable-sandbox` and
`--scratch-path /tmp/unlirice-spm-build`. Before accepting the result, check the
`model:` and `reasoning effort:` lines at the top of the run's output against the
table. Whether a profile with no file silently falls back to the expensive default
is unverified.
````

In § "How work moves", replace "Claude uses Sonnet or Haiku subagents, and Codex
uses a smaller Codex model, chosen per step with `codex -p build` (multi-file steps)
or `codex -p build-light` (small mechanical edits). Each profile is its own file,
`~/.codex/<name>.config.toml`." with "Each step carries a label, and the table under
§ "Builder contract" maps it to a model. Each Codex profile is its own file,
`~/.codex/<name>.config.toml`."

### Step 4 — `planner`: Claude's side points at the contract

- `.claude/agents/builder.md`: description becomes "Builds one `build` step (alias
  `sonnet`) from a settled docs/PLAN-<slug>.md, under AGENTS.md § Builder contract.
  Never makes design calls." The body becomes one opening line, "Read `AGENTS.md`
  § "Builder contract" first and follow it exactly", plus the Unli Rice-specific
  lines the contract doesn't cover: `swift test` with
  `--scratch-path /tmp/unlirice-spm-build`, and the report format.
- `.claude/agents/builder-light.md`: the same, for `build-light` (alias `haiku`).
  Keep its line that anything needing judgement goes to `builder`.
- `CLAUDE.md:39`: "labelled `sonnet` or `haiku`" becomes "labelled `build`,
  `build-light` or `planner` (the table is in `AGENTS.md` § "Builder contract")".

### Step 5 — `planner`: the vault

- `_AI Context/04_Guardrails.md`, Tier 2 step 2: "labels each step `sonnet` or
  `haiku` (or the Codex equivalent)" becomes "labels each step `build`,
  `build-light` or `planner`; the mapping to models is in each repo's `AGENTS.md`
  § "Builder contract"". Under "### Dispatching Codex", add: "The bridge refuses a
  profile with no file and a plan path outside `docs/`."
- `scripts/templates/PLAN.md`: wherever it asks for build steps, ask for a label per
  step (`build` / `build-light` / `planner`). Nothing else in the template changes
  (see Out of scope).
- Re-run `install-studio-hooks.sh` only if a script changed. None should.

### Step 6 — `planner`: verify, record, hand to review

1. Review step 1's and step 2's diffs. Run the full suite (expect 383 / 0 / 2) and
   `node ~/.tools/codex-mcp-bridge/test/smoke.mjs`.
2. `grep -rn "\`sonnet\`\|\`haiku\`" CLAUDE.md AGENTS.md .claude/agents` finds only the
   alias mentions.
3. Commit per step on `chore/plan-high-build-low` through the hooks. Update
   `memory.md` (all six fields) and append a `PROJECT_NOTES.md` entry.
4. Dialogue: `State: built`, then ask Codex for the post-mortem.
5. Later, not part of this build: on the first two Codex-built steps, record in
   `PROJECT_NOTES.md` whether `gpt-reserve` / `gpt-6-luna` held up (finding 5), and
   whether a nested `codex exec` works from inside the bridge sandbox (finding 2).

## Verification

- Full suite: **383 tests, 0 failures, 2 skipped**, including
  `testEngineeringGuardrailsCheckpointWaitsForReview`.
- Bridge smoke test exits 0, covering every case in step 2.5, including a
  descendant that ignores SIGTERM.
- One real dispatch through the restarted bridge with `profile: build-light`, into a
  throwaway one-commit repo with a one-line review brief. Its log's `model:` and
  `reasoning effort:` lines read `gpt-6-luna` / `low`. That confirms explicit
  pinning reaches Codex. The smoke test only checks the arguments.
- `codex -p build exec …` and `codex -p build-light exec …` still print
  `gpt-reserve` / `gpt-6-luna` (no change expected; re-run only if `~/.codex` was
  touched).
- No `sonnet` / `haiku` step labels remain except as aliases.
