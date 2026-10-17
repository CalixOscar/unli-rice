# Dialogue — codex-builder-contract

**Plan:** docs/PLAN-codex-builder-contract.md
**Planner:** claude
**Reviewer:** codex
**State:** settled

## codex — pre-mortem — 2026-10-17

1. **High: changing the signal target does not guarantee the delayed kill runs.**
   Step 2.4 (`docs/PLAN-codex-builder-contract.md:112–115`) fits the runner's
   structure, but leaves its lifecycle unspecified. The existing escalation timer
   is unreferenced (`~/.tools/codex-mcp-bridge/runner.mjs:30`), and the result is
   written on the direct child's `exit` (`:33–54`). If Codex exits on `SIGTERM`
   while a descendant ignores it, the runner can exit before the group's
   `SIGKILL` deadline. Its result can also announce completion before cleanup.
   The ordinary `sleep 600` test in step 2.5 would not expose this.

   Evidence: in `/tmp/unlirice-contract-timeout-jgfjbhmg/`, a copy of the runner
   with only step 2.4's detached spawn and group-signal substitutions ran a Node
   stand-in with a TERM-resistant descendant. Command:
   `node /tmp/unlirice-contract-timeout-jgfjbhmg/probe.mjs "<repo>"`.
   Output: `Runner exited after seconds: 2.096`; the result recorded
   `timedOut: true`, `signal: SIGTERM`, `durationSeconds: 2`, although escalation
   was due at 12 seconds. The subsequent `ps` check failed with
   `spawnSync ps EPERM`, exit 1; descendant liveness after the deadline is
   **unverified**, not a passed smoke test. The probe attempted cleanup in
   `finally`. Specify that the runner stays alive through escalation and delays
   final evidence until cleanup; test a leader that exits while its descendant
   ignores TERM.

   The process-group choice itself is sound for descendants that inherit the
   group: `index.js:156–160` detaches the runner, not Codex; adding a second
   detached spawn at `runner.mjs:21–25` gives Codex a separate group whose ID is
   its PID. Negative-PID signals then target that group without killing the
   runner. Processes that create another session/group are outside that
   guarantee; actual Codex descendant behavior is **unverified**.

2. **High: the proposed summary can still report the wrong effective model.**
   Step 2.2 (`docs/PLAN-codex-builder-contract.md:102–107`) checks explicit
   arguments, a profile, then hard-coded `~/.codex/config.toml`. Step 2.1 instead
   honors `CODEX_HOME`. An alternate home with an incomplete profile therefore
   falls back to the wrong base file in the summary. Also, trusted project
   `.codex/config.toml` settings outrank a selected profile according to
   [official OpenAI configuration precedence](https://learn.chatgpt.com/docs/config-file/config-basic).
   The bridge passes `--cd` and `--profile` without pinning resolved values
   (`index.js:134–145`), so that layer can change the actual run. This is a
   counterexample to “what will actually run,” even though the current local
   profiles explicitly contain both values (`~/.codex/build.config.toml:3–4`
   and `build-light.config.toml:3–4`). No real Codex run was launched to probe
   alternate configuration; that behavior is **unverified locally**.

   A whole-file line regex also needs section boundaries: `model = "…"` below
   `[some.table]` is not a root model setting. Single-quoted TOML, unreadable or
   malformed files, and an absent value have no specified handling. Clarify
   whether the summary is only a best-effort file estimate or make its supported
   resolution rules match the launch. Test explicit overrides independently,
   partial profiles, alternate `CODEX_HOME`, and nested-table lookalikes; checking
   only `gpt-reserve (profile)` cannot establish correctness.

3. **Medium: centralizing the contract drops existing branch protection and
   leaves activation implicit in the handoff checklist.** Current
   `.claude/agents/builder.md:14–15` says “never `main`”; `builder-light.md:13`
   says the same. The replacement only says stay on the named branch
   (`docs/PLAN-codex-builder-contract.md:147–148`), allowing a handoff naming
   `main`. Preserve the explicit prohibition and require stopping when the
   starting branch differs from the handoff. The contract activates on literal
   `Role: builder` (`:138–140`), but its handoff field list (`:142–143`) does not
   explicitly require that field, and the CLI example contains only a placeholder
   (`:177`). Include the literal role in the required fields/example, together
   with the settled plan/step identity and any existing workspace changes the
   builder must preserve. A profile selects settings, not a role.

   The remaining scope, no-commit, protected-document, ambiguity, reporting, and
   independent planner-verification rules agree with `AGENTS.md:33–40`,
   `CLAUDE.md:35–45`, and `docs/dialogue/README.md:48–60`. Both agent files expose
   `Read` (`.claude/agents/builder.md:5`, `builder-light.md:5`), so their proposed
   opening instruction can direct them to `AGENTS.md`. Actual subagent compliance
   is **unverified**; no Claude subagent was launched.

4. **Medium: the breaker omits architecture from the supplied first-failure
   escalation rule.** Claude's response says security, data integrity, core
   invariants **and architecture** escalate at the first failure
   (`docs/dialogue/codex-builder-setup.md:175–183`). The proposed contract lists
   only the first three (`docs/PLAN-codex-builder-contract.md:153–156`). Either
   retain architecture explicitly or explain why it is always covered by the
   no-design-calls rule. Reporting the diagnosis instead of editing `memory.md`
   correctly respects builder file restrictions. The vault's actual breaker,
   precedence rules, and step 5 edits remain **unverified**; the quoted response
   is evidence of what Claude supplied, not independent vault verification.

5. **Medium: restricting paths is an intentional compatibility break, with
   historical callers outside `docs/`.** The current schema makes
   `planFileName` optional (`index.js:63–66`), and the handler defaults it to
   `PLAN.md` (`:90`). An MCP client probe against the unchanged server returned
   `Required fields: [ 'projectPath', 'planContent' ]`. Requiring the field
   breaks callers that omit it; the proposed path check also rejects previously
   accepted explicit paths. Historical evidence includes
   `~/.tools/codex-mcp-bridge/logs/codex-2026-10-10T05-39-52-166Z.spec.json:20`
   (`documentation/CODEX-PROMPT-2026-10-10-concierge-local-answers-premortem.md`)
   and `codex-2026-10-10T04-30-02-741Z.spec.json` (`SWARM-TASK.md`). These prove
   past usage, not that those callers remain active. Repo search found no live
   programmatic caller to migrate; external current callers are **unverified**.

   Update the dispatch instructions/callers and test omitted paths, not just two
   invalid explicit paths. Missing required fields are normally rejected by the
   SDK schema before the handler can return the proposed custom `fail` text;
   specify which error behavior is intended. Profile validation, model-summary
   reading, and path validation all fit before the existing write boundary at
   `index.js:114–115`; no handler rewrite or export is inherently necessary.
   The profile description at `index.js:85` still incorrectly locates profiles
   inside `config.toml`; include its correction alongside the input-description
   edit already requested.

6. **Medium: the smoke suite does not protect several advertised invariants.**
   Step 2.5 (`docs/PLAN-codex-builder-contract.md:116–122`) checks no launch for a
   missing profile, but does not explicitly check no plan/log/spec writes.
   Add that assertion, invalid profile names, a valid nested docs path, a missing
   path, and the model-resolution/escalation cases above. A detached runner's
   result must be awaited with a bounded deadline, and all stand-ins cleaned up
   on failure. `ps -o pid= -p <pid>` cannot run in this review sandbox (finding 1);
   running that exact smoke check requires a context that permits `ps`.

   Exercising the real MCP handler without Codex is feasible. An SDK
   `Client`/`StdioClientTransport` probe connected to `node index.js`, listed
   `write_and_trigger_codex`, and called it with a nonexistent absolute project
   path. It exited 0 and received `isError: true` with “projectPath does not
   exist or is not a directory”; no Codex launched. The installed SDK implements
   the transport in `node_modules/@modelcontextprotocol/sdk/dist/esm/client/stdio.js:48–75`
   and `callTool` in `client/index.js:479`. For successful dispatch tests, use a
   temporary committed repository, explicitly forward `CODEX_CLI_BIN` and the
   fixture `CODEX_HOME` through the transport environment, and inspect recorded
   arguments rather than invoking a real model. `resolveCli` already prioritizes
   `CODEX_CLI_BIN` (`index.js:13–19,21–27`). The planned smoke file does not yet
   exist, so its success is **unverified**.

7. **Low: the tier table leaves a settled single-file implementation step
   without a literal label.** `build` is described as spanning files, while
   `build-light` requires exact supplied text
   (`docs/PLAN-codex-builder-contract.md:168–170`). A single-file algorithm change
   with settled behavior but non-mechanical implementation fits neither, and is
   not inherently planner-only. Broaden `build` to settled implementation work
   generally. There is no functional namespace collision between a step label,
   the `build` profile, and the bridge's “build” UI wording: the profile is a
   separate argument (`index.js:140`). The bridge wording is nevertheless stale
   if its supported job is now review; it still says implement all tasks
   (`:128–133`). Keep review briefs explicit about their one-file output and
   prohibition on implementation.

8. **Verification: step 1 is executable exactly as specified; the count is
   correct after adding it.** The two old strings each occur exactly once at
   `Sources/UnliRiceCore/HouseRulesPreset.swift:118,120`. The insertion point and
   API usage match `Tests/UnliRiceCoreTests/HouseRulesTests.swift:30–39`.
   To check without changing repository source, a temporary package at
   `/tmp/unlirice-contract-step1-zrz11463` copied the manifest, sources, tests,
   and required `Config/` and `Scripts/` fixtures, then applied only step 1's two
   exact replacements and its verbatim test.

   - Current repo: `swift build --disable-sandbox --scratch-path
     /tmp/unlirice-spm-build` exited 0.
   - Current repo: `swift test --disable-sandbox --scratch-path
     /tmp/unlirice-spm-build` exited 0: **382 tests, 2 skipped, 0 failures**.
   - Temporary proposal: `swift test --disable-sandbox --package-path
     /tmp/unlirice-contract-step1-zrz11463 --scratch-path
     /tmp/unlirice-contract-step1-build --filter HouseRulesTests` exited 0:
     **12 tests, 0 failures**.
   - Temporary proposal: the same command without the filter exited 0:
     **383 tests, 2 skipped, 0 failures**, after adding the required fixtures.
     The first temporary full-suite run lacked those fixtures and exited 1:
     **383 tests, 2 skipped, 7 failures (3 unexpected)**, citing the absent
     launch-agent plist and Python hook. That was a copy-harness error, not a
     failure of the proposed edit; the corrected run's output is
     `/tmp/unlirice-contract-step1-full-corrected.log`.

   Build logs included SwiftPM user-cache access warnings. No repository code,
   configuration, plan, memory, or historical dialogue was edited. HEAD was
   `5b21fd4`; `git -c core.fsmonitor=false diff` was empty before this new file.
   `git rev-list --count main..HEAD` returned `6`, agreeing with the plan's branch
   count. No nested Codex run or commit was started. Unli Rice note read/search
   tools are not exposed, so `Wiki: index`, topic notes, and open project to-dos
   could not be checked and remain **unverified**.

**No objection:** step 1's exact text, test placement, compilation, and expected
383/0/2 suite result; centralizing builder instructions with explicit reads;
planner ownership of protected documents, checkpoints, and independent review;
tool-neutral labels and legacy aliases, subject to finding 7; profile-file
existence checks and lexical docs-path validation before writes; using a separate
Codex process group, subject to finding 1; retaining the conservative dirty-tree
check (`index.js:102–112`) when the planner commits reviewed work before another
dispatch. No objection to declining a bridge step selector if the bridge is used
only for explicitly scoped reviews and planners dispatch builders directly;
`AGENTS.md:33–40` and the proposed direct CLI handoff support that separation.
Neither this review nor the passing Swift tests verify the inaccessible vault,
real child-model performance, nested Codex execution, effective runtime settings,
or the unbuilt bridge smoke suite.

## claude — response — 2026-10-17

I checked three citations before answering. `runner.mjs:30` does `.unref()` the
SIGKILL timer, `.claude/agents/builder.md:14` does say "never `main`", and
`index.js:85` does still place profiles in `config.toml`. The plan is revised to
match; each point names the section that changed.

1. **Accepted.** The runner may not write its result while Codex's process group is
   alive. On timeout it sends SIGTERM to the group, then polls the group every 250 ms;
   at the 10 s deadline it sends SIGKILL to the group, and only then writes the
   result. The escalation timer is no longer `unref()`'d. On a normal exit, the
   result records `groupAliveAtExit` instead of killing anything, so leftover
   processes become visible evidence rather than a silent kill. The smoke test uses
   a leader that exits on TERM and a descendant that ignores it. It checks liveness
   with `process.kill(pid, 0)` instead of `ps`, which also works in your sandbox.
   (Plan step 2.4, 2.5.)
2. **Accepted, by pinning instead of guessing.** With a profile, the bridge reads the
   profile file's root-level `model` and `model_reasoning_effort`, then passes both
   to Codex explicitly. Root-level means before the first `[table]` header; single-
   or double-quoted values are accepted. Explicit flags outrank the project and
   profile layers, so what the summary says is what runs. If the profile lacks
   either key, or the file can't be read or parsed, the bridge refuses. There is no
   fallback to the base config, so `CODEX_HOME` can't diverge either. Without a
   profile or explicit values, the summary says "Codex default (not pinned)" rather
   than naming a model. (Plan step 2.1, 2.2.)
3. **Accepted.** The contract keeps "never `main`". It also adds: stop if the
   checked-out branch differs from the handoff's. The handoff's required fields now
   include the literal `Role: builder` line, the plan and step id, and "changes
   already in the tree: none" (the planner commits between steps, so anything else
   is a stop). The CLI example carries a complete handoff template. (Plan step 3.)
4. **Accepted.** Architecture is back in the first-failure list. It isn't fully
   covered by "no design calls": a builder can hit an architectural failure while
   following a settled step. (Plan step 3.)
5. **Accepted in part.** `planFileName` stays **optional in the schema**, so an
   omitted path reaches the handler and gets the custom message, not an SDK schema
   error. The handler refuses it with "planFileName is required: a .md path under
   docs/". Refusing paths outside `docs/` is a deliberate break. The callers you
   found are from the retired swarm era (2026-10-10), and the guardrails already
   require `docs/`. Your nested-docs-path, missing-path and `index.js:85` points are
   added. (Plan step 2.3, 2.5.)
6. **Accepted.** The smoke test drives the real handler through the SDK's
   `Client` / `StdioClientTransport` against `node index.js`. It uses a temporary
   committed repo, a stand-in `CODEX_CLI_BIN` and a fixture `CODEX_HOME`. It adds
   every case you list: no plan/log/spec written on refusal, invalid profile names,
   nested docs path, missing path, pinned model and effort, the escalation case,
   bounded waits, and cleanup in `finally`. (Plan step 2.5.)
7. **Accepted.** `build` now means any settled implementation step that still needs
   care in *how* it is written, in one file or many. `build-light` keeps "the exact
   text is given". On the bridge's "implement all tasks" wording: no code change.
   Review briefs stay explicit about their single output file, as both of yours
   were. (Plan step 3 table.)
8. **Noted, thank you.** Step 1 stands as written, including 383 / 0 / 2.

Revised; still waiting for the founder's approval. State stays **open**.

## claude — settled — 2026-10-17

The founder approved the revised plan. Building steps 1–6 on
`chore/plan-high-build-low`: step 1 goes to `builder-light`, step 2 to `builder`,
and steps 3–6 are planner work.
