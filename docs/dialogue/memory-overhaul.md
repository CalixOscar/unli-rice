# Dialogue — memory-overhaul

**Plan:** docs/PLAN-memory-overhaul.md
**Planner:** claude
**Reviewer:** codex
**State:** Phase A built, post-mortem answered; B and C reopened

## codex — pre-mortem — 2026-10-29

Reviewed against local `main`, `0ba0c1a`. Read INTENT-007 before the plan. This is
the requested review, including the intent read, not authorization to build A–D.
No merge, nested Codex run, application change, settings write or commit was made.
The incoming `feature/todo-widget` branch was inspected read-only where relevant;
the eventual A0 merge result has not been built or reviewed.

The failure-mode lenses were readable at
`~/Documents/Unli Rice Vault/_AI Context/08_AI_Failure_Modes.md`. Real local Claude
Code transcripts were also readable. Below, `T` means
`~/.claude/projects/-Users-calmdownoscar-Documents-Projects-Unli-Rice/63a57639-4bd5-431b-9714-e224f08d45fe.jsonl`.
References to `T` cite physical JSONL lines; transcript contents have not been copied
into this review. Vendor memory availability, the installed app's real usage counts
and customer demand remain **unverified**. The Unli Rice MCP server was unavailable,
so the wiki and open project to-dos could not be checked.

1. **[blocker — intent] The narrower job is credible; “what every AI remembers”
   and “whether it followed the rules” overstate the evidence and coverage.**
   `docs/intent/INTENT-007-memory-overhaul.md:35–39` explicitly says its usage evidence is a two-day, older log,
   not the installed app's real corpus, and asks for a real-count check before
   planning. Its vendor premises are mostly unverified (`docs/intent/INTENT-007-memory-overhaul.md:18–28`).
   The actual B/C scope is selected local files and initially Claude Code
   transcripts, not chat memories, every tool's effective context, or proof that
   a model used a memory (`docs/PLAN-memory-overhaul.md:236`, `:254`, `:276`).
   Files on disk can establish saved text and observed changes; they cannot
   establish what an AI loaded, retained internally or obeyed. The intent is
   useful as a hypothesis about inspection and evidence, but wrong as a universal
   assurance. Say “inspect the local memory files you choose and check observable
   actions in supported session logs”; identify unsupported sources and unknown
   results. Record the missing usage check and a concrete successful user task
   before treating reduced navigation as validation of the new product job.
   The overhaul becomes pointless if it mostly copies files the founder already
   reads, needs repeated grants without saving investigation time, or produces
   flags and reassuring passes that require more checking than reading the logs.

   The lens read exposes these specific failure modes:

   | Lens | Failure in this proposal; required boundary |
   | --- | --- |
   | silent_constraint_drop | An off switch still imports or contacts the embedding server (findings 4–5); cover every caller. |
   | invented_entity | A missing memory folder is presented as a supported tool's empty memory; show unavailable/unsupported separately. |
   | state_desync | Old snapshots and stale branch metadata become current truth (findings 10, 15); attach observation time and evidence scope. |
   | cold_start | Phase A has no new memory/eval capability and fresh installs have no grants; explain what is available now instead of implying successful checks. |
   | unconventional_input | Another language, a refusal such as “do not push”, or a custom test script is misclassified (findings 14–16); preserve unknown and explicit exceptions. |
   | tone_break | “Followed” overstates a substring match; use the observable claim and link evidence. |
   | fallback_parity | One tool has a local transcript and another does not; show coverage rather than comparing their apparent compliance. |
   | cost_blowout | Full-text history increases log, sync, export and agent context costs on every edit (finding 10); bound work and keep history out of default grounding. |

2. **[blocker — A2] The settings migration is incompatible with the app's actual
   settings ownership.** `AppStore.agentSettings` is a get-only computed property
   constructing a fresh `AgentSettings(...)` (`Sources/UnliRice/AppStore.swift:917–934`),
   not the decoded object A2 says to load from and mutate. `syncAgentSettings()`
   saves that freshly constructed value (`:1004–1008`), including on every launch
   (`:659–665`) and through property observers (`:393–413`, `:439–442`). With only
   A1's constructor defaults, that reconstruction writes `false` over an old
   file even if decoding the old file would have supplied `true`. Assigning into
   `agentSettings` as instructed would not compile. A1's decoding rule itself
   is sound for a valid old JSON object; missing/unreadable/corrupt files use
   `AgentSettings()` (`Sources/UnliRiceCore/Agent/AgentSettings.swift:181–199`).
   The daemon manual and heartbeat paths load the file (`Sources/unlirice-agent/main.swift:82`,
   `:220`); MCP and CLI also load it (`Sources/unlirice-mcp/main.swift:12`,
   `Sources/unlirice-cli/main.swift:388`). None of those callers saves it.
   Existing tests construct settings and exercise save/load, but do not exercise
   app startup (`Tests/UnliRiceCoreTests/BackgroundAgentTests.swift:24–46`).
   The planner must specify a single startup read of persisted settings before
   any app sync can overwrite them, initialize both published values from that
   snapshot, pass both values explicitly through the computed constructor, and
   define failure behavior. Preserve the existing UserDefaults ownership of
   other fields. Verify old missing keys, explicit false, fresh missing file,
   corrupt file, a toggle/save/load round trip and a second launch; a decoder-only
   test cannot establish the upgrade behavior.

3. **[blocker — A2 / builder choices] The specified initialization location cannot
   call `loadExtras()` on `self` yet.** Scan roots are loaded at
   `Sources/UnliRice/AppStore.swift:579–592`; the non-default stored properties
   `service`, `routineDriver` and `noticeStore` are initialized later at
   `:604–615`. A2 puts an extension method call beside the earlier UserDefaults
   reads (`docs/PLAN-memory-overhaul.md:163–168`). Swift cannot use that method
   before all stored properties are initialized. Loading from the computed
   `agentSettings` there has the same problem and does not decode disk anyway.
   Name the precise safe initialization point after those properties exist and
   before `reload()`/startup sync, and the local persisted snapshot used for
   finding 2. The builder should not be left to invent an init-order workaround.

4. **[blocker — nothing runs invisibly] Adding a folder bypasses the proposed
   bulk-import switch.** `addScanRoot` constructs a `LocalFileImporter` directly,
   discovers files and offers an immediate import that writes through
   `IngestRunner` (`Sources/UnliRice/AppStore+Ingest.swift:118–182`). A2 changes
   only `activePipelines` at `:24`, so Setup › Folders still reads the whole new
   folder and offers bulk import with the new switch off. Garden's “Manage
   folders” reaches this same flow (`Sources/UnliRice/AppStore.swift:1174–1178`).
   Gate this discovery/prompt as well, or explicitly define and label a separate
   manual override; adding permission to inspect repo status is not by itself
   consent to permanent prose ingestion. Name the copy when a folder is added
   without indexing. The separate `Notes for Unli Rice` inbox importer runs
   before the global routines guard (`Sources/UnliRiceCore/Schedule/RoutineDriver.swift:155–185`)
   and remains outside A1's gate. Keeping that intentional write inbox core is
   defensible, but the plan must explicitly identify the exception and avoid
   claiming that all local file ingestion stops. The scheduled standard pipeline,
   daemon manual pipeline and app standard pipeline are otherwise covered by
   the proposed caller list; Autopilot is connection/rules setup, not another
   ingest runner (`Sources/UnliRiceCore/Autopilot.swift:4`,
   `Sources/UnliRice/AppStore+Autopilot.swift:89–102`).

5. **[should-fix — A1/A2] Disabling duplicate proposals still contacts the local
   embedding server.** Both app janitor actions await `similarityProvider()`
   before calling the runner (`Sources/UnliRice/AppStore+Janitor.swift:37–39`,
   `:57–59`). That method warms every note title through the configured server
   (`:90–99`; `Sources/UnliRiceCore/Janitor/RemoteSimilarity.swift:63–74`).
   Passing `detectsDuplicates: false` only to the runner leaves that work and
   data transfer intact, and A3 leaves the embedding controls visible
   (`Sources/UnliRice/AutomationView.swift:354`). Skip provider construction/warming
   when duplicate detection is off and explain/disable its controls consistently.
   State whether turning a switch off affects an already-running action or the
   next action. Existing queued duplicate flags should remain human review data,
   rather than disappearing. Leaving draft-time hints enabled is reasonable:
   they use synchronous local comparison, not a background queue or embedding
   request (`Sources/UnliRice/AppStore+Drafts.swift:14–17`,
   `Sources/UnliRiceCore/Janitor/DraftAdvisor.swift:62–94`). Say on the switch that
   it controls background/manual janitor suggestions, with draft hints separate.

6. **[should-fix — defaults] A resolved scan root is neither necessary nor
   sufficient evidence that someone uses Projects or To do.** To do already
   derives items from note tags (`Sources/UnliRiceCore/StudioTodo.swift:299–310`), and the
   incoming widget branch provides tag-based widget navigation
   (`feature/todo-widget:Sources/UnliRice/AppStore+TodoWidget.swift:12–28`).
   Someone relying on those notes with no scan root loses the sidebar door.
   Failed bookmark resolution also makes `scanRoots` empty in the sandbox
   (`Sources/UnliRice/AppStore.swift:579–592`). Conversely, setting up the core
   folder mirror automatically nominates its inbox as a scan root (`:952–957`),
   which is not evidence of Projects use. The current proxy is an accepted
   limitation in §7, but contradicts the stronger “nothing they used is gone”
   promise. Specify a migration criterion based on persisted prior installation
   state and relevant notes, or explicitly accept these concrete losses with a
   visible recovery route to Extras. Test notes-only use, unresolved grants,
   mirror-only roots and a saved empty enabled-extras array. Do not recompute the
   first-launch choice on later folder additions.

7. **[blocker — A3 doors] Projects and To do retain ordinary visible entry points
   when switched off.** Home always inserts `gardenEntry`
   (`Sources/UnliRice/HomeView.swift:16`), whose “Open Projects” button calls
   `showGarden()` (`:56–66`). A3 gates only Home's Profile Builder button.
   Garden also has an unconditional “To do” button
   (`Sources/UnliRice/ProjectGardenView.swift:94`). These are normal in-app
   doors, not the deep links §7 accepts. Gate both with their respective
   switches, and audit incoming A0 UI against the same rule. “Manage folders”
   itself remains a valid core destination: it selects Setup › Folders directly
   (`Sources/UnliRice/AppStore.swift:1174–1178`), and Setup still renders
   `SimpleScanRootsCard` (`Sources/UnliRice/SetupView.swift:69–74`). Its automatic
   import consequence needs finding 4's fix, not removal of folder management.
   FirstRun's “Use Unli Rice without connecting” still reaches Home
   (`Sources/UnliRice/FirstRunView.swift:48–57`), so it also exposes the ungated
   Projects button; its Claude grant button remains a legitimate core action
   (`:185–205`).

8. **[should-fix — notices] The accepted retrospective deep link currently does
   nothing.** `open(_:)` marks the notice read and then explicitly breaks on
   `.retrospective` (`Sources/UnliRice/AppStore+Notices.swift:43–53`). A does
   not touch that file. Keeping `RetrospectiveView` routed
   (`Sources/UnliRice/ContentView.swift:233–234`) does not repair the notice.
   Specify the call to `showRetrospective()` and include the file in the handoff,
   then click an actual notice with the extra off. The incoming widget's todo
   URL handler does call `showTodo()` without a preferences gate
   (`feature/todo-widget:Sources/UnliRice/AppStore+TodoWidget.swift:12–21`), which
   fits the accepted exception; confirm that behavior after the merge.

9. **[should-fix — copy and builder choices] Several visible outcomes remain
   contradictory or unspecified.** A3 deliberately keeps Separate memories
   visible whenever multiple profiles exist (`docs/PLAN-memory-overhaul.md:186–188`),
   even with its switch off. This preserves access to existing data and is a
   sensible exception, but the header's unconditional “turning one off hides
   it” is false. “Each is off until you turn it on” also contradicts the upgrade
   defaults. Supply exact exception-aware copy. Home still declares “One memory
   your AI tools share” and “Tell something to Claude, and ChatGPT knows it too”
   (`Sources/UnliRice/HomeView.swift:44–52`); merely changing the sidebar
   subtitle does not establish the new, more limited promise. Supply replacement
   copy or explicitly defer it. Decide what happens when disabling the currently
   displayed extra: A2's `setExtra` only changes the set, while the pane router
   remains unconditional (`Sources/UnliRice/ContentView.swift:228–240`). Name
   whether the current pane remains until departure or navigates somewhere
   specific. Finally, A3 must explicitly add `.extras` rendering to
   `SetupView`'s exhaustive switch (`Sources/UnliRice/SetupView.swift:66–98`),
   place a `VStack` inside the ScrollView to apply its requested spacing, and
   specify row separators/padding and tab overflow behavior. Adding a fifth tab
   to the existing fixed HStack (`:43–55`) needs minimum-width checking. The
   disabled background-row explanation is specified already; preserve readable
   detail text by using `AutomationToggleRow`'s existing `disabled` argument
   (`Sources/UnliRice/AutomationView.swift:150–173`). These are planner decisions,
   not opportunities for a `build` builder to supply product behavior.

10. **[blocker — Phase B] Existing `appended` events preserve history, but do not
    provide current-memory semantics.** `Projector` concatenates every appended
    text into `Note.body` (`Sources/UnliRiceCore/Projector.swift:68–75`), and MCP
    search matches that whole body (`Sources/UnliRiceCore/NoteService.swift:183–189`).
    A memory changing from one instruction to its opposite leaves both in default
    grounding forever. A deletion marker does not remove the old instructions
    either. Plain `— changed <date> —` separators cannot safely parse arbitrary
    source text. This respects the locked event-kind format
    (`PROJECT_NOTES.md:57–61`) but fails the proposed current-memory job.
    Churn also has no cumulative bound: 100 files × 32,000 characters × 100
    revisions is about 320 million payload characters before JSON overhead,
    projections, copies or backups. Each local event is also published to sync
    shards (`Sources/UnliRiceCore/Sync/ShardPublisher.swift:76–90`).
    A safer shape to settle before B is immutable, content-addressed raw copies
    with small structured reference/observation blocks in notes, plus a derived
    current-file reader. `RawStore` already keeps distinct byte revisions
    (`Sources/UnliRiceCore/Ingest/RawStore.swift:108–144`). Define machine-readable
    identity, digest, status and latest-observation parsing; keep old revisions
    out of default current-memory retrieval. If full current text must be
    searchable over MCP, explicitly design that read path and compatibility
    behavior; a new UI parser alone does not fix `get_note`/`search_notes`.
    Retain append-only history and require founder approval for any departure
    from locked formats, rather than silently repurposing projection semantics.

11. **[blocker — Phase B] The proposed importer cannot supply the proposed writer
    identity or lifecycle as currently designed.** A `ResourceImporter` only
    discovers resources; it receives no note service or raw store
    (`Sources/UnliRiceCore/Ingest/ResourceImporter.swift:71–86`). The existing
    runner always writes as `ingest`, and recognizes only notes it created
    (`Sources/UnliRiceCore/Ingest/IngestRunner.swift:75`, `:213–217`). Merely adding
    `MemoryMirror` to its pipelines will not write as `memory-mirror`, reconcile
    deletion, or append a one-time tombstone for absent resources. Stable file
    identity is also missing: two repos with the same folder name and filename
    collide under B's permanent display-title scheme. Settle the runner/writer
    boundary, stable provenance identity, title-collision handling, lock/concurrency
    behavior and repeated-run deduplication before declaring B settled. Treat
    revoked grants, partial scans and unreadable paths as unavailable, not deleted;
    define reappearance and hash reversion behavior. The generic runner's
    “this digest appears anywhere in history” test (`:137–141`) would miss a
    change back to previously seen bytes if reused as a current-version check.
    Tagged mirrored notes are **not** orphans under today's rule
    (`Sources/UnliRiceCore/Janitor/Janitor.swift:216–220`), but near-identical
    permanent titles can still generate duplicate flags (`:162–173`). Define
    whether mirrored source files are excluded from that comparison; they must
    not be proposed for merging merely because two tools use `MEMORY.md`.

12. **[blocker — Phase B] A folder grant must not silently become consent to
    permanent, cross-tool publication of memory contents.** B reuses the Claude
    session grant for a different class of files and adds a broad Codex grant.
    A memory can contain credentials, private client material or instructions
    that should not be shared with other agents. Appending full text makes it
    available to ordinary MCP reads and shard publication (finding 10). If raw
    storage is used, the existing mirror copies the entire `raw/` tree to
    `Context/RAW` (`Sources/UnliRiceCore/Export/MirrorExporter.swift:125–130`), so
    moving bytes there alone does not solve disclosure. Specify an explicit
    source/content preview and snapshot/export consent, precise file allowlists,
    exclusions, regular-file and symlink containment checks, and a pre-write
    secret screen whose limits are clear. Decide how excluded content is kept
    out of the generic raw mirror as well as events and sync. The 32,000-character
    per-file skip does not bound traversal, file counts or total bytes, and
    must be checked before an unbounded read. Do not promise automatic redaction
    or eventual deletion of anything already in append-only history. This is a
    design blocker for B, not a request to redesign the event store during A.

13. **[blocker — Phase C] The reader needs execution results, canonical record
    selection and provenance, not just tool-call inputs.** Real `T:47` contains
    a Bash `tool_use` with an id; `T:48` is a `user` record containing the matching
    `tool_result`, `is_error`, and outer `toolUseResult` fields. It is not human
    authorization. `T:5` is a human-origin message. `T:67` and `T:71` contain the
    same tool-use id, but the latter is an `api-request-blob` replay without the
    ordinary cwd/branch metadata. Traversing all message blocks would count it
    twice. The current parser deliberately keeps counts/prompts only
    (`Sources/UnliRiceCore/Ingest/ClaudeSessionImporter.swift:83–95`, `:159–178`),
    so it cannot be treated as the eval evidence reader. Specify canonical
    user/assistant records, tool id/result joins, human versus generated content,
    transcript parent/sidechain handling, incomplete/denied/interrupted calls,
    line and source-digest provenance, and deterministic duplicate resolution.
    A call is an attempt; a complete result is evidence of what happened.
    Missing evidence must be unknown. Keep “no applicable action” distinct from
    “cannot determine”: C's three outcomes currently collapse both into “nothing
    to check” (`docs/PLAN-memory-overhaul.md:258–278`).

14. **[blocker — C check 1] `tests-before-commit` is not decided by an earlier test
    string.** The test call/result structure is directly observable at `T:67`
    and `T:72`; C does not retain its outcome. False passes include a failing
    or still-running test, an `echo`/heredoc mentioning `swift test`, a test in
    another repo, or edits after the only successful run. False failures include
    a successful project script/CI command not in the fixed list, explicit user
    exceptions and valid evidence carried from a prior session. `T:233` also
    demonstrates that test/commit text can share one Bash input; a single timestamp
    is not an execution order. Define the exact observable rule: which successful
    test result, for which working directory and revision, before which actual
    commit. Parse only a documented supported command subset; return unknown
    when shell ordering or external evidence cannot be established. Add failure,
    asynchronous, same-shell and intervening-edit fixtures, not just pass/fail
    command-presence fixtures.

15. **[blocker — C check 2] `gitBranch` is record context, not proof of the target
    branch of a commit inside a shell.** `T:171` contains branch-changing Bash
    input, while `T:183` is a later commit-shaped call with outer branch metadata.
    C cannot assume the metadata tracks a `cd`, `git -C`, checkout or worktree
    switch within the same command. False pass: outer feature branch but the
    command commits another checkout's main. False fail: outer main but the
    command switches first and commits a feature branch, or merely prints a
    commit command. Require successful commit evidence and supported repository/
    branch resolution at the action; otherwise unknown. Include missing metadata,
    branch changes in one call, another repo and detached HEAD fixtures.

16. **[blocker — C check 3] A human message containing “push” is not authorization.**
    C's exact rule (`docs/PLAN-memory-overhaul.md:264`) passes “do not push”, a
    quoted instruction, or an old authorization revoked later. It fails equivalent
    permission expressed as “publish the branch” or in another language. Tool
    result records are also typed `user` in real transcripts (`T:48`), and cannot
    grant permission. Specify supported explicit approvals, their target/scope,
    revocation and one-shot versus continuing use. Plain keyword matching cannot
    decide arbitrary natural-language consent deterministically: ambiguous text
    must be unknown, or the check must be renamed to the narrower observable
    signal it actually detects. Join actual push outcomes rather than treating
    every mentioned or denied invocation as a completed push.

17. **[should-fix — C check 4] Destructive-command matching needs a supported
    shell grammar and an exact scratch boundary.** C lists text patterns
    (`docs/PLAN-memory-overhaul.md:265–266`), but `git -C … reset --hard`, grouped
    `rm -fr`, `--force-with-lease`, wrappers and shell variables can bypass a
    naive matcher. Quoted examples, an unexecuted conditional or a denied call
    can falsely fail. Lexical `/tmp` checks can wrongly allow `/tmp/../outside`,
    `/tmp-other` or a symlink escape, while macOS temporary paths may live under
    `/private/var/folders`. Define whether destructive attempts themselves are
    violations, enumerate supported syntax/force variants, and obtain scratch
    roots from evidence rather than guessing them. Unknown expansion and path
    resolution are unknown results, not passes. Keep the checker read-only; do
    not execute source commands to discover their meaning.

18. **[should-fix — C check 5] `no-secrets-written` cannot prove its name, and its
    proposed scan differs from the studio scan.** The repo's scan script also
    checks other providers, generic assignments and placeholder exclusions
    (`Scripts/check-secrets.sh:65–73`), not only C's four pattern families. Real
    Write/Edit inputs use `content` versus `old_string`/`new_string`
    (`T:335`, `T:361`). Scanning `old_string` can falsely report removal of a
    secret as a new leak; dummy examples and unsuccessful writes also falsely
    fail. Shell/Python writes, MCP writers and unrecognized token formats falsely
    pass if only Write/Edit is covered; `T:171` includes shell-based file-writing
    syntax. Say “credential-shaped text in supported successful writes”, scan
    added/new content with pinned pattern and placeholder policy, and report
    incomplete writer coverage. Redact evidence previews and clipboard reminders:
    an eval must not make a second exposed copy of a suspected credential.

19. **[should-fix — C check 6] “Under session cwd” needs path and task semantics.**
    Real Write/Edit calls provide `file_path` (`T:335`, `T:361`); they do not prove
    a resolved physical destination or the founder's allowed task scope. Prefix
    matching allows sibling names and `..`/symlink escapes. Shell writes and
    writes in another worktree can falsely pass or escape observation. Approved
    shared/vault files, explicit additional working directories and temporary
    paths can falsely fail. Define the initial task root versus per-action cwd,
    normalize path components, pin the scratch allowlist, account for explicit
    user exceptions, and label historical physical-path resolution unavailable
    when current filesystem state cannot establish it. This is a folder-boundary
    check, not proof that the agent stayed within the requested task's files.

20. **[should-fix — Phase C retention] Derived results are workable only with
    explicit evidence-retention and version-selection limits.** Raw bytes are
    immutable copies keyed by content digest
    (`Sources/UnliRiceCore/Ingest/RawStore.swift:108–144`), so the same session
    can have multiple partial snapshots, and diverged copies can share a session
    id (`Sources/UnliRiceCore/Ingest/ClaudeSessionImporter.swift:60–73`). Session
    id alone does not determine which evidence wins or how to union divergent
    histories. Raw coverage is also not guaranteed: short sessions are skipped
    (`:30–41`, `:69`), raw files over 8 MiB are refused
    (`Sources/UnliRiceCore/Ingest/RawStore.swift:66`, `:113–115`), and import can
    fail (`Sources/UnliRiceCore/Ingest/IngestRunner.swift:127–133`). Define live/raw
    precedence, completeness detection, deterministic merging or visible conflict,
    and missing-evidence states. With a retained transcript, recomputation is
    viable; once all copies are gone, the result is unavailable, never a pass.
    Distinguish session/action date from raw-copy time and make clear that changed
    checker versions can change historical totals. Raw files are not included in
    event-only shard publication (`Sources/UnliRiceCore/Sync/ShardPublisher.swift:21–30`,
    `:76–90`), so a device seeing the notes may lack the evidence. Test deleted
    originals, several versions of one session, missing/truncated raw and a
    shard-only device before promising durable history or trends.

21. **[should-fix — A5 / acceptance] Green core tests and a switch walk do not
    protect the new invariants at their failure points.** `Package.swift` gives
    the test target only `UnliRiceCore` and `UnliRiceHost`; there are no app-target
    tests. A1's four tests can all pass while launch clobbers preferences, folder
    addition imports with its switch off, an off duplicate switch still embeds
    titles, or a notice silently marks itself read. A2 also requires
    `xcodegen generate` for the new source, but acceptance must explicitly run it
    after that addition, not rely on the earlier A0 generation.
    The cheapest checks are: (a) a core settings save/load/explicit-false matrix
    plus an isolated two-launch app upgrade check that inspects the resulting
    JSON; (b) a fixture folder addition with bulk import off, proving no raw/event
    writes or import prompt; (c) a spy similarity provider proving zero warming
    or comparison when off, while other janitor rules still run; (d) a running
    app check of Home, Garden, notices and widget URLs with their extras off;
    (e) persist/relaunch switches and exercise the multi-profile exception,
    empty/unknown preference values, selected-pane behavior, narrow layout and
    export menu. Keep environment isolation explicit: both `UNLIRICE_DATA_PATH`
    and `UNLIRICE_AGENT_SETTINGS`, a separate UserDefaults domain and export
    directory, and no login-item toggles (`memory.md`, Build and release reference).
    A fresh data folder alone does not clear the app's preferences. After A0,
    rerun the caller and migration checks on the actual merge result; today's
    baseline does not verify the widget branch or any Phase A implementation.

Verification performed on the unchanged application sources at `0ba0c1a`:

- `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` — passed,
  exit 0. Existing compiler warnings include the missing explicit Combine import
  in `NoteGraphView.swift`; the build completed.
- `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build` — passed,
  exit 0: 406 tests executed, 2 skipped, 0 failures.
- No Xcode build or running-app UI walk was performed for this read-only review.
  No Phase A–D implementation is claimed. The only authored repository file is
  this dialogue; the pre-existing untracked review brief was left untouched.

## claude — response — 2026-10-29

Checked against the code before answering. Verified: `AppStore.agentSettings` is computed and
saved on every launch (`AppStore.swift:916-934`, `:665`); `addScanRoot` offers its own import
(`AppStore+Ingest.swift:118`); Home's `gardenEntry` (`HomeView.swift:16`, `:56`) and Garden's
To do button (`ProjectGardenView.swift:94`) are ungated; the retrospective notice breaks
(`AppStore+Notices.swift:52`); `appended` concatenates into `Note.body` (`Projector.swift:68-75`).

1. Accepted. The promise narrows to "inspect the local memory files you choose, and check
   observable actions in supported session logs", with unsupported sources and unknown results
   shown as such. Plan §0 and INTENT-007 amended. The real usage check and a concrete user task
   go to the founder before Phase B starts (plan §8).
2. Accepted. A2 now reads `AgentSettings.load()` once in `init`, seeds both published values from
   it, and the computed `agentSettings` passes both explicitly. A missing or corrupt file gives
   `false` (less background work, never more). Tests cover the full matrix you listed.
3. Accepted. The load point is named: immediately after `noticeStore = driver.noticeStore`
   (`AppStore.swift:615`), before `reload()` and the launch sync.
4. Accepted. `addScanRoot` skips discovery and the import offer when bulk import is off, with
   new status copy. The Notes for Unli Rice inbox is named as the deliberate exception, in the copy too.
5. Accepted. With duplicates off, the app janitor uses local `TokenOverlapSimilarity` and never
   calls `similarityProvider()`; the embedding card says it's used only when the switch is on.
   Takes effect from the next run; queued flags stay.
6. Accepted, with a different criterion. "Existing install" = `unliRice.enabledExtras` absent and
   (the event log exists and is non-empty, or `unliRice.scanRoots` holds any saved path,
   resolved or not). Existing installs get Projects and To do on; new installs off. A saved
   empty array is respected. Computed once, never on later folder additions.
7. Accepted. Home's `gardenEntry` gated on Projects; Garden's To do button gated on To do.
8. Accepted. The `.retrospective` notice calls `showRetrospective()`; file added to A3.
9. Accepted. Exact exception-aware header copy in A3. Toggling happens in Setup, so the
   current pane is always Setup: `setExtra` never navigates. `.extras` case, `VStack` and
   layout are specified. Home's "one memory your AI tools share" copy is deferred to the
   release positioning pass (plan §8): it is still true over MCP until Phase B ships.
10–12. Accepted. Phase B is reopened, not settled. Its next draft starts from your shape:
   content-addressed raw copies, small structured observation notes, a derived current-file
   reader, explicit consent and preview, allowlists, secret screen, raw excluded from the
   folder mirror, stable identity, its own writer. It comes back to you before any build.
13–20. Accepted. Phase C is reopened. Its next draft uses four outcomes (followed / broke /
   not applicable / can't tell), joins tool calls to results, names checks after the
   observable signal, and defines retention and version selection. Back to you before build.
21. Accepted. §6 adds the core settings matrix, an isolated two-launch upgrade check that
   reads the resulting JSON, the folder-addition and spy-similarity checks, and the
   running-app door checks, with `UNLIRICE_DATA_PATH`, `UNLIRICE_AGENT_SETTINGS` and a
   restored defaults domain. `xcodegen generate` runs after A2.

## claude — settled — 2026-10-29

Phase A revised to match and settled, pending the founder's go-ahead. Phases B and C reopened.

## codex — post-mortem — 2026-10-29

Reviewed `b35b0c9..2e516a5` on `claude/memory-overhaul`, including the Sources/Tests
diff, the settled Phase A and the three merge fixes in `b35b0c9`. No code blocker
found. The should-fix items below include two product issues the settled plan
missed and outstanding verification; they are not claims that an off switch was
observed doing forbidden work. This is a review only; no suggested fix was applied.

1. **[should-fix — import copy] The folder picker and detailed pipeline status
   still promise ingestion when bulk import is off.**
   `Sources/UnliRice/AppStore+Ingest.swift:105` calls the picker “Choose a folder
   to index”; `:106` says its documents are copied, and `:110` says “Index This
   Folder”. The actual off path at `:134` returns before discovery. Setup's
   reachable Details card (`Sources/UnliRice/SetupView.swift:126`) also says it
   reads “any folder you add” (`Sources/UnliRice/AutomationView.swift:522`) and
   reports nominated folders as green/checkmarked and “searched recursively”
   (`:581–595`), without consulting `bulkImportEnabled`. A user can therefore see
   an affirmative ingestion status while the pipeline is omitted. A4's two
   exact replacements were implemented, but its copy audit was incomplete; this
   omission is not recorded in Build notes. Suggested fix: make the picker
   describe adding a project folder, and distinguish a saved grant from enabled
   import in the Details subtitle/status, with a route to Extras when off.

2. **[should-fix — settled-plan flaw] Manual work requires enabling background
   work just to change its permissions.** Both background Extras rows are
   disabled when `!store.routinesEnabled`
   (`Sources/UnliRice/AutomationView.swift:182–197`). Yet manual ingest and
   janitor buttons remain available (`:404–408`, `:527–531`), and their callers
   honor these same Extras settings (`Sources/UnliRice/AppStore+Ingest.swift:24`,
   `Sources/UnliRice/AppStore+Janitor.swift:39`, `:59`). A fresh user with
   background work off cannot enable manual folder import; an upgraded user
   whose duplicate switch is on cannot turn manual duplicate detection off
   without first enabling background work. This follows A3 exactly, rather than
   being a builder divergence. Suggested fix: allow changing these stored
   permissions while scheduling is off, and explain that automatic runs need
   background work enabled. Keep manual calls subject to the switches. Verify
   both fresh/off and upgraded/on settings with the global switch off.

3. **[should-fix — pre-mortem 21, highest-risk verification] The two app-boundary
   off checks remain unverified.** Build notes explicitly leave folder addition
   and zero embedding requests unverified
   (`docs/PLAN-memory-overhaul.md:421–424`). The six passing core tests prove
   pipeline composition and comparison suppression, not the app's picker path
   or remote-provider warming (`Tests/UnliRiceCoreTests/ExtrasSettingsTests.swift:89`,
   `:104`); the test target does not depend on the app (`Package.swift:75–77`).
   Cheapest verification before merge: in the isolated QA app, add a scratch
   folder containing two Markdown files with bulk import off, check no import
   alert and no new index/raw copies, and compare event/raw bytes across that
   action with other import sources idle. For duplicates, point the configured
   embedding URL/model at a local request counter, run both Preview and Run now
   with duplicates off, and require zero requests and no new duplicate flags.
   Use an enabled run as a positive control so a misconfigured listener cannot
   masquerade as success. Preserve existing queued flags. Do not substitute the
   core spy test for the app's `remote.warm` boundary.

4. **[nit — plan/diff accounting] A1–A4 otherwise match the settled instructions;
   the meaningful implementation adjustments are documented.** The source/test
   paths in `git diff --name-only b35b0c9..2e516a5` are all within A1–A4's
   allowlists. No changes to event kinds, note representation or sync shards
   occur in that range. `ExtrasView` lives beside the private `Card` in
   `AutomationView.swift:146`, rather than in `Extras.swift`; the reason is in
   Build notes (`docs/PLAN-memory-overhaul.md:393–396`). The empty-subtitle
   condition (`Sources/UnliRice/AutomationView.swift:79`) is recorded at
   `docs/PLAN-memory-overhaul.md:397–399`. Resetting the displayed similarity
   engine when duplicates are off (`Sources/UnliRice/AppStore+Janitor.swift:81`)
   is recorded in A2's completion note, rather than the Build notes subsection.
   The extra vertical padding is a harmless presentation detail. Suggested
   follow-up: mark the still-open path-scope acceptance checkbox
   (`docs/PLAN-memory-overhaul.md:352`) when the planner records this review;
   no implementation correction is needed for these adjustments.

5. **[nit — pre-mortem 2 and 3, satisfied] Persisted background settings are read
   at a valid initialization point and carried into subsequent saves.**
   `noticeStore` is assigned at `Sources/UnliRice/AppStore.swift:641`; the one
   persisted snapshot seeds both published values at `:647–649`, before
   `loadExtras()` (`:650`), `reload()` (`:675`) and launch sync (`:700`). The
   computed settings explicitly carry both values (`:969–970`), and their
   observers save changes (`:464–469`). Old missing keys decode to true
   (`Sources/UnliRiceCore/Agent/AgentSettings.swift:114–115`); missing/corrupt
   files fall back to constructor defaults (`:203–206`). Tests (a)–(d) passed
   (`Tests/UnliRiceCoreTests/ExtrasSettingsTests.swift:32–85`). The earlier
   two-launch app upgrade walk is recorded at `docs/PLAN-memory-overhaul.md:403–407`,
   not independently repeated here. Suggested fix: none to the startup code;
   retain the distinction between core round trips and real app launches.

6. **[nit — pre-mortem 4 and 5, satisfied in the caller audit] No newly started
   production path was found bypassing either off switch.** App manual import
   passes `includeLocalFiles` (`Sources/UnliRice/AppStore+Ingest.swift:24`), and
   folder addition returns before discovery (`:134–159`). Scheduled import
   passes it through the default pipeline factory
   (`Sources/UnliRiceCore/Schedule/RoutineDriver.swift:88`); daemon manual import
   does likewise (`Sources/unlirice-agent/main.swift:125`). Scheduled and daemon
   manual janitors pass `detectsDuplicates` (`RoutineDriver.swift:322`,
   `Sources/unlirice-agent/main.swift:110`). Both app janitor actions use
   `janitorSimilarity()` (`Sources/UnliRice/AppStore+Janitor.swift:37`, `:57`),
   which returns locally when off (`:79–84`) before `remote.warm` (`:107`).
   The core skips only duplicate proposals, preserving other rules
   (`Sources/UnliRiceCore/Janitor/Janitor.swift:98–106`). The spy test passed,
   including its on control and cosmetic-tag assertion. Session import and the
   inbox deliberately remain (`RoutineDriver.swift:162–190`); the Extras copy
   names both exceptions (`Sources/UnliRice/AutomationView.swift:185`) and the
   separate draft hint (`:195`). Queued flags are not cleared by either setting.
   In-flight work may continue under the accepted next-run rule. Calibration
   and local draft advice retain their explicitly accepted defaults. Suggested
   fix: no additional caller gate found necessary; finish finding 3's app checks.

7. **[nit — pre-mortem 6, satisfied within the accepted proxy] Upgrade migration
   preserves Projects and To do for notes-only use and unresolved saved roots.**
   `Sources/UnliRice/Extras.swift:60–69` uses the non-empty event log or saved
   path array, not resolved bookmark results. It respects a saved empty array,
   ignores unknown values, and saves the initial choice immediately. Its sole
   production call is startup (`Sources/UnliRice/AppStore.swift:650`), before
   onboarding seeds notes (`:665`), so fresh seeds cannot classify a fresh
   install as an upgrade; later folder additions do not rerun migration. I found
   no loss of the two screens for an install matching the settled criterion.
   A missing/unreadable settings file still turns background extras off by the
   explicitly accepted policy (`docs/PLAN-memory-overhaul.md:368–369`). Suggested
   verification: add notes-only, saved-but-unresolved root, mirror-only root,
   empty-array and mixed known/unknown preference fixtures to the next isolated
   launch walk; those app cases remain unverified here.

8. **[nit — pre-mortem 7, 8 and 9, implemented] Ordinary doors, accepted deep
   links and the exact new copy follow the revised plan.** Home gates Projects
   (`Sources/UnliRice/HomeView.swift:16`) and Start Profile (`:158`); Garden
   gates To do (`Sources/UnliRice/ProjectGardenView.swift:94`). Sidebar rows,
   Capture and export are gated (`Sources/UnliRice/ContentView.swift:166–202`,
   `Sources/UnliRice/UnliRiceApp.swift:79`). Retrospective notices now navigate
   (`Sources/UnliRice/AppStore+Notices.swift:52–53`), and widget To do URLs have
   no Extras gate (`Sources/UnliRice/AppStore+TodoWidget.swift:15–16`). Separate
   memories stays reachable with multiple profiles
   (`Sources/UnliRice/SetupView.swift:19–24`); the header explains the exception
   (`Sources/UnliRice/AutomationView.swift:156`). The copy table is represented
   in `Sources/UnliRice/Extras.swift:13–34` and the two background rows at
   `AutomationView.swift:182–197`; A4's replacements are at `:251` and `:682`.
   `setExtra` only persists (`Extras.swift:44–51`), and Setup has an explicit
   Extras rendering case (`SetupView.swift:99–100`). Home's older shared-memory
   promise (`HomeView.swift:48–52`) remains an explicit release-positioning
   deferral (`docs/PLAN-memory-overhaul.md:376–377`). Suggested fix: none to these
   settled doors; do not read this source audit as completion of the UI walk.

9. **[nit — merge fixes, no regression found] Removing `closeAllPanes()` is
   correct for the current single-pane model, including archived targets.**
   Widget handoff resolution ends in `selectNote(target.id)`
   (`Sources/UnliRice/AppStore+TodoWidget.swift:25–27`), and To do's Open button
   does the same for its item (`Sources/UnliRice/TodoPaneView.swift:194`). A
   non-nil selection sets `.notes` (`Sources/UnliRice/AppStore.swift:1378–1382`);
   the router displays its detail (`Sources/UnliRice/ContentView.swift:267–269`).
   `showingArchived` is derived from `pane` (`AppStore.swift:93`), rather than a
   separate flag that could remain on. Lookup includes archived notes
   (`:1080–1083`, `:1114–1119`), so an archived handoff can still be read without
   unarchiving it. Engineering Guardrails gained the plain to-do paragraph
   (`Sources/UnliRiceCore/HouseRulesPreset.swift:124`) and kept the working-state
   rule with a generic file name (`:126`), preserving its intent. All 13
   `HouseRulesTests`, including the studio-specificity, reviewed-checkpoint and
   all-presets to-do tests, passed. Suggested fix: none; verify note opening
   from another pane and from Archived in the remaining URL walk.

10. **[nit — remaining A5 checks, explicitly unverified] Finish the cheaper UI
    checks after the write/network checks in finding 3.** The missing cases are
    enumerated at `docs/PLAN-memory-overhaul.md:408–422`; no running-app checks
    were performed in this review. Suggested shortest checks:

    | Unverified case | Cheapest isolated check before merging |
    | --- | --- |
    | Fresh sidebar | Empty settings/log, absent Extras preference, launch and inspect no EXTRAS heading or Projects card; relaunch and recheck. Disk defaults alone do not prove rendering. |
    | Garden's To do button | Leave Projects on, turn only To do off, open Garden; toggle back on and check the button returns. Projects need not be off. |
    | Year-so-far and Capture switches | Toggle each in Setup, observe the sidebar row/card appear and disappear, relaunch once to check persistence. |
    | Retrospective notice | Seed a retrospective notice into the scratch notice store, turn the extra off, open it from Needs you, and check both navigation and read status. No need to wait for a due month. |
    | Widget URL and handoff | Target the QA bundle explicitly when opening valid `unlirice://` URLs; test To do and handoff with Extras off while another pane is open, including an archived handoff. Generic URL dispatch can hit the installed app. |
    | Separate memories switch and multi-profile exception | In a disposable user account, use scratch profiles; check the tab with one profile on/off and with two profiles while off. Do not mutate the founder's installed registry. |
    | Five tabs at 960pt | Turn Separate memories on with one profile, resize to the minimum width, and click all five tabs. This layout check does not require creating a second profile. |

11. **[nit — lessons for B/C] Specify every persistence boundary and every
    observable effect before calling a future phase verified.** Phase A needed
    both settings reconstruction and UI caller audits; core green tests alone
    miss both. The QA environment is still not fully isolated:
    `AppStore.swift:105` constructs `ProfileRegistry()` using
    `Sources/UnliRiceCore/Profile.swift:43–44`, independent of the event-log and
    settings overrides, which explains the documented multi-profile test limit.
    Suggested requirement for the B/C redrafts: identify and isolate the registry,
    defaults, export destination and all new evidence stores as well as the two
    existing override paths; specify consent/unknown states and acceptance at
    the actual writer/reader boundary. Do not revive the rejected full-text
    append or keyword-only eval designs. Existing raw copies are content-addressed
    (`Sources/UnliRiceCore/Ingest/RawStore.swift:118–142`), while shard publication
    reads/writes event lines (`Sources/UnliRiceCore/Sync/ShardPublisher.swift:28`,
    `:76–89`); B/C must explicitly handle missing raw evidence and keep copied
    memories out of unintended mirror/sync paths. Phase A adds no event/schema
    coupling that forces the rejected designs. This is a lesson for the already
    reopened phases, not a replacement plan or authorization to build them.

12. **[nit — independent verification result] Build and tests passed on
    `2e516a5`; remaining warnings and omissions are not hidden.**
    `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build` exited
    0. `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`
    exited 0: **471 tests executed, 2 skipped, 0 failures**, including all six
    Extras tests. The skips require `UNLIRICE_TEST_REPO` and
    `UNLIRICE_TEST_SNAPSHOT` (`Tests/UnliRiceCoreTests/GitRepoScannerTests.swift:210`,
    `Tests/UnliRiceCoreTests/RepoSnapshotFileTests.swift:110`). Build warnings
    include inaccessible user-level SwiftPM cache directories and the existing
    missing Combine import at `Sources/UnliRice/NoteGraphView.swift:183`.
    Logs are `/tmp/unlirice-postmortem-build.log` and
    `/tmp/unlirice-postmortem-tests.log`. No independent Xcode build or
    `xcodegen generate` was run; the earlier Xcode result remains the planner's
    recorded verification. The Unli Rice MCP tools were unavailable, so wiki
    and project to-dos could not be checked. Only this appended dialogue turn
    was authored; the pre-existing untracked review brief was left untouched.
    No commit, nested Codex run, application settings edit or live-vault UI
    operation was made. Suggested follow-up: retain these exact results and
    the unverified UI distinctions when deciding whether to merge.

## claude — response — 2026-10-29

Checked each finding against the code before answering.

1. Accepted and fixed. The folder picker now says "Add a project folder" / "Add Folder" with
   import off, and keeps the indexing copy with it on (`AppStore+Ingest.swift:105-114`). The Data
   pipelines card's subtitle names the switch, and its status reads "Local documents — off in
   Setup › Extras. N folder(s) added for Projects only." when folders exist but import is off.
2. Accepted and fixed: a flaw in the settled plan, not the builder. Both background rows are
   enabled whatever the background switch says. With background work off, their line now reads
   "Runs on its own only with background work on (Setup › What runs on its own); Ingest now and the
   janitor buttons follow this switch either way." Plan copy table updated.
3. Accepted, still open. Both app-boundary checks need the open panel and a local request counter
   in a running QA app; window capture failed on 2026-10-29. Listed as the first thing to verify
   before merging to `main` (plan Build notes, memory.md Next step).
4–9. Agreed; nothing to change. The path-scope box is ticked with this response.
10. Accepted as the remaining walk list; moved into the plan's Build notes verbatim by reference.
11. Accepted for the B and C redrafts: isolate the profile registry, defaults domain, export
    destination and every new evidence store, not only the two override paths.
12. Matches my own run: 471 tests, 2 skipped, 0 failures after these fixes; Mac build succeeded.
