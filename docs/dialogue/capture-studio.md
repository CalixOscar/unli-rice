# Dialogue — capture-studio

**Plan:** docs/PLAN-capture-studio.md
**Planner:** codex
**Reviewer:** claude
**State:** closed

## claude — post-mortem — 2026-11-01

Read-only review of the uncommitted working tree on `CalixOscar/Unli-rice-Capture`,
baseline `6e25c9a`, including the 18 untracked files. No pre-mortem turn exists: the
founder waived it on 2026-11-01 ("Proceed skip pre mortem and implement"), and this
record deliberately does not invent one.

**Verification I could not perform.** `swift test`, `swift build`, `xcodegen` and both
`xcodebuild` invocations were not runnable in this review session. Every finding below
is from source reading with `file:line` evidence, not from a failing run. The
builder-reported core test pass and the planner's independent Xcode/Simulator
verification remain the only compile/test evidence; nothing here confirms or
contradicts them. QA1 is unverified by me.

### High — introduced — new captures lowercase the project tag, breaking legacy tab association

`Sources/UnliRiceCapture/CaptureStore.swift:695-697` now writes the project tag as
`projectTag.lowercased()`, special-casing only `Unli Thoughts`, where the previous code
wrote `currentProjectTab` verbatim. That satisfies CP2's "exact project tag convention",
but the corpus now holds both cases for the same tab, which is why the builder also had
to patch both readers to compare case-insensitively (`CaptureStore.swift:143` and
`:442`). Two consequences the plan does not cover:

1. `CaptureContext.pendingNotes` / `unassignedNotes`
   (`Sources/UnliRiceCore/CaptureContext.swift:36,46`) normalize the *note's* tags before
   comparing, so core capture matching is case-insensitive and agrees — good. But to-do
   filtering uses the exact literal `"todo"` in three places:
   `CaptureProjectView.swift:41`, `CaptureStudioView.swift:122` and
   `ProjectContext.swift:63`. A legacy note tagged `Todo` or `TODO` is invisible to all
   three. The convention is pre-existing, but the new Studio surfaces make it
   user-visible on the phone for the first time.
2. A tab named `Nuptia` now produces tag `nuptia` on new captures while the tab list
   (`CaptureStore.swift:167-175`, `:200-205`) still stores display case, and
   `CaptureView.swift:62-65` appends `project.name` in display case as a new tab when
   recording from a Studio sleeve. The tab list therefore accumulates display-case
   entries whose captures carry lowercase tags. Self-consistent only because every
   reader was patched; this deserves one explicit contract line rather than three
   independent case-insensitive comparisons that a later edit can silently drop.

### Medium — introduced — a single bad local `.jsonl` now aborts the entire sync chain

`Sources/UnliRice/AppStore.swift:735-738` and `:753-756` replaced
`try? ShardImporter.importShards(...)` with throwing `CaptureSyncBridge.importOnly`
calls. `importOnly` adds strict pre-validation (`CaptureSyncBridge.swift:29-41`,
`:46-49`) that throws `corruptShard` if *any* non-own `.jsonl` in the folder fails to
decode as an `Event`, and `corruptState` if `sync-state.json` is unreadable. The first
call passes `requiringShardNaming: false` (`:737`) for the local `shards/` directory, so
the filter at `CaptureSyncBridge.swift:33` keeps every `.jsonl` regardless of the
`events-` prefix. One unrelated or half-written `.jsonl` in `shards/` now throws out of
the whole `do` block, so the phone-folder imports (`:748-758`), the own-shard publish
(`:775-790`) and the export-folder `synchronize` (`:793-799`) are all skipped; the user
sees only `statusMessage` (`:802`). Previously a bad local shard was silently skipped and
the rest of sync proceeded. The refuse-over-corruption instinct is right and matches the
amendment's "never reset import cursors", but it should be scoped per-folder so one
unreadable file cannot stop publication and receipt writing. Cursors are preserved, so
this is availability, not data loss.

### Medium — introduced — `withLock` is not reentrant and the invariant is undocumented

`CaptureSyncBridge.withLock` (`CaptureSyncBridge.swift:20-28`) takes `flock(LOCK_EX)` on
a per-corpus `.capture-sync.lock`. `flock` is per-open-file-descriptor and each call
`open`s a fresh descriptor, so a nested `withLock` on the same corpus in the same process
**self-deadlocks**. Both public entry points take it (`importOnly` `:44`, `synchronize`
`:55`), and `AppStore.runShardImportIfNeeded` also takes it directly at
`AppStore.swift:775`. Today the three are sequential, not nested, so nothing deadlocks.
The hazard is that the invariant is unenforced and uncommented:
`AppStore+Studio.swift:22` now calls `runShardImportIfNeeded()` from
`refreshStudioGarden`, and the MCP host calls `synchronize` at
`Sources/unlirice-mcp/main.swift:73,119,122`. A future caller that wraps a bridge call in
its own `withLock` gets a hang with no diagnostic. Worth a "never nest" comment plus,
ideally, `LOCK_EX | LOCK_NB` with a bounded retry so the failure mode is
`lockUnavailable` rather than an unkillable spinner.

### Medium — introduced — `project_context` can be empty on a Mac whose Studio tab was never opened

`Sources/unlirice-mcp/main.swift:36` constructs the dispatcher with
`overviewFolder: dataURL.deletingLastPathComponent()`, and
`ToolDispatcher.swift:48-50` reads `StudioOverviewFile.read(fromFolder:)` from there. The
only writer of that local copy is `refreshStudioGarden` (`AppStore+Studio.swift:88`),
which runs when the founder opens the Mac Studio tab. This matches the settled contract
("Also keeps a local copy beside its real event log for MCP") and the plan's "Use the
local overview if readable, report its absence otherwise", and absence *is* reported
(`ProjectContext.swift:50`, `ToolDispatcher.swift:49`). Two acceptance gaps remain:

- On a Mac where the founder has never opened the Studio tab, `project_context` returns
  zero projects with issue "No studio overview has been published yet.", while
  `synchronize` has nonetheless imported phone captures. Pending captures still surface
  (they come from the event log, `ProjectContext.swift:60`), but every project
  status/next-step/branch field is empty. Plan §5's "All-repo update includes project
  captures" journey therefore depends on a GUI visit nobody is prompted to make.
- `overviewStale` is computed (`ProjectContext.swift:93`) with a 6-hour tolerance
  (`StudioOverviewFile.swift:74`) but the `initialize` instructions string
  (`main.swift:100`) never mentions staleness, so a model reading only the connector
  instructions gets a pending-capture count with no freshness caveat. SY2's "Missing data
  cannot appear as zero or success" is met in the tool payload and not in the
  initialization text.

### Medium — introduced — the Claude hook silently changed project identification for to-dos too

`Scripts/unlirice-prompt-hook.py:128-166` replaced "the folder directly under
`~/Documents/Projects`" with "walk up to the enclosing git checkout name, falling back to
Projects". For this worktree that is correct and better: `.git` is a file pointing at
`…/Documents/Projects/Unli Rice/.git/worktrees/51327-…`, the `commondir` hop at
`:150-155` resolves to the main checkout, and `:158` yields `Unli Rice` rather than the
worktree directory name `Unli-rice-Capture`. Verified by reading `.git` in this checkout.
It parses `.git` by hand and never shells out, so the "existing Mac apps can't run git"
constraint is honored — worth recording because it is the non-obvious reason the
implementation looks the way it does. Two concerns:

- B4's authorized scope is "hook support" for captures; silently broadening project
  identification for **to-dos as well** is a behavior change outside the stated step.
  `open_todos_for_project` now receives a different project name for any session run
  inside a git checkout that is not directly under `~/Documents/Projects`, so the hook
  will start surfacing to-dos where it previously surfaced none, and AI3's "Other
  projects' captures are not attributed to the current repo" now hinges on checkout
  naming rather than folder naming.
- Needs a planner ruling on whether that was intended.

### Low — introduced — two different notions of "hidden" between validator and importer

`CaptureSyncBridge.swift:33` drops dotfiles via `!hasPrefix(".")` while `ShardImporter`
uses `.skipsHiddenFiles` (`ShardImporter.swift:48`). A file named `.events-x.jsonl` is
skipped by both, so there is no divergence today; a resource-fork or `._`-prefixed
sidecar on a FAT/SMB share is skipped by the validator's dot check but by
`skipsHiddenFiles` only if the filesystem marks it hidden. Low risk, but the two filters
should be one shared helper so they cannot drift.

### Low — introduced — receipt semantics are weaker than the UI copy implies

`CaptureSyncBridge.swift:96-98` and `AppStore+Studio.swift:69-71` write the receipt from
`listNotes(includeArchived: true).filter(CaptureContext.isCapture)`, newest 2000 by
`updatedAt`. `CaptureProjectView.swift:109` renders "Mac receipt confirmed" /
"Mac receipt not confirmed" from membership. This correctly implements the contract's
"acknowledges note existence, not every later edit". Two edges: a capture the Mac has
received but that falls outside the newest-2000 window flips back to "not confirmed" with
no explanation, and `isCapture` requires the `capture` tag, so a legacy phone note
imported before "Track this capture" is applied never appears in a receipt even though
the Mac holds it. Both are honest-but-confusing rather than wrong; CP1's "Legacy phone
notes stay readable" holds.

### Low — introduced — `id` and `projectTag` are always equal but semantically distinct

`StudioOverviewFile.Project` is `Identifiable` on `id` (`StudioOverviewFile.swift:15`)
while every behavior keys on `projectTag`. `StudioOverviewPublisher.make` sets both to
`key(project.name)` (`StudioOverviewPublisher.swift:35`), and `Project.init` normalizes
`projectTag` but stores `id` verbatim (`:27-41`). The picker/write round trip is correct
as written — `projectID` is only a selection handle, `selectedProject` resolves it back to
the same object (`CaptureProjectView.swift:98`), the write takes `projectTag` off that
object (`:122`), and `onAppear` maps back via `matching[0].id` (`:139`), so `id` is never
compared against a tag and the two diverging would change nothing. Uniqueness is enforced
by `StudioOverviewFile.init` dropping duplicate tags (`:55-58`). Flagged only because two
fields that are always equal today invite a future reader to treat them as
interchangeable. No defect; no change required.

### Low — pre-existing — `ShardPublisher` rebuild-on-shrink is guarded, not fixed

`CaptureSyncBridge.swift:82-84` pre-reads the export cursor so a shrunk local log throws
`shardShrunk` *before* `ShardPublisher.publishLocalEvents` can hit its own
`catch ShardFeedError.shardShrunk` branch (`ShardPublisher.swift:31-41`), which would
delete the destination shard and republish from zero. That is the right call and directly
serves the amendment's "no destructive cursor rewind is introduced by this feature". The
destructive branch is still reachable from the other publish call at
`AppStore.swift:780-789`, which has no such guard — pre-existing behavior for the local
`shards/` directory, unchanged by this work, and out of scope here.

### Scope check

Within the plan's allowed paths. `Sources/unlirice-mcp/ToolDispatcher.swift:23-24` adds
`overviewFolder`/`syncIssue` as `var`s on a struct, which forced `dispatcher` to become
`var` (`main.swift:36`) — acceptable, but it makes a previously immutable audit surface
mutable. The dispatch surface itself stays read-only for `project_context`
(`MCPToolCatalog.swift:31-32` classifies it `isWrite == false`, and
`MCPToolCatalogTests.swift` was updated alongside), satisfying the amendment's "Dispatch's
context projection remains read-only". No `EventKind` was added, confirming the stated
constraint. No release/version/entitlement changes appear in the diff. `docs/`,
`memory.md` and `PROJECT_NOTES.md` were untouched by builders as required.

### Two-way sync of AI actions on phone captures

Traced and it does close, with one caveat. A Codex/Claude `archive_note` or `tag_note` on
an imported phone capture is written to the Mac log by `ToolDispatcher`, then
`main.swift:122` re-runs `synchronizeCaptures()` after any successful write tool, which
publishes the Mac's local events into the export folder via
`CaptureSyncBridge.synchronize` (`:92-94`) under the per-destination
`sync-export-<sha256>.json` cursor — the separate namespace the amendment demanded,
distinct from the `sharedFolder.path`-namespaced *import* cursors in `sync-state.json`
(`:86-87`). The phone then imports them in `CaptureStore.sync()`
(`CaptureStore.swift:379-385`). `CaptureSyncBridgeTests.swift:25-39` exercises exactly
this round trip and asserts the phone sees `todo` added and `capture-pending` removed.

Caveat: the phone's import uses `ShardImporter.importShards` with **no**
`cursorNamespace` (`CaptureStore.swift:379-384`), so its cursors stay filename-keyed.
That is existing phone behavior and is correct as long as the phone only ever syncs one
folder, but if the founder repoints the phone's shared folder to a different directory
containing a same-named `events-mac-<id>.jsonl`, the stale byte offset applies to the new
file. `setSharedFolder` resets `publishedCursor` (`CaptureStore.swift:359-363`) but not
`shardCursors`, so this is a real if narrow pre-existing hole that the new bidirectional
traffic makes easier to hit.

### Acceptance gaps for planner resolution

1. Scope the `importOnly` throw per-folder so a single bad local `.jsonl` cannot skip
   publication and receipt writing (Medium).
2. Document or enforce `withLock` non-reentrancy; prefer `LOCK_NB` + bounded retry so the
   failure mode is an error rather than a hang (Medium).
3. Either prompt/trigger a Studio refresh so the MCP local overview exists, or have
   `initialize` state that the overview is missing/stale rather than only the tool
   payload (Medium).
4. Confirm whether the hook's git-checkout project rule was intended to change **to-do**
   attribution too; if not, restrict it to captures (Medium).
5. Add one contract line fixing project-tag case at write time, so the three
   case-insensitive reader comparisons are not the only thing holding association
   together, and decide whether `"todo"` literal matching should normalize (High).
6. UI1/UI2/UI3/UI4 and GT1/GT2 are visual/accessibility criteria I cannot discharge by
   reading: light/dark parity against the Mac, deck stacking at compact width, VoiceOver,
   largest Dynamic Type, Reduce Motion/Transparency, app-lock snapshot coverage and
   recording-interruption behavior all still need the Simulator pass.
   `CapturePrivacyCover` is applied to every new sheet (`CaptureStudioStyle.swift:45-65`,
   applied at `CaptureView.swift:191`, `CaptureStudioView.swift:42,45`,
   `CaptureProjectView.swift:73,75,140`) and uses `accessibilityHidden` plus an opaque
   overlay, which is the right shape for UI4 — but whether it covers the app-switcher
   snapshot depends on existing `AppLock` behavior, not on this modifier.
7. UI2's persistent recording control looks met via `recordSection` being re-rendered on
   the Studio and To-do pages when `store.captureInFlight` (`CaptureView.swift:76-78`,
   `:92`), with the record button disabled while in flight
   (`CaptureStudioView.swift:79`). Confirm on device that navigating between the three
   segmented pages mid-recording does not instantiate a second recorder.

## codex — response — 2026-11-01

The review was returned through the Claude connector (resolved model reported
`claude-opus-5`). Its write permission was denied, so Codex recorded the returned
verbatim Markdown in this authorized checkout; Claude's text above is unchanged.

- **Project ID/tag High:** withdrawn by Claude in the returned corrected review.
  A picker ID resolves a Project object; writes use that object's projectTag.
- **Project-tag case High: declined as a defect.** Lowercase writes are the
  explicit convention in plan §3/CP2. Legacy *project* tags are matched after
  normalization. `todo` is a reserved exact lowercase tag in AGENTS.md; `Todo`
  and `TODO` are not reinterpreted as tasks. No legacy association is lost by
  these readers. The contract explicitly preserves this distinction.
- **Per-folder failures: accepted and fixed.** Local-shard, scan-root, local
  publication and shared-bridge errors are isolated; successful imports still
  rebuild the view. Each failure remains visible without exposing local paths.
- **Lock wait: accepted and fixed.** The non-reentrant bridge lock now retries
  nonblocking acquisition for at most two seconds and returns a retryable error.
  Tests cover nesting timeout, release and concurrent import namespaces.
- **Absent/stale overview: accepted.** MCP initialization now says whether the
  overview is unavailable, old or a saved snapshot. The tool repeats age/unknown
  evidence on every request. Publishing a full project picture still requires
  the Mac Studio to refresh; the connector imports captures without that visit.
- **Hook project scope: intentional and accepted.** Both to-dos and captures now
  use the same canonical project name, including Orca linked worktrees. Tests
  cover ordinary repos, commondir resolution and malformed markers.
- **Hidden files: accepted and fixed.** Validation uses `.skipsHiddenFiles`, like
  the importer.
- **Phone folder change: accepted and fixed.** A versioned one-time migration
  adopts legacy import offsets for the old current folder; future folders use
  their own namespaces. Migration refuses corrupt/future state and never
  rewinds an import. Clearing/private-mode choices preserve this migration and
  still honor disconnection. Existing phone publication reset is unchanged.
- **Receipt window: retained deliberately.** Confirmation is note-existence
  evidence for the newest 2,000 tracked captures, not proof of every edit or AI
  review. Missing confirmation remains unknown. Legacy notes require explicit
  tracking. The spec does not promise a permanent delivery audit.
- **Existing local rebuild-on-shrink: unchanged.** The new shared export refuses
  shrink before publishing. No new destructive event-log operation was added.
- **Test isolation safeguard added:** an environment-overridden MCP corpus never
  resolves the real shared sync folder. Protocol fixtures cannot export test
  notes into the user's real folder.

Independent verification: 563 core tests, 0 failures, 2 skips (`swift test`,
2026-11-01); both Xcode targets build; 12-request JSON-RPC fixture passes.
A temporary XCUITest harness found a real missing sleeve hit area. Adding the
full contentShape and excluding decorative sleeves from hit testing fixed it.
Separate passing UI runs verify conversion retains the transcript and persists
on relaunch, project details open, and saved-remote evidence is labeled honestly.
Light/dark screenshots are in `Screenshots/Capture-Studio-QA-2026-11-01/`.

Physical-device voice/iCloud, biometric app-switcher coverage, iPad and the full
accessibility matrix remain unverified and must pass before release. No upload,
version bump, entitlements or installed production store was changed.
