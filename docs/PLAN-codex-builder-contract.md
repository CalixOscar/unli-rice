# PLAN — one builder contract for both tools

**Intent:** none. This comes from a founder request on 2026-10-17 ("answer Codex's 7
findings and draft the fixes into a plan for me to approve"), not an intent doc.
**Skips:** step 1 (intent), at founder direction. Step 3 (pre-mortem): Codex's review
of the setup, `docs/dialogue/codex-builder-setup.md`, stands in for it. The founder
confirms or overrules that at approval. The post-mortem is not skippable.
**Planner:** claude. **Reviewer:** codex.
**State:** draft, waiting for founder approval.
**Tier:** 1 (tooling, docs, and one shipped copy string). No data model, persistence,
server, auth or dependency changes.
**Branch (step 0):** stay on `chore/plan-high-build-low`. Step 1 fixes text in the
Engineering Guardrails preset, which exists only on this unmerged branch, so the fix
must land before the merge. The branch is at 6 commits ahead of `main`, under the
8-commit drift warning.

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
planner copies the folder to `~/.tools/codex-mcp-bridge.bak-<date>` first.

1. **Profile must exist.** If `profile` is given, it must match `^[a-z0-9-]+$`, and
   `$CODEX_HOME/<profile>.config.toml` (with `CODEX_HOME` defaulting to `~/.codex`)
   must exist. Otherwise return `fail("No Codex profile file: <path>. Create it or
   drop the profile.")` before anything is written or launched.
2. **Report what will actually run.** The summary line resolves the model and effort.
   Use an explicit `model` / `reasoningEffort` if given. Otherwise read `model = "…"`
   and `model_reasoning_effort = "…"` from the profile file, then from
   `~/.codex/config.toml`, with a line-level regex (no TOML dependency). Print each
   value's source, e.g.
   `Profile: build, model: gpt-reserve (profile), effort: medium (profile)`.
3. **Plans go in `docs/`.** `planFileName` becomes required and must match
   `^docs/[A-Za-z0-9._/-]+\.md$` with no `..` segment. Otherwise
   `fail("planFileName must be a .md path under docs/")`. Update the tool's input
   description to match.
4. **Timeout kills the whole run.** In `runner.mjs`, spawn Codex with
   `detached: true`. On timeout, send `SIGTERM` to the process group
   (`process.kill(-child.pid, "SIGTERM")`), then `SIGKILL` to the group 10 s later.
   Wrap both in `try/catch` for an already-exited group.
5. **`test/smoke.mjs`** checks, using a stand-in CLI script (records its arguments,
   starts `sleep 600`, waits):
   - a missing profile is refused and nothing is launched;
   - `planFileName: "PLAN.md"` and `"docs/../x.md"` are refused;
   - with a 2 s budget, the stand-in **and its `sleep` child** are gone after the
     timeout (check with `ps -o pid= -p <pid>`);
   - the summary line for `profile: build` shows `gpt-reserve (profile)`.

Change nothing else in the bridge. Stop and report if the handler's structure makes
any of 1–4 need a wider change.

Verify: `node ~/.tools/codex-mcp-bridge/test/smoke.mjs` exits 0. Restart the
`codex-bridge` MCP server (start a fresh Claude Code session) before using it.

### Step 3 — `planner`: the builder contract in `AGENTS.md`

Builders may not edit `AGENTS.md`, so the planner makes this edit. Insert after
§ "How work moves — plan high, build low":

````markdown
## Builder contract

This applies whenever a handoff says `Role: builder`: Claude's `builder` /
`builder-light` subagents, and Codex runs on the `build` / `build-light` profiles.
A planner never hands a step over without one.

A handoff names the plan (`docs/PLAN-<slug>.md`), the **one** step to build, the
branch, the files you may change, and the commands that verify it.

- Build that one step. Don't start the next one, even if it looks easy.
- Change only the files the handoff names. Needing any other file is a stop.
- Stay on the named branch. Never switch branches, commit, push or open a PR. The
  planner reviews your diff and commits it; checkpoints are the planner's.
- Don't edit `memory.md`, `PROJECT_NOTES.md`, `CLAUDE.md`, `AGENTS.md`, or anything
  in `docs/`.
- Make no design calls. If the step is ambiguous, contradicts the code, or leaves a
  choice open, stop and report it with `file:line`.
- **Circuit breaker.** After two failed attempts at the same problem, stop. After
  one, if it touches security, data integrity or a core invariant. Report what is
  wrong, what you tried, and why each attempt failed. Don't try again; the planner
  decides.
- If you add a file under `Sources/`, say so: Xcode needs `xcodegen generate`.
- Run the handoff's verification commands before you report.

Report the files you changed, each command with its pass/fail counts, and anything
you stopped on. Your report is not evidence: the planner reads the diff and reruns
the tests.

### Step labels

| Label | The job | Claude builds with | Codex builds with |
|---|---|---|---|
| `build` | a settled step that spans files | `builder` (Sonnet) | `codex -p build` (`gpt-reserve`, medium) |
| `build-light` | a small edit with the exact text given | `builder-light` (Haiku) | `codex -p build-light` (`gpt-6-luna`, low) |
| `planner` | anything a builder may not touch | the planner | the planner |

Older plans say `sonnet` / `haiku`; read them as `build` / `build-light`.

### Codex as planner: handing over a step

```bash
codex -p build exec --cd "<repo>" --sandbox workspace-write "<handoff text>"
```

`codex` may not be on `PATH`; the app ships it at
`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`. Swift builds
inside the sandbox need `--disable-sandbox` and
`--scratch-path /tmp/unlirice-spm-build`. Check the `model:` line at the top of the
run's output before accepting the result. An unknown profile may silently fall back
to the expensive default (unverified).
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
- Bridge smoke test exits 0, including the process-group kill.
- `codex -p build exec …` and `codex -p build-light exec …` still print
  `gpt-reserve` / `gpt-6-luna` (no change expected; re-run only if `~/.codex` was
  touched).
- No `sonnet` / `haiku` step labels remain except as aliases.
