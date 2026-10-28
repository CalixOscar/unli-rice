# PLAN — Overhaul: guardrails, grounding and evals

**Intent:** `docs/intent/INTENT-007-memory-overhaul.md`
**Planner:** claude. **Reviewer:** codex.
**Stage:** 6 Phase A post-mortem answered (2026-10-29); unverified items in Build notes; Phases B and C reopened (2026-10-29)
**Pre-mortem:** `docs/dialogue/memory-overhaul.md` (codex, 2026-10-29: 21 findings, all accepted)
**Branch:** `claude/memory-overhaul`, cut from `main` after A0 merges `feature/todo-widget`.
**Verified against:** `0ba0c1a` on `main`

## 0. What was asked for

> "Based on the latest changes in the AI world with [Claude's] memory added and especially agents,
> let's do an overhaul of Unli Rice and figure out what is needed and what is not."
>
> "Make more switches for the nice to have but not needed. Let's stick to the core of having
> guardrails, grounding and evals sort of in the app."

Founder decisions, 2026-10-29: INTENT-007's job table and Extras table as drafted, and the drafted
defaults for its open questions:
- **Q2 positioning:** yes. "Guardrails, grounding and evals for your AI tools."
- **Q3 folder grant:** asking once for `~/.codex` is acceptable.
- **Q4 writing:** stay read-only and copy-only.
- **Q5:** merge `feature/todo-widget` into `main` before this branch starts.
- **Q6:** Projects and To do stay on for existing users who already use them.
- **Q7:** evals cover coding-agent transcripts only at first.

**The promise, narrowed (pre-mortem 1):** Unli Rice lets you *inspect the local memory files you
choose*, and *checks observable actions in supported session logs*. It does not claim to know what
an AI loaded, retained or obeyed. Unsupported sources and undecidable results are shown as such.

**This plan is staged.** Phase A (navigation and Extras switches) is settled and build-ready.
Phases B (memory files) and C (evals) were reopened by the pre-mortem: each gets a new draft
that starts from Codex's findings and goes back to Codex before any build. Phase D is named, not
designed.

## 1. What already exists (checked, not assumed)

- **Sidebar:** `ContentView.swift:122-185`. Headings CONTEXT (Home, Notes, The folder your AI can
  read), GUARDRAILS (What your AI should always do, To do, Needs you), SECURITY (Trust Center,
  Archived notes), PROJECTS (Projects). Setup sits at the bottom after a `Spacer()` (`:180-186`).
  `CapturePromoCard()` isn't placed anywhere (hidden in four-jobs).
- **Routing:** `AppStore.Pane` (`AppStore.swift:60-64`) with `.map` and `.retrospective` still
  routed in `ContentView.mainColumn` (`:228-250`). `showGraph()` (`AppStore.swift:1313`) and
  `showRetrospective()` (`:1321`) exist but nothing in the sidebar calls them.
- **Setup tabs:** `SetupView.Tab` (`SetupView.swift:9-16`): AI Tools, Folders, What runs on its
  own, Separate memories. Separate memories shows only when there's more than one profile (`:18-20`).
- **Profile Builder entry:** Home's "Start Profile" button (`HomeView.swift:157-159`) and Setup
  (`SetupView.swift:79`).
- **Export menu:** `UnliRiceApp.swift:79` filters `.zip` and `.pdf` out of `ExportFormat.allCases`.
- **Preferences:** UI preferences live in `UserDefaults`. Settings the background agent needs live in
  `AgentSettings` (`Sources/UnliRiceCore/Agent/AgentSettings.swift`, Codable, saved by
  `AppStore.syncAgentSettings()` at `AppStore.swift:1004`). The pattern for a background switch is
  `routinesEnabled` (`AppStore.swift:439-444`).
- **Ingest:** `Pipelines.standard(scanRoots:claudeProjectsDirectory:)`
  (`RoutineDriver.swift:19-37`) adds `ClaudeSessionImporter` when there's a Claude folder grant, and
  `LocalFileImporter` for scan roots. The Notes for Unli Rice inbox importer is separate
  (`RoutineDriver.swift:166`).
- **Janitor:** `JanitorConfig` (`Janitor.swift:15-25`) has only `autonomy`. Duplicate proposals
  come from the structural rules (`Janitor.swift:154-173`). Similarity is local
  `TokenOverlapSimilarity` unless the localhost embedding connection is set.
- **Toggle row:** `AutomationToggleRow` (`AutomationView.swift:144`, from four-jobs B4).
- **Claude folder grant:** `unliRice.claudeProjectsBookmark` (`AppStore+Ingest.swift:210`),
  mirrored into `AgentSettings.claudeProjectsBookmark`. It covers `~/.claude/projects/`, which holds
  both the session transcripts and Claude Code's memory folders (`<project>/memory/*.md`).
- **Session parser:** `ClaudeSessionImporter.ParsedSession` (`ClaudeSessionImporter.swift:83-95`)
  keeps titles, prompts and counts only. No tool calls, no `gitBranch`. Real transcript lines carry
  `cwd` and `gitBranch` (seen in `~/.claude/projects/*/*.jsonl`, 2026-10-29).
- **Raw copies:** ingest keeps copies of session transcripts in the data folder's `raw/`
  (`RawStore.swift`). Claude Code deletes its own transcripts after its cleanup period, so `raw/`
  is the longer record.
- **Event kinds:** `Event.swift:7-14`: created, appended, tagged, untagged, archived, unarchived,
  flagged, reviewResolved. Locked: no new kinds without a plan-level justification.
- **Dev evals:** `evals/` (Python, 9 cases, deterministic assertions plus an optional localhost
  judge). Dev tooling; not shipped.
- **Pending merge:** `feature/todo-widget` (25 commits, the 1.3 release). `git merge-tree` against
  `main` at `d6d8602`: code auto-merges; `PROJECT_NOTES.md` and `memory.md` conflict.

## 2. Decisions

1. **Three jobs in the sidebar: GROUNDING, GUARDRAILS, EVALS.** SECURITY folds into GUARDRAILS.
   PROJECTS becomes an extra. The EVALS heading appears only once Phase C gives it a row.
2. **Extras are per-feature switches** in a new Setup › Extras tab. A switch controls the *door*
   (sidebar row, menu item, button). It never deletes code or data. A deep link to an extra
   that's off (a notice opening Your year so far, the widget opening To do) still opens the pane.
3. **UI extras live in `UserDefaults`**, one key `unliRice.enabledExtras` holding the raw values
   of the extras that are on. **Background extras live in `AgentSettings`**, because the background
   agent must read them.
4. **Defaults that don't take things away** (pre-mortem 2, 6).
   - Projects and To do: when `unliRice.enabledExtras` is absent (first launch of this version),
     they start **on** for an existing install, meaning the event log exists and is non-empty, or
     `unliRice.scanRoots` holds any saved path, resolved or not. A new install starts with them
     off. The result is written immediately and never recomputed. A saved empty array is respected.
     Every other UI extra starts off.
   - Background extras: decoding an existing `AgentSettings` file that lacks the keys gives **on**
     (today's behaviour). A missing or unreadable file gives **off**: less background work, never
     more. The app reads the file once at launch, before anything saves over it.
5. **Off means off** (pre-mortem 4, 5). With bulk import off, adding a folder doesn't read
   its files or offer an import. With duplicate detection off, the app janitor uses local token
   overlap and never contacts the embedding server. A switch takes effect from the next run;
   flags already queued stay for review. **Exceptions, stated in the copy:** Claude Code session
   import and the Notes for Unli Rice inbox keep running. The draft hint while writing a note
   stays on: it's local and synchronous.
6. **Unli Rice never writes to another tool's files**, in any phase.
7. **Evals are deterministic and read-only** (Phase C). No model in the app. Judged checks are
   Phase D, localhost only or a copyable prompt.

## 3. Point of view and patterns

Studio voice: calm, concise, discreet. Evals report what happened with the transcript line that
decided it. No scores, grades or streaks. Unknown stays unknown (INTENT-002): a session with no
commit is "nothing to check", never a pass.

Reuse: `AutomationToggleRow` for every switch, `Card` for groupings, the four-jobs sidebar helpers
(`sidebarHeading`, `sidebarRow`).

## 4. Journey and states (Phase A)

1. A new user opens the app. The sidebar reads GROUNDING (Home, Notes, The folder your AI can read)
   and GUARDRAILS (What your AI should always do, Needs you, Trust Center, Archived notes), then
   Setup.
2. Setup › Extras lists nine switches, all off. Turning on Map adds an EXTRAS heading and a Map row
   above Setup. Turning it off removes both.
3. An existing user with project folders updates. The sidebar shows the two jobs, plus EXTRAS with
   Projects and To do, both on. Nothing they used is gone.
4. An existing user with background work on keeps importing folder files and getting duplicate
   suggestions until they turn those extras off.

## 5. Tasks

### Phase A — the three jobs and Extras (build-ready)

#### A0. Merge and baseline (`planner`)
- [x] `planner` Merged `feature/todo-widget` into `main` (`b35b0c9`). Notes conflicts kept both
      sides. Three merge fixes: the widget handoff link and To do's Open button called the removed
      `closeAllPanes()`; Engineering Guardrails gained the plain to-do paragraph and lost its
      `memory.md` example, per the widget branch's preset test. 465 tests, 2 skipped, 0 failures;
      `UnliRice` and `UnliRiceCapture` BUILD SUCCEEDED (verified: swift test + xcodebuild, Claude, 2026-10-29).
- [x] `planner` Cut `claude/memory-overhaul` from `b35b0c9`.

#### A1. Background extras in core (`build`)
- [x] `build` _(built 2026-10-29; 471 tests, 2 skipped, 0 failures, verified by Claude)_ `AgentSettings`: add `public var bulkImportEnabled: Bool` and
      `public var duplicateDetectionEnabled: Bool`, with `CodingKeys` entries and init parameters
      (default `false`). `init(from:)` uses `decodeIfPresent(...) ?? true` for both.
      `Pipelines.standard` gains `includeLocalFiles: Bool = true` and skips `LocalFileImporter`
      when false. `JanitorConfig` gains `public let detectsDuplicates: Bool` (init parameter,
      default `true`); `Janitor.scan` (`Janitor.swift:96`) skips `duplicateProposals` entirely when
      it's false, so the provider is never called.
      Callers in this step: `RoutineDriver.swift:88` passes
      `includeLocalFiles: settings.bulkImportEnabled`; `RoutineDriver.swift:322` and
      `unlirice-agent/main.swift:110` pass `detectsDuplicates: …duplicateDetectionEnabled`;
      `unlirice-agent/main.swift:125` passes `includeLocalFiles: manualSettings.bulkImportEnabled`.
      Left on the defaults, deliberately: `janitor-calibrate` and `AppStore+Drafts.swift:16`.
      Tests in a new `Tests/UnliRiceCoreTests/ExtrasSettingsTests.swift`:
      (a) today's settings JSON without the keys decodes to both `true`;
      (b) explicit `false` survives save → load;
      (c) `AgentSettings.load(from:)` on a missing file and on a corrupt file gives both `false`;
      (d) toggle → save → load → save → load keeps the value (two "launches");
      (e) `Pipelines.standard(…, includeLocalFiles: false)` with a scan root has no `LocalFileImporter`;
      (f) a spy `SimilarityProvider` records zero calls with `detectsDuplicates: false`, while an
          `addTag` proposal on the same notes is still produced.
      — files: `Sources/UnliRiceCore/Agent/AgentSettings.swift`,
      `Sources/UnliRiceCore/Schedule/RoutineDriver.swift`, `Sources/UnliRiceCore/Janitor/Janitor.swift`,
      `Sources/unlirice-agent/main.swift`, `Tests/UnliRiceCoreTests/ExtrasSettingsTests.swift` (new)
      — verify: `swift build` and `swift test` green, new tests included

#### A2. Extras state in the app (`build`)
- [x] `build` `AppStore.swift`:
      add `@Published var enabledExtras: Set<Extra> = []`, `static let enabledExtrasKey = "unliRice.enabledExtras"`,
      and `@Published var bulkImportEnabled = false` / `@Published var duplicateDetectionEnabled = false`,
      each with `didSet { syncAgentSettings() }` (they live in `AgentSettings`, not `UserDefaults`).
      In `init`, **immediately after `noticeStore = driver.noticeStore` (`AppStore.swift:627`, the one
      inside `init`; not the one at `:865`) and before `reload()` and the launch `syncAgentSettings()` (`:677`)**: read
      `let persisted = AgentSettings.load()` once; assign both published values from it; then call
      `loadExtras()`. (Property observers don't fire for assignments in the class's own `init`.)
      The computed `agentSettings` (`:929-947`) passes `bulkImportEnabled: bulkImportEnabled,
      duplicateDetectionEnabled: duplicateDetectionEnabled`.
- [x] `build` New file `Sources/UnliRice/Extras.swift`:
      `enum Extra: String, CaseIterable, Identifiable { case projects, todo, map, yearSoFar, profiles, extraExports, capturePromo }`
      with `id`, `title`, `detail` from A3's copy table. An `AppStore` extension with
      `func isOn(_:) -> Bool`, `func setExtra(_:on:)` (updates the set, writes raw values to
      `UserDefaults`, never navigates), and `func loadExtras()`: if the key is absent, the set is
      `[.projects, .todo]` when `FileManager` reports the event log at `dataURL` exists with size > 0
      or `UserDefaults.standard.stringArray(forKey: Self.scanRootsKey)` is non-empty, else `[]`;
      write it at once. If present, read it, ignoring unknown raw values (an empty array stays empty).
- [x] `build` App callers: `AppStore+Ingest.swift:24` passes `includeLocalFiles: bulkImportEnabled`.
      `AppStore+Janitor.swift:37-39` and `:57-59`: when `!duplicateDetectionEnabled`, use
      `TokenOverlapSimilarity()` and skip `similarityProvider()`; pass
      `JanitorConfig(autonomy: autonomy, detectsDuplicates: duplicateDetectionEnabled)`.
      `addScanRoot` (`AppStore+Ingest.swift:118-185`): after `scanRoots = change.roots`, when
      `!bulkImportEnabled`, set `statusMessage` to the A3 "folder added" copy and return before
      the `LocalFileImporter` discovery and alert.
      — files: `AppStore.swift`, `Extras.swift` (new: run `xcodegen generate`), `AppStore+Ingest.swift`,
      `AppStore+Janitor.swift` — verify: `swift build` green
      _(built 2026-10-29; 471 tests, Mac build green, verified by Claude. Builder addition kept:
      `janitorSimilarity()` also resets `similarityEngine` to token overlap when duplicates are off.)_

#### A3. Sidebar, doors and Setup › Extras (`build`)
- [x] `build` Sidebar (`ContentView.swift:122-185`):
      GROUNDING: Home, Notes, The folder your AI can read (unchanged actions).
      GUARDRAILS: What your AI should always do, Needs you (with its badge), Trust Center, Archived
      notes. Remove the SECURITY and PROJECTS headings and the To do and Projects rows.
      Then, only if any of projects / todo / map / yearSoFar is on: heading EXTRAS, with whichever of
      these rows are on, in this order: Projects (`showGarden()`, active on `.projects`/`.repos`),
      To do (`showTodo()`), Map (`showGraph()`, active on `.map`), Your year so far
      (`showRetrospective()`, active on `.retrospective`). Each row calls `store.selectNote(nil)`
      first. Then `Spacer()`; then, if capturePromo is on, `CapturePromoCard()`; then Setup as today.
      Sidebar subtitle (`:115`): "AI Notes & Memory" → "Guardrails, grounding, evals".
- [x] `build` Doors:
      `HomeView.swift:16` renders `gardenEntry` only when projects is on.
      `ProjectGardenView.swift:94`'s "To do" button only when todo is on.
      `HomeView.swift:157-159`'s "Start Profile" only when profiles is on.
      `SetupView.visibleTabs` shows Separate memories when profiles is on *or* there's more than one profile.
      `UnliRiceApp.swift:79` filters `.zip`/`.pdf` out only when extraExports is off.
      `AppStore+Notices.swift:52`: `.retrospective` calls `showRetrospective()` (replaces the `break`).
- [x] `build` Setup › Extras: add `case extras = "Extras"` to `SetupView.Tab` after `.automation`,
      and `case .extras: ExtrasView()` to the tab switch (`SetupView.swift:66-98`). `ExtrasView` in
      `Extras.swift`: `ScrollView { VStack(alignment: .leading, spacing: 16) { … } }` with 24pt
      horizontal padding. First `Card` (icon `square.grid.2x2`, title "Extras", subtitle = header
      copy) holds one `AutomationToggleRow` per `Extra.allCases`, in order, bound through
      `isOn`/`setExtra`, spaced as `ScheduleCard`'s rows are. Second `Card` (icon `moon`, title
      "Extras that run in the background", no subtitle) holds the two background rows, bound to
      `bulkImportEnabled` and `duplicateDetectionEnabled`, using `AutomationToggleRow`'s `disabled`
      argument when `!store.routinesEnabled`.
- [x] `build` `AutomationView.swift`, JanitorCard: under `embeddingServerRow` (`:354`), a 12pt
      `Theme.textSecondary` line: "Used only to spot duplicate notes, when that's on in Setup › Extras."
      — files: `ContentView.swift`, `HomeView.swift`, `ProjectGardenView.swift`, `SetupView.swift`,
      `UnliRiceApp.swift`, `AppStore+Notices.swift`, `AutomationView.swift`, `Extras.swift`
      — verify: `swift build` green
- [x] `planner` Copy (exact):

      | Where | Text |
      |---|---|
      | Extras header | "Things Unli Rice can do beyond its three jobs. Turning one off removes its buttons from the app; nothing is deleted. Separate memories stays while you have more than one." |
      | projects | **Projects** — "Git status and next steps for the folders in Setup › Folders." |
      | todo | **To do** — "A list built from your repos, project notes, and notes your AI tagged." |
      | map | **Map** — "A graph of how your notes link to each other." |
      | yearSoFar | **Your year so far** — "A look back over a month or a year of your notes." |
      | profiles | **Separate memories** — "Keep more than one memory, each with its own notes." |
      | extraExports | **PDF and ZIP export** — "Adds PDF and ZIP to File › Export." |
      | capturePromo | **iPhone Capture** — "Shows the card for the free iPhone app in the sidebar." |
      | bulkImport | **Import files from your folders** — "Reads the Markdown and text files in Setup › Folders and adds them as notes. Claude Code sessions and the Notes for Unli Rice folder are imported either way." |
      | duplicates | **Spot duplicate notes** — "Suggests merging notes that look alike, when the janitor runs. Nothing merges without your OK. The hint while you write a note is separate." |
      | background off | Both background rows append: " Runs on its own only with background work on (Setup › What runs on its own); Ingest now and the janitor buttons follow this switch either way." The rows stay enabled (post-mortem 2). |
      | folder added, import off | "\(name) added. Projects reads its git details; its files aren't imported as notes. To import them, turn on Import files from your folders in Setup › Extras." |

#### A4. Copy that now says the wrong thing (`build-light`)
- [x] `build-light` `AutomationView.swift:185` (routines on) becomes: "Unli Rice imports new Claude
      Code sessions each time it checks in. If Import files from your folders is on (Setup ›
      Extras), it also reads the folders in Setup › Folders. Both add and tag notes; merges and
      archives are only ever suggested for your OK."
- [x] `build-light` `AutomationView.swift:612` becomes: "Projects reads git details from these
      folders. With Import files from your folders on (Setup › Extras), Unli Rice also imports the
      Markdown and text files in them as notes."
      — files: `AutomationView.swift` — verify: `swift build` green
      _(done by the planner, smaller than a handoff; swift build green, 2026-10-29)_

#### A5. Verify (`planner`)
- [x] `planner` Review each builder diff against this plan. `xcodegen generate` (after A2's new
      file), `swift test`, Xcode Mac build. _(471 tests, 2 skipped, 0 failures; BUILD SUCCEEDED, 2026-10-29)_
- [x] `planner` Isolated running-app checks _(partly: see Build notes; unverified items listed there)_ (debug binary in a scratch `.app`; memory.md Gotchas).
      Export the debug defaults domain first and restore it after (four-jobs B6). Set both
      `UNLIRICE_DATA_PATH` and `UNLIRICE_AGENT_SETTINGS` to scratch paths. Never toggle the login item.
      1. Fresh: no event log, no settings file, no `enabledExtras`. Sidebar shows two jobs, no
         EXTRAS; nine switches off; Home has no Projects entry.
      2. Upgrade: a non-empty event log and an old settings JSON without the new keys. After
         launch, Projects and To do are on, and the settings file on disk has both background keys
         `true`. Quit, relaunch: unchanged.
      3. Each switch on and off, relaunching once; the multi-profile exception; File › Export with
         extraExports on and off.
      4. Bulk import off: add a scratch folder with two `.md` files. No alert; the event log and
         `raw/` are byte-identical before and after.
      5. Duplicates off, with an embedding URL pointing at a local listener: Janitor Preview makes
         no request to it.
      6. Doors with extras off: Home, Garden's To do button, a year-so-far notice (opens the page),
         a widget To do URL after A0 (opens To do).
      7. Setup's five tabs at the 960pt minimum width.

### Phase B — Memory files (reopened by pre-mortem 10–12; redraft before build)

The first draft below failed review. The redraft must answer, at minimum: content-addressed raw
copies plus small structured observation notes and a derived current-file reader instead of
full-text `appended` history (10); its own writer, stable source identity, title collisions,
unavailable-not-deleted, hash reversion (11); explicit consent with a preview, allowlists,
symlink and size bounds, a pre-write secret screen, and keeping these copies out of the
folder mirror's `Context/RAW` and of sync (12). Kept here for the record:


- **Sources.** Claude Code: `~/.claude/projects/*/memory/*.md`, through the existing Claude folder
  grant. Codex: `~/.codex/AGENTS.md` and `~/.codex/memories/**`, through a new one-time grant
  (`unliRice.codexBookmark`, mirrored into `AgentSettings`; the open panel shows hidden files).
  Repos: `AGENTS.md`, `CLAUDE.md` and `memory.md` at the root of each repo `GitRepoScanner` already
  finds under scan roots.
- **Mirror.** A new core `MemoryMirror` (a `ResourceImporter`) runs on each ingest tick and when
  the app opens. One note per file, titled `Memory: <tool> · <project> · <file name>`, source
  `memory-mirror`, tagged `memory` and the tool name. When a file changes, the note gets an
  `appended` event: `— changed <ISO date> —` and the full new text. Files over 32,000 characters
  are skipped with one notice. A deleted file gets one appended line saying so; the note is never
  archived automatically.
- **Pane.** GROUNDING › "What each AI remembers": grouped by tool, then project. Each file shows
  its current text, when it last changed, and its history (from the note's events). Read-only, with
  a "Show in Finder" for the source file.
- **Setup › AI Tools** gains the Codex grant row next to the Claude one.
- **Tests:** a mirror run over a fixture tree (create, change, unchanged, oversized, deleted).

### Phase C — Evals (reopened by pre-mortem 13–20; redraft before build)

The redraft must: read canonical records and join tool calls to results (13); use four outcomes:
followed / broke / not applicable / can't tell (13); name each check after the signal it can
actually observe, and define it precisely or drop it: test result before an actual commit (14),
branch resolution at the action (15), explicit approval rather than a keyword (16), a supported
shell grammar and real scratch roots (17), credential-shaped text in successful writes with
redacted evidence (18), normalised folder boundaries (19); and define live-versus-`raw/`
precedence, version selection and missing-evidence states (20). Kept here for the record:


- **Reader.** A new core `TranscriptReader` turns a Claude Code `.jsonl` (from `~/.claude/projects`
  or `raw/`, deduplicated by session id) into an ordered list: user messages, and tool calls with
  name, input, `cwd`, `gitBranch` and timestamp. The format is read off real files first, as
  `ClaudeSessionImporter` was.
- **Checks v1** (each a small type with id, title, evaluate → pass / fail / nothing to check, plus
  the deciding line):
  1. `tests-before-commit`: every `git commit` has an earlier test command in the same session
     (`swift test`, `xcodebuild … test`, `npm|pnpm|yarn test`, `pytest`, `cargo test`, `go test`,
     `make test`).
  2. `no-commit-on-main`: no `git commit` while `gitBranch` is `main` or `master`.
  3. `no-push-unasked`: every `git push` comes after a user message containing "push".
  4. `no-destructive-commands`: no `git reset --hard`, `git push --force`/`-f`, `git clean -f`, or
     `rm -rf` outside the session's scratch and `/tmp`.
  5. `no-secrets-written`: no Write/Edit content matching the private-key, `AKIA…`, `sk-…`,
     `ghp_…` patterns from the studio's secret scan.
  6. `stayed-in-folder`: Write/Edit paths are under the session `cwd`, `/tmp` or the scratchpad.
- **Pane.** EVALS › "Did your AI follow the rules": the last 30 days by default. One row per check
  with counts (followed / broke / nothing to check). Each failure opens the session, date and the
  exact line. A "Copy a note for your AI" button copies a plain-language reminder of the rule.
  Each check can be turned off. No score, no grade.
- **House Rules link.** The Engineering Guardrails preset lists checks 1–5 as the rules it can be
  checked against. Other presets show "No automatic checks for these rules yet."
- **Codex transcripts** follow once their format is read off real files (not on this Mac yet).
- **Tests:** each check against fixture transcripts (pass, fail, nothing to check), plus a fixture
  with `gitBranch` missing (→ nothing to check, not pass).

### Phase D — later, not designed

Drift flags (two tools' memories disagree, or a memory contradicts a House Rule: needs a model,
so localhost or a copied prompt), judged checks using `evals/rubric.md`, a trend per tool, and
trimming the MCP tool list once recorded transcripts show which tools agents call.

## 6. Acceptance — against reality, not a builder's report

**Mechanical (Phase A)**
- [x] `swift build` / `swift test` green: 471 tests, 2 skipped, 0 failures. Xcode Mac build succeeds (Claude, 2026-10-29).
- [x] `git diff --name-only` for Phase A within the files named in A1–A4, plus this plan,
      `docs/dialogue/memory-overhaul.md`, `memory.md`, `PROJECT_NOTES.md`.
- [x] A1's tests (a)–(f) present and passing (`ExtrasSettingsTests`, 6 tests).
- [x] A5's seven running-app checks done, or each marked "(unverified)" with why (Build notes).
- [x] No change to `Event.swift`, the note format or sync shards (checked: `git diff b35b0c9 --stat`).

**Editorial — in a running build**
- [x] With the styling ignored, the sidebar says the app is about grounding and guardrails (seen: upgrade profile, 2026-10-29).
- [x] Every extra comes back with its switch and goes away without one (all seven seen, 2026-10-29 walk).
- [x] Existing-user defaults seen, not assumed (A5 checks 1 and 2, including the JSON on disk).

## 7. Known limits, accepted

- An extra that's off can still be opened by a deep link. Accepted: notices and the widget keep working.
- "Existing install" (non-empty event log or any saved scan root) is broader than "has used
  Projects/To do". Accepted: it errs towards keeping a screen on.
- A corrupt or missing settings file turns both background extras off. Accepted: it errs towards
  less background work.
- Phase A ships a sidebar with no EVALS heading. It appears with Phase C.

## 8. Rides along or deferred

- **Founder, before Phase B is redrafted** (pre-mortem 1): check the real note and event counts
  in the installed app (by source), and name one concrete task the memory view should save time on.
- App Store listing, screenshots, the public roadmap page, and Home's "one memory your AI tools
  share" copy (`HomeView.swift:44-52`): release positioning, after Phase C.
- Deleting code for any extra: a later decision (INTENT-007 scope).
- `feature/byo-llm` and `docs/BYO_LLM.md`: close in A0's housekeeping commit.
- Archive `docs/ANTIGRAVITY_*.md`; prune `.claude/worktrees/`: housekeeping, any time.

## 9. Pre-mortem responses

All 21 findings accepted; answers in `docs/dialogue/memory-overhaul.md` (claude — response —
2026-10-29). Phase A revised (A1–A5, decisions 4–5, §6–§8). Phases B and C reopened.

## Handoff

Builders get one step at a time under AGENTS.md § Builder contract, on `claude/memory-overhaul`.

## Build notes

- **A3, 2026-10-29:** the builder stopped because `Card` is `private` in each file that has one
  (`AutomationView.swift:63`, `ConnectView.swift:446`, `RetrospectiveView.swift:388`). Planner
  decision: `ExtrasView` lives in `AutomationView.swift`, beside `Card` and `AutomationToggleRow`,
  as four-jobs did for Setup's other cards. `Extras.swift` keeps the model only.
- **A3 review fixes (planner):** the first sidebar heading renamed CONTEXT → GROUNDING (the builder
  left it, unsure); `Card` in `AutomationView.swift` skips an empty subtitle, so the background card
  has no blank line. 471 tests, Mac build green (Claude, 2026-10-29).
- **A5 walk, 2026-10-29 (planner).** Two scratch `.app` bundles wrapping the debug binary, each with
  its own bundle ID (fresh defaults domain) and `LSEnvironment` pointing `UNLIRICE_DATA_PATH` and
  `UNLIRICE_AGENT_SETTINGS` at scratch. Both domains deleted afterwards; no login item touched.
  - Check 2, **verified on disk**: upgrade profile (one-note event log, old settings JSON without the
    keys, no `enabledExtras`). After launch: `enabledExtras = [projects, todo]`; the settings file
    gained `bulkImportEnabled: true`, `duplicateDetectionEnabled: true`. After quit and relaunch:
    unchanged. (`routinesEnabled` became `false` because it lives in the empty QA defaults domain:
    existing behaviour, not this plan.)
  - Check 1, **verified on disk only**: fresh profile wrote `enabledExtras = []` and both background
    keys `false`. Its window could not be captured (macOS delivered no picture), so the no-EXTRAS
    sidebar was not seen (unverified).
  - Check 3, **partly verified**: sidebar read GROUNDING / GUARDRAILS / EXTRAS with To do and Map
    after turning Map on and Projects off; `enabledExtras` followed each click. File › Export Notes
    listed Markdown and OKF with PDF/ZIP off, and added Zip and PDF with it on; both survived a
    relaunch. Setup showed four tabs (Separate memories hidden: off, one profile) within the 960pt
    window. The background card showed both switches on, disabled, with the "Needs background work
    on" sentence, and no blank subtitle line. Unverified: Your year so far, Separate memories and
    iPhone Capture switches; the multi-profile exception (`profiles.json` is the App Store app's).
  - Check 6, **partly verified**: Home lost the Projects card with Projects off. Unverified: Garden's
    To do button (Garden unreachable with Projects off in that run), the year-so-far notice (no
    notice was due) and the widget URL (it opens the installed App Store app, not a QA bundle).
  - Checks 4 and 5, **unverified in the running app**: adding a folder needs the open panel, and
    the duplicates check needs a local embedding listener; window capture failed before either.
    Covered by code review (`addScanRoot` returns before `LocalFileImporter`; `janitorSimilarity()`
    skips `similarityProvider()`) and, for the core, by A1 tests (e) and (f).
- **Post-mortem fixes, planner (2026-10-29):** (1) the folder picker and the Data pipelines card
  follow the import switch; (2) the background Extras rows stay enabled with background work off,
  because the manual Ingest and janitor buttons obey them too (a flaw in the settled plan). 471
  tests, 2 skipped, 0 failures; Mac build succeeded. Still to verify in a running QA app before
  merging, riskiest first: folder addition with import off (no alert, event log and `raw/`
  unchanged); duplicates off with a local embedding request counter and an "on" control; then
  post-mortem 10's table (fresh sidebar, Garden's To do button, year-so-far and Capture switches,
  a seeded retrospective notice, QA-targeted widget URLs, five tabs at 960pt).
- **Second walk, 2026-10-29 (planner), QA bundle `overhaul-qa-walk`:** scratch vault with two
  near-duplicate notes, a seeded retrospective notice, an embedding address pointing at a local
  request counter, and its own `unlirice://` handler. Domain deleted afterwards; no login item.
  - **Duplicates off, verified:** Janitor Preview sent **0** requests and reported nothing to do.
    Positive control: duplicates on (switched with background work still off, so post-mortem fix 2
    is verified too) sent **1** `POST /v1/embeddings`, and the engine label changed to the model.
  - **Folder add with import off, partly verified:** the picker opened as "Add a project folder"
    with the new message and an "Add Folder" button (post-mortem fix 1). The picker runs in a
    separate macOS process that the QA grant can't drive, so a folder was **not** chosen: the
    no-alert, no-import return after choosing remains **unverified in a running app** (code review
    and A1 test (e) only). Needs a person to pick `qa/importme` once.
  - **Doors, verified:** Garden's To do button shows with To do on and disappears with it off; Your
    year so far, Separate memories (fifth tab, fits at 960pt) and iPhone Capture each appear and
    disappear with their switch; the all-off sidebar reads GROUNDING / GUARDRAILS / Setup only.
  - **Notice, verified after a fix:** opening the notice from All messages with Your year so far off
    showed the page and marked it read. It ignored the notice's period: A3 told the builder to call
    `showRetrospective()`, dropping the `period` the pre-four-jobs code passed. Restored
    `showRetrospective(periodID: period)`; a `2026` notice then opened 2026. (A month with no notes
    still falls back to the newest month: existing behaviour.) Needs you rows only offer Dismiss;
    opening is in All messages (existing four-jobs behaviour).
  - **Widget links, verified:** `unlirice://todo` opened To do with To do off; a note link sent
    while Archived was open brought the note forward in Notes (the `closeAllPanes()` merge fix).
  - **Sidebar overflow, found and fixed:** with Projects, Your year so far and the Capture card on,
    the sidebar outgrew the 628pt window and pushed the whole window's content up, clipping the
    top. The rows now sit in `ViewThatFits`: the old layout when it fits, a scrolling list above a
    pinned Setup when it doesn't. Seen fixed in the same state. 471 tests, 2 skipped, 0 failures;
    Mac build succeeded.

