# PLAN — Project Garden in Unli Rice

**Intent:** docs/intent/INTENT-005-project-garden.md
**Date:** 2026-10-19
**Planner:** codex
**Tier:** 2 conservatively: new derived project representation, though no persisted data model or format changes.
**State:** implemented, built and reviewed; interactive UI QA remains unverified
**Branch:** codex/project-garden
**Baseline:** c7b5d6e; working tree clean before these planning documents. Existing history from chore/plan-high-build-low is retained.

## 1. Outcome and architecture

Add a native **Garden** sidebar destination and a quiet entry from Home. Keep existing destinations. Garden assembles an in-memory report off the main thread from existing active notes, explicitly granted scan roots, and the optional existing repos.json. No persistence, ingestion, network request, subprocess, or mutation is added. The standalone Python/HTML dashboard supplies the product concept; none of its owner names, historical project stories, server, or snapshots is imported as application truth.

The overview consists of a short header, refresh, summary counts (projects, projects with Git details, open to-do notes), search, All/Needs attention filters, and adaptive project cards. Cards show recorded status and its source/date, a next step and its source when available, related-note count, open to-do/review counts, and conservative repository facts. Details show the full bounded status/next step and buttons to open related notes. Notes remain the same notes the app already displays. Empty states explain that folders are managed under More → What Runs on Its Own → Add Folder (or Add a folder to index in advanced mode), and offer a Manage project folders button through a new showGardenFolders() method routing to moreDestination = .automation. Explain that explicit Project: notes appear without any folder. No customer copy asks for a studio script. Existing To do and Repos remain available as deeper views.

## 2. Data contract and behavior

`Sources/UnliRiceCore/ProjectGarden.swift` exposes `public enum ProjectGarden` with these Sendable, in-memory value types (no Codable and no event/schema additions):

```swift
public struct Report: Sendable {
    public let projects: [Project]
    public let scannedAt: Date
    public let issues: [String]
}
public struct Project: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let folderURL: URL?
    public let status: String?
    public let statusSource: String?
    public let statusDate: Date?
    public let nextStep: String?
    public let nextStepSource: String?
    public let notes: [Note]
    public let repository: Repository?
    public let issues: [String]
    public var todoCount: Int { /* active related notes tagged todo */ }
    public var reviewCount: Int { /* unresolved flags on active related notes */ }
    public var needsAttention: Bool { /* todoCount > 0 or reviewCount > 0 */ }
}
public struct Repository: Sendable {
    public let currentBranch: String?
    public let branchCount: Int
    public let worktreeCount: Int
    public let differentTipCount: Int?
    public let observedAt: Date
    public let fromPublishedSnapshot: Bool
}
public static func load(roots: [URL], notes: [Note],
                        publishedSnapshot: RepoSnapshotFile? = nil,
                        now: Date = Date()) -> Report
```

Builders may add initializers/private helpers. Public field names/types and semantics above are fixed. Root and corpus access is started/stopped in balanced pairs inside the detached task, mirroring RepoPaneView.scan(), while the synchronous loader runs; tests use temporary folders. The core only reads the arguments' filesystem paths and never obtains grants itself.

### Discovery and identity

- A folder is a project when it contains `.git` (file or directory), `memory.md`, or `PROJECT_NOTES.md`. A granted project root itself is supported. Otherwise search beneath roots to depth 4, stopping descent when a project is found. Skip hidden directories, symlinks beneath roots, `node_modules`, build/dist/vendor/dependency and archive/backup directories. Honor the existing `LocalFileImporter.ignoreMarkerFilename` (`.unliriceignore`) at roots and descendants. A memory.md symlink must not be followed outside its project; report it as unavailable. Cap discovery at 2,000 directories / 500 projects, reporting truncation rather than silently presenting complete coverage. Use bounded reads of at most 128 KiB for memory.md; oversized/unreadable files produce issues, never a partial authoritative field.
- Path-based project IDs use standardized canonical directory paths, deduplicating overlapping grants. Different folders with the same basename remain different cards, with location shown. No global basename-keyed dictionary that can trap or merge them.
- Active notes titled `Project: <name>` explicitly register notes-only projects. A registration joins a folder only when the case-insensitive name match is unique. Otherwise keep it notes-only, without inventing a folder association. Do not infer projects from arbitrary tags.
- Match other active notes by exact project-path provenance (or a source-file path inside the project, using path components), and by case-insensitive exact project-name tag only when the discovered name is unique. Explicit provenance must win over a conflicting tag. Match to the most specific project folder. Never open a provenance path to discover or scan a new folder; provenance links notes, it does not grant filesystem access. Filter archived notes out even if passed in.
- Optional snapshot-only repositories may produce cards with IDs prefixed `snapshot:` and an explicit historical source/date. Match snapshot names to folders only when unambiguous. Guard duplicate snapshot names; never `Dictionary(uniqueKeysWithValues:)` on untrusted names.

### Status, next steps, and evidence

- A readable memory.md supplies its `**Status:**` field and existing `StudioTodo.nextStep(fromMemory:)` next-step parsing. Extract Status with the same multiline stopping rules. Treat this as *recorded status*, not verified release/test evidence. Cap extracted Status at 400 characters and next-step display text at 800 characters, with an ellipsis when shortened. Its date is file modification time, labeled as file updated rather than status verified.
- If no memory status is available, show an attributed excerpt from a related note. Prefer the explicit Project registration, then newest related note with deterministic ID tie-break. Strip an initial heading/metadata when selecting a short first prose paragraph; cap excerpts at 400 characters. Imported notes remain identified as imported notes, not fresh conclusions. Note dates are `updatedAt`, labeled as note updated. No automatic summarization or AI call.
- Note bodies can contain append-only revisions. For a note excerpt or registration Next step, use its latest `\n\n---\n` append block (or full body if no separator). Do not resurrect an earlier block's Next step when the latest block clears or omits it. The separator can also occur in pasted Markdown content: selecting its final fragment is an accepted display-only approximation, not a claim about event boundaries; never add an event-history walk to correct this. This is a display boundary only; no older note body is edited or removed. memory.md remains one current record and uses the existing parser directly.
- Readable memory with no Next step suppresses an older snapshot next step. Missing/unreadable memory may fall back to the matching optional snapshot's next step, with the snapshot date in its source label. A notes-only project may use an explicit Next step field in its registration; do not generate a task from generic prose. Do not equate having a field with needing attention: “None open” remains a quote, not a new task.
- Live repository facts come from the existing GitRepoScanner. A scan failure stays an issue/unknown; never use zeros as substitute facts. `differentTipCount` is nil when no cached remote refs exist. Otherwise it counts branch tips with no *identical* cached remote SHA; copy must say tips differ from cached remotes, never claim ancestry, genuinely unpushed commits, missing backups, or product health.
- Snapshot repository facts are labeled with generatedAt and as a saved snapshot. No overwrite of repos.json. No subtraction of differing history scopes. No dirty-file or commit counts are invented, since the current in-process scanner does not compute them.
- needsAttention is derived only from active todo notes and unresolved review flags. Differing branch tips remain a neutral informational fact and never affect attention counts or sorting. Old notes alone do not make every resting project need attention. Sort attention projects first, then name, then stable ID. Search matches project name, displayed status, next step and linked note titles.

## 3. Build steps

- [x] **G1 — Project report and discovery (`build`)**
  - Files: `Sources/UnliRiceCore/ProjectGarden.swift`, `Tests/UnliRiceCoreTests/ProjectGardenTests.swift` only.
  - Implement §2's loader and report without changing existing persisted types or scanner semantics.
  - Tests with temporary folders: direct root and parent/nested discovery; no-Git project; overlap deduplication; same basename without incorrect note or snapshot joins; symlink/dependency/ignore-marker skip; missing/unreadable/oversized memory; multiline Status/Next step; readable blank next step suppressing snapshot fallback; notes-only registration and archived exclusion; latest append block does not resurrect an old step; explicit provenance over tags with component boundaries; todo/review derivation; no remote refs => unknown; live vs historical repository provenance; duplicate snapshot names do not crash; bounded discovery and deterministic ordering.
  - Verify: `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build --filter ProjectGardenTests`.

- [x] **G1R — Complete report edge cases (`build`, depends initial G1)**
  - Files: `Sources/UnliRiceCore/ProjectGarden.swift`, `Tests/UnliRiceCoreTests/ProjectGardenTests.swift` only. The initial G1 focused suite passes 6/6 independently, but planner inspection found omissions from §2. Complete these existing requirements before accepting G1.
  - Notes-only projects must include related active todo/review notes with the exact project-name tag when there are no ambiguous folder matches; registrations alone are insufficient. Snapshot-only projects also associate active name-tagged notes when that name is unambiguous. A notes-only Project registration and a unique same-name snapshot represent one display card: attach the historical repository facts to it, preserve the registration's next step (including its absence). Do not create a second snapshot card. If folder-name matches are ambiguous, don't use tags or snapshots to choose a folder. Ignore all duplicate snapshot-name records for joining and issue one warning; never select an arbitrary first record as truth.
  - For folder note association, authoritative projectPath wins over sourceFilePath, which wins over tags. If the chosen provenance path matches several discovered folders (e.g. separately granted parent and child), associate only with the longest matching folder path by path components. Explicit provenance that matches no discovered project never falls back to a conflicting tag. Otherwise match registration title or exact project-name tag only for a unique folder name. One-character registration names (`Project:X` or `Project: X`) are valid.
  - Select status source deterministically: matching Project registration first, then newest related note with ID tie-break, whether memory.md was missing or readable but had no status. Limit every note excerpt to 400 chars, including missing-memory and notes-only paths. Source captions explicitly distinguish imported notes (`creator == ingest`) from other notes. Only an explicit registration Next step may supply a folder's note-derived step; a random task note must not be promoted to the project's next declared step.
  - Snapshot next-step fallback is independent of whether live repository facts exist. A missing/unreadable memory permits a unique matching snapshot step, labeled with the snapshot generation date; a successfully read memory with an empty/absent Next step suppresses it. Repository facts from a snapshot also always retain its date; don't overwrite a live repository. Remove the second memory read in the snapshot pass by retaining the first read outcome internally.
  - Discovery failures (nonexistent/unreadable roots or enumeration errors) must add report issues; do not silently collapse them to an empty complete report. Skip backup/archive directories explicitly, in addition to existing dependency exclusions. Maintain limits, symlink/ignore-marker boundaries, determinism, and direct-root support. Detect an unreadable/invalid Git HEAD result as unavailable rather than a known zero-branch repository, without changing GitRepoScanner. An unborn repository with readable `ref: refs/heads/main` remains valid. Close FileHandle with defer even if reading throws.
  - Add behavioral tests for these cases, plus all originally requested but missing tests: multi-line status/next step and truncation; missing/unreadable/oversized/symlink memory; direct vs parent/nested no-Git discovery; duplicate basename identities; overlapping parent/child provenance; symlink/dependency/archive and root-ignore boundaries; depth/project/directory caps and reported truncation; empty live remotes vs known differing tips, with no attention caused by Git alone; snapshot-only and live repository dates; latest append clearing an old notes-only step; archived exclusion; deterministic source and sorting. Tests must establish the actual behavior, not assert helper implementation details. Use temporary fixtures; test invalid/unreadable memory with a directory or invalid UTF-8 so the test doesn't depend on process privileges. No real repository or vault writes.
  - Verify: `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build --filter ProjectGardenTests`.

- [x] **G1P — Resolve source ownership and verify boundaries (`planner`, depends G1R)**
  - Planner review of the second diff found an unresolved ownership case: a related note may itself register a different project, and a notes-only tag may conflict with explicit provenance. Resolve primary status/next-step selection to a registration whose name matches this project, and permit name tags for notes-only projects only when the note has no explicit path provenance. Deduplicate related notes by UUID when combining providers so counts and SwiftUI identity remain correct.
  - Keep snapshot fallback source dates in the caption itself, independently of live Git observation time. Validate detached HEAD as an actual hexadecimal object ID rather than any nonempty text. These decisions preserve the original evidence/unknown contracts.
  - Files: the same two G1/G1R files. Add missing regression coverage for these ownership decisions and the originally required filesystem/memory/Git limits. Independently run the focused suite before accepting G1 and starting G2. This planner-owned correction resolves the ambiguous source ownership exposed by review; it does not expand the feature.

- [x] **G2 — Native Garden and navigation (`build`, depends G1)**
  - Files: `Sources/UnliRice/ProjectGardenView.swift`, `Sources/UnliRice/AppStore.swift`, `Sources/UnliRice/ContentView.swift`, `Sources/UnliRice/HomeView.swift` only.
  - Add transient `showingGarden`, `showGarden()`, sidebar Garden directly below Home, mainColumn route, exclude Garden from Notes active state. Clear Garden in closeAllPanes, resetCorpusScopedState, and selectNote(non-nil) so note links and other destinations work. Preserve onboarding and existing launch destination.
  - Home gets a compact Garden entry leading to showGarden. Use existing Theme and native SwiftUI cards, with a leaf/sprout accent and readable source captions; no giant illustration or background animation. At 960px app minimum width the adaptive grid fits the available main column and does not clip. Support both appearance modes.
  - View reads all active notes using NoteService; optional snapshot read and loader run off main thread while the existing root and corpus security scopes are open. Refresh on appearance, explicit Refresh, root changes, corpus changes, and updated note state. Track load identity / cancellation so an older task cannot overwrite newer input or leak a previous corpus report. Keep previous successful report visible with an error if a refresh fails; show progress and honest partial-coverage issues. Missing optional snapshot alone is normal and must not block projects discovered from notes/folders.
  - Show project cards, summary, search, All/Needs attention filter, empty/no-match/error states, and a project detail sheet. Show a folder's location to disambiguate names. Details list related notes with dates and source type; opening a note dismisses the sheet, clears Garden and opens the existing detail view. Folder reveal can use NSWorkspace for an already discovered/granted folder only. No mutation actions. Header links to To do and Repos may use existing navigation methods. Manage project folders uses showGardenFolders(): closeAllPanes(), showingMore = true, moreDestination = .automation; it lands on the existing Add Folder control, not the unrelated notes-folder picker. Explain this folder source in the empty state. Do not silently invoke ingestion or alter grants.
  - Verify: `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-build --product UnliRiceApp`; `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build`.

- [x] **G2P — Finalize loading and detail contracts (`planner`, depends G2)**
  - The G2 diff exposes architectural display/loading issues: an optional malformed snapshot must not prevent local/notes discovery, a cancelled old load must not clear a newer load's progress, and note/next-step dates cannot share one timestamp when the providers differ. The planner owns these cross-layer decisions.
  - Keep the public core API: include the correct next-step date in its source caption and do not append the unrelated status date in the UI. Use a value-based load key and per-request identity plus cancellation forwarding. Preserve current-corpus data on a refresh error; discard previous-corpus data. Add partial snapshot failures as coverage issues while rendering available providers.
  - Show folder locations and project-specific issues on cards/details, unknown initial counts, clear note/source captions, and an explicit dismissible/scrollable detail sheet. Include current branch and correctly describe linked worktrees. The planner verifies these adjustments against the preview rather than accepting builder claims alone.
  - Files: `Sources/UnliRice/ProjectGardenView.swift`, `Sources/UnliRiceCore/ProjectGarden.swift`, `Tests/UnliRiceCoreTests/ProjectGardenTests.swift` plus planner documentation. No persisted schema or new feature scope.

- [ ] **G3 — Integration verification and records (`planner`, depends G2)**
  - Review every builder diff and independently rerun checks. Run xcodegen generate because Sources files were added, and verify the generated Mac target builds without signing (external /tmp DerivedData). Review iOS Core portability if a new Foundation API is platform-specific.
  - Exercise Garden with a throwaway vault and temporary project fixtures: populated cards, notes-only, empty state, search/filter, Refresh, sources, detail-to-note navigation, navigation back to other panes, and at 960px width in light/dark. Do not test by changing the user's real vault or launching the development build against the App Store container. Record precisely which checks ran and any UI limits.
  - Claude post-mortem in docs/dialogue/project-garden.md, answer findings, fix confirmed issues. Planner appends verified session history in PROJECT_NOTES.md, atomically updates memory.md's six fields, adds brief README/guide coverage if warranted, and commits checkpoints. No push, merge into main, App Store upload or version bump is part of this task.

## 4. Builder context

Each builder receives the mandatory AGENTS.md Role/Plan/Step/Branch/Files/Changes/Verify handoff. Only one step at a time, clean checkpoint before each step. Builders may not edit documentation, git state or other files. They stop on an architectural choice, missing required file, branch mismatch, unexpected modifications, or the contract's circuit breaker. New Sources files must be called out for xcodegen.

The planner owns unresolved design choices and review. Test output in a builder report is not accepted without independent verification. Current app-group restrictions mean UI QA must use a throwaway log, not the App Store vault. Live MCP note tools are unavailable in this session and reading the app-group vault was denied in discovery; do not claim Wiki: index or project to-dos were checked. No note writes are authorized by this feature implementation.

## Build verification so far

2026-10-19: G1's six tests were independently rerun. G1R's report was reviewed; the planner-owned G1P resolved remaining primary-registration ownership, duplicate note identities across providers, dated next-step fallback, invalid detached HEAD and depth-coverage reporting. The completed focused suite was independently executed: `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build --filter ProjectGardenTests`, 22 tests, zero failures. G2 has not started at this checkpoint.

2026-10-19: G2 built through gpt-reserve / medium (startup verified); planner-owned G2P finalized request identity/cancellation, partial snapshot failures, source-specific next-step dates, source issues, card locations, and scrollable/dismissible details. Independent verification after the interruption: SwiftPM UnliRiceApp build succeeded; full `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-build` executed 406 tests, 2 skipped, zero failures. `xcodegen generate` succeeded and the generated Mac target built with `xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -destination 'platform=macOS' -configuration Debug -derivedDataPath /tmp/unlirice-garden-mac-derived CODE_SIGNING_ALLOWED=NO build` outside the command sandbox. A prior sandboxed attempt failed to start SwiftUI macro processes; the host retry succeeded. The shared Core iOS simulator target also built before interruption (command output observed then; temporary logs were later cleared).

The sample-data app at `dist/Unli Rice Garden Preview.app` has an isolated bundle ID, vault and agent settings. It was launched and LaunchServices reported it as the foreground app. Automated native UI inspection hung and was interrupted, then its tool was unavailable; search/filter/detail-click/minimum-width/light-dark interaction checks remain unverified and are not claimed as passed. The founder is viewing this preview. No App Store copy was replaced and no real vault was used for testing.

2026-10-19: Claude returned the approved post-mortem with no blockers. Its CLI file-write request did not complete, so Codex transcribed the returned review into the dialogue with explicit attribution. The planner accepted the initial-loading and empty-notes-copy suggestions, deferred association-aware scan invalidation pending performance evidence, and closed the dialogue. SwiftPM rebuilt successfully after those two UI polish edits. G3's remaining unchecked work is automated interactive/appearance QA, which is unavailable in this session; this is not release approval. The implementation and source review are complete and the sample preview is available to the founder.
