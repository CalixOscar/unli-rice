# PLAN — Capture Studio

**Intent:** docs/intent/INTENT-010-capture-studio.md
**Spec:** docs/SPEC-capture-studio.md
**Planner:** codex
**Reviewer:** claude
**Stage:** 6 — built and post-mortemed; physical-device release acceptance remains
**Branch:** CalixOscar/Unli-rice-Capture (existing non-main checkout)
**Baseline:** 6e25c9a; working tree clean before these three planning documents
**Pre-mortem:** skipped — founder 2026-11-01: “Proceed skip pre mortem and implement”
**Founder skips:** pre-mortem only; verification and post-mortem remain required

## 1. Verified starting point

- CaptureStore.saveCapturedText writes transcript events and a project-tab tag;
  sync publishes phone-originated events. Several sync errors currently use try?.
- AppStore.runShardImportIfNeeded imports shared-folder shards at launch and app
  activation. The MCP server itself does not import those shards.
- MCP initialize offers search guidance; it supplies no pending-capture summary.
  Scripts/unlirice-prompt-hook.py currently selects project-tagged todo notes only.
- Mac StudioView uses Projects, Branches and Notes decks; StudioPalette is shared
  pure core code. Its GardenCrateView uses AppKit and cannot simply compile on iOS.
- ProjectGarden.Report is currently an in-memory projection of folders and notes,
  not a mobile interchange format. The new report needs an explicit export boundary.
- ReposSnapshotView already reads repos.json on the phone. RepoPaneView explicitly
  says check-repos.sh is its producer; do not replace that file with a poorer scan.
- ProjectGardenView distinguishes “This Mac”, “Recorded remote” and “Remote live:
  Not checked.” GitRepoScanner.tipOnRemote compares commit IDs with fetched refs.
  This is not a live GitHub comparison and not upstream ahead/behind counts.

Evidence above comes from current source, not the old capture battleplan or ingest notes.
Toolchain checked 2026-11-01: Xcode 27.2, Swift 6.4.2, xcodegen on PATH.

## 2. Chosen direction for review

### Shared state and association

Keep the event log authoritative. Use existing tagging/untagging events for capture
origin and pending state; exact tag strings will be reserved in the reviewed
contract before B1. Do not add EventKind or change Note shape. Historical phone
notes are not silently rewritten; expose an explicit “Track this capture” action.

The project picker uses known overview projects and their lowercased folder-name
tags, matching the existing todo convention. Preserve an Unassigned choice.
Unknown existing project tabs stay visible until explicitly assigned. Duplicate
project names must not silently merge; association is unknown until resolved.

Add to to-dos tags the existing capture as todo plus its explicit project tag;
it does not create a second note. Pending-capture status ends only after a
successful explicit transition. Retries complete missing tag events. A todo is
actionable work; a pending capture is an idea awaiting a decision. Never archive
the note as a side effect of merely requesting AI help.

### Overview transport

Introduce a separate studio-overview.json, version 1, rather than changing the
existing repos.json producer. It contains producer identity, generatedAt, bounded
project entries and report issues. Each entry carries a path-free project key,
name, project tag, status/next-step with observation/source metadata, repository
summary and optional seven-stage evidence from the existing Mac selectors.
No generated local filesystem path metadata, remote credentials or full project document bodies
are exported. Notes/captures/todos remain sourced from the event log, not duplicated
as authoritative snapshot state. The phone joins them to the overview by project tag.

Publication belongs to the Mac's successful Studio refresh and configured sync
folder, using existing folder grants. Publish once per completed report, atomically;
retain the last valid snapshot on failure and expose the failure. Do not claim a
background publisher or live phone-to-Mac refresh. An offline phone shows the last
snapshot with age. An older phone continues using repos.json.

### AI context

Add one read-only MCP tool for project/all-project context using a shared core
projection, returning bounded capture IDs/titles/previews plus project evidence.
Initialization provides a bounded pending-capture pointer and explicit retrieval
guidance. Never insert transcript text into system instructions. The Claude hook
must agree with the same capture-state and project matching fixtures. New sessions
check project captures; existing sessions can call the tool again. No transport
guarantees that an LLM obeys the reminder, and no unsolicited background push is promised.

Keep source content separate from instructions, and make missing/old overview data
explicit. Both tools can read notes and act only on the founder's request.

### iOS design

Studio is the overview; Capture is a prominent one-tap destination/action. Projects
use the Mac's sleeve colors and status stickers. Project detail has Status & next
step, Captures, To-dos and Branches. Unassigned captures are reachable from Notes.
Compact phones stack decks; regular widths place suitable decks side by side.
Keep the existing recorder implementation and a persistent recording control across
navigation; reuse its one shared store, playback, lock and interruption behavior.

Use StudioPalette, solid rounded deck surfaces and system type. Reuse the Mac's
hierarchy rather than copying its fixed desktop sizes. Controls have 44-point
minimum touch targets. Every swipe has a button alternative. Reduce Motion removes
3D flips; Reduce Transparency uses solid controls. Branch comparison uses plain
labels “On this Mac”, “Recorded remote” and “Live remote not checked.”

## 3. Settled contracts (planner, 2026-11-01)

- Reserved tags: `capture` identifies a capture, `capture-pending` means awaiting a
  decision, `capture-deferred` means explicitly set aside. Removing deferred and
  restoring pending reverses that action. Reading/sharing never changes these tags.
- Project keys/tags are trimmed, lowercased folder names. The overview omits
  duplicate normalized names and reports an issue; no inferred assignment.
  `Unli Thoughts` is unassigned. Existing custom tabs match only a known project.
- New captures get origin/pending tags in the original event batch. Legacy notes
  can be explicitly tracked without changing their title or transcript.
- Add to to-dos adds the explicit project tag and `todo` on the same note, then
  removes pending/deferred only after those writes succeed. Idempotent retries.
- Core CaptureContext owns matching/state/action and bounded handoff formatting.
  Context is a projection over notes, joined to StudioOverviewFile projects.
- StudioOverviewFile version 1: generatedAt, deviceLabel, projects, issues. Each
  Codable project has id/name/projectTag, optional status/statusDate/nextStep,
  observedAt, optional RepoSnapshotFile.Repo, stage evidence and issues.
  The id is the normalized unique project name, never a filesystem path.
  Stage evidence is a string-keyed dictionary of state plus optional reason.
  Limit reads to 2 MB, 500 projects; reject unknown versions. Clip status/nextStep
  to 2000 characters. Preserve upstream branch-evidence semantics.
- Mac publishes into exportFolderURL only (the explicitly chosen shared export
  folder). Also keeps a local copy beside its real event log for MCP. Do not
  guess that all scan roots are sync destinations or overwrite repos.json.
- CaptureReceiptFile version 1: generatedAt, deviceLabel and receivedNoteIDs.
  Mac writes `capture-receipt-<device-id>.json` atomically into shared export
  folder after reading its corpus. Up to 2000 newest capture IDs. Phone may
  claim receipt of that note only when its ID is present; absence is unknown.
  This acknowledges note existence, not every later edit or AI review.
- A failed shared publication exposes retryable sync status. Publication does not
  prove Mac receipt. No destructive cursor rewind is introduced by this feature.
- MCP read-only tool `project_context`, optional `project` argument, omitted for
  all projects. Use the local overview if readable, report its absence otherwise.
  Max 20 projects/request and 10 capture/todo previews/project, 300-char preview;
  counts remain total and truncation is explicit. IDs retrieve full text.
  Initialization contains counts and retrieval guidance, never transcript text.
- Hook uses exact normalized project tag and capture/pending/archived rules;
  max 10 ID/title pointers. Instructions treat title/transcript as quoted data.
  Project context before unrelated implementation is guidance, not autonomous action.

## 4. Ordered implementation steps

Each step gets a complete Role: builder brief. Intent is approved, contracts above
are settled, and the founder waived the pre-mortem for this feature.
Builders are Terra at medium effort, with their reported model verified. No step
may edit docs, memory.md, PROJECT_NOTES.md or agent instructions.

- [x] P0 — planner: intent approved, DTO/state contracts settled above; founder waived pre-mortem.
- [x] B1 — build: shared capture state, project association and context projection.
  Allowed: new Sources/UnliRiceCore/CaptureContext.swift and
  Tests/UnliRiceCoreTests/CaptureContextTests.swift; ShardWriter.swift and
  CaptureStore.swift only for the reviewed capture-origin writes.
  Accept CP1–CP4 and AI1/AI4 pure contracts. Verify focused CaptureContext tests.
- [x] B2 — build: overview DTO plus compatibility and repository-evidence tests.
  Allowed: new Sources/UnliRiceCore/Sync/StudioOverviewFile.swift and its core tests.
  Accept SY1–SY2 and GT1–GT2 data semantics. Verify focused StudioOverview tests.
- [x] B3 — build: Mac publisher, sync feedback and reviewed receipt/retry mechanism.
  Allowed paths to be finalized after P0: AppStore+Studio.swift, AppStore.swift,
  CaptureStore.swift, relevant Sync types and focused tests. Never modify the
  repos.json producer. Accept SY1–SY3 and compatibility with old Capture clients.
  Verify sync/overview tests and both target builds.
- [x] B4 — build: MCP context tool and initialization, plus hook support.
  Allowed: Sources/unlirice-mcp/{main,ToolCatalog,ToolDispatcher}.swift,
  Sources/UnliRiceCore/MCP/MCPToolCatalog.swift, Scripts/unlirice-prompt-hook.py
  and focused tests. Accept AI1–AI4. Verify JSON-RPC transcripts, hook agreement,
  MCP classification tests and MCP build. Preserve trust-center tool accounting.
- [x] B5 — build: iOS Studio navigation, capture actions and visual family.
  Allowed: Sources/UnliRiceCapture/{CaptureView,Theme,ReposSnapshotView}.swift and
  new CaptureStudioView.swift, CaptureProjectView.swift, CaptureStudioStyle.swift.
  Accept UI1–UI4 and GT1–GT2. Preserve all existing settings/recording/lock paths.
  Regenerate Xcode project and build Capture for Simulator.
- [x] B6 — build: complete bidirectional shared-folder sync and connector refresh.
  Allowed: CaptureStore.swift, CaptureProjectView.swift, CaptureView.swift,
  TodoView.swift and core handoff formatter/tests. Accept CP2–CP5 and UI3.
  Verify idempotence/failure tests and Simulator build.
- [x] P7 — planner: review every worker diff, independently rerun appropriate
  checks, conduct journey/visual QA, obtain Claude post-mortem, update all seven
  memory.md fields at the implementation checkpoint. No release upload.

## 5. Verification and acceptance record

Commands below were run by the planner on 2026-11-01. See the verification record
below for results and the manual checks that remain unverified.

```sh
swift test --disable-sandbox --scratch-path /tmp/unlirice-capture-studio-tests
swift build --disable-sandbox --scratch-path /tmp/unlirice-capture-studio-tests --product unlirice-mcp
xcodegen generate
xcodebuild -project UnliRice.xcodeproj -scheme UnliRiceCapture -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/unlirice-capture-studio-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -configuration Debug -derivedDataPath /tmp/unlirice-capture-studio-mac CODE_SIGNING_ALLOWED=NO build
git diff --check
```

- [ ] New user without sync: record privately, no fake repo/status/receipt.
- [ ] Existing user: old captures/tabs/audio and old repos.json remain accessible.
- [ ] Walking journey: offline capture → reconnect → publish → Mac receipt → new
  Codex session on Nuptia → relevant reminder → choose act or todo → Claude sees state.
- [ ] All-repo update includes project captures and a separate Unassigned section.
- [ ] Already-open AI session requests fresh context without reconnecting.
- [ ] Matching/different/no-remote evidence, stale snapshot and unavailable Mac.
- [ ] Partial event write, denied folder, moved folder and retry without duplicate capture.
- [ ] iPhone narrow width and iPad, light/dark, VoiceOver, largest Dynamic Type,
  Reduce Motion, Reduce Transparency, recording interruption and app lock.

Built: yes, both targets. Verified with fixtures and Simulator: yes, as recorded below.
Verified on physical devices: no. Ready to release: no.

## 6. Deferred items

The existing Mac page-placement, multi-restore and old project-check to-dos found
in Unli Rice are outside this feature; none is silently folded in or closed.
Live GitHub fetch/auth, remote agent execution, automatic semantic project
classification and historical-corpus migration are outside this plan.

## Integration review amendment — 2026-11-01

Planner review found the old Mac publisher writes its own shard only beside its
local log; Capture reads the shared folder. B6 must connect that return path.
Use a shared core CaptureSyncBridge to import using the EXISTING sync-state.json
and folder.path cursor namespace (never reset import cursors), publish local Mac
events to export folder with a SEPARATE per-destination SHA256-keyed export cursor,
and write actual Mac receipt. The GUI calls it on import/refresh; the MCP host
calls it at connection initialization and before tool calls, then after successful
note-write tools so AI decisions reach the phone. Dispatch's context projection
remains read-only; connector synchronization imports existing device events.
Bridge errors go to stderr and into the context report, never a fake zero.
Use an interprocess bridge lock; no source rewriting or new event kind.
When there is no configured export folder the bridge does nothing.

Generated diagnostic paths are redacted from exported issues/stage reasons.
Founder-authored status/next-step text is deliberately preserved as content; it
may name a file. The path-free rule governs generated identity/filesystem metadata,
not rewriting the founder's words.

## Final implementation and verification record — 2026-11-01

Founder intent/spec approval and pre-mortem-only waiver remain as quoted above.
Implementation used three native Terra workers with explicit `gpt-6.1-terra`,
`medium` launch overrides. Planner reviewed tracked and new source, reran checks,
and obtained Claude's post-mortem; response in `docs/dialogue/capture-studio.md`.

Final file ownership expanded within reviewed steps: B1 adds CaptureContext;
B2 adds StudioOverviewFile/CaptureReceiptFile; B3 adds StudioOverviewPublisher and
Mac/CaptureStore integration; B4 adds ProjectContext, MCP catalog/dispatch/host
and hook; B5 adds the three iOS Studio files and updates CaptureView/Theme;
B6 adds CaptureSyncBridge, local SyncState cursor migration and host integration.
Focused tests accompany each pure contract. The older Allowed-path descriptions
in the checklist are initial scopes; the completed bounded handoffs are reflected
by this final inventory, not permission for a future builder to edit broadly.

- Full core suite: **563 tests, 0 failures, 2 skipped** (planner log
  `/tmp/unlirice-planner-final-tests.log`).
- Xcode `UnliRiceCapture` Simulator and `UnliRice` Debug: **BUILD SUCCEEDED**
  (`/tmp/unlirice-ios-verified.log`, `/tmp/unlirice-mac-verified.log`). Sandbox
  compiler-plugin failures were resolved by running the builds with the normal
  host permissions; they were not source errors.
- JSON-RPC smoke: **12 requests pass**, including initialization freshness,
  context retrieval, invalid-offset refusal, exact same-note todo conversion and
  catalog exposure (`/tmp/unlirice-mcp-smoke-result.json`). Temporary corpus only.
- Isolated iPhone Simulator: conversion/persistence **1 test passed**, and
  project navigation/converted capture/remote evidence **1 test passed** in a
  separate run. An earlier failing sleeve-tap run found and drove a hit-area fix.
  Results `/tmp/unlirice-capture-ui-qa-result-2` and `...-3`.
- Reviewed actual light/dark renders. Screenshots contain sample fixtures, not
  the founder's live notes, and are not App Store submission assets.
- Unverified before release: real voice transcription and interruption on device;
  real two-device cloud transport; live Codex and Claude client compliance after
  installing updated helper; iPad; VoiceOver/largest type/Reduce Motion and
  Reduce Transparency; biometric app-switcher coverage. Fixture tests prove state
  and transport contracts, not those production environments.

No release numbers, entitlements, uploads or production app installation changed.
Initialization now explicitly explains unavailable/old overview data. Both project
and capture matching normalize project tags; reserved tags such as `todo` remain
exact lowercase. Phone import-scope migration preserves old offsets once before
switching, while the pre-existing own-shard publication reset is retained.


Checkpoint note: physical-device/release acceptance is filed in Unli Rice as
“Test the updated phone app with your Mac” (`BBC01BEE-FE38-4D53-9999-59422F498AD8`),
linked to handoff `3A5B38D0-4421-4031-A660-1924EF09BE54`. No unrelated to-dos closed.
The planner's P7 local review is complete; unchecked manual acceptance above is
explicitly deferred to that device test, not claimed passed.


## Shared Capture scheme follow-up — 2026-11-01

The founder's screenshot showed the main-checkout Xcode project, not the feature
checkout. The target exists in both, but project.yml only explicitly shared the
Mac scheme. Added explicit shared UnliRiceCapture build/run/archive configuration
with Debug run and Release archive; generated project regenerated. Xcode was
opened at the feature checkout and scripting verified active scheme
UnliRiceCapture. Xcode -list confirms it, and the Simulator build passes
(`/tmp/unlirice-shared-scheme-build.log`). No source behavior, signing, release
number or to-do state changed. Mechanical edit built by explicitly selected
Luna/low; planner inspected the diff and reran scheme/build checks.
