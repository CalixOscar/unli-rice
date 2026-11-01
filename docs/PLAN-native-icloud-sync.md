# PLAN — Native iCloud sync

**Intent:** docs/intent/INTENT-011-native-icloud-sync.md
**Spec:** docs/SPEC-native-icloud-sync.md
**Planner:** codex
**Reviewer:** claude
**Branch:** CalixOscar/Unli-rice-Capture
**Baseline:** 2f3506c; clean tree before these planning documents
**Stage:** 8 — implementation, peer review and internal TestFlight uploads complete; physical delivery acceptance remains unverified
**Founder skips:** none for this native sync feature

## Settled architecture

Astra's read-only architecture audit confirmed the local log remains authoritative.
The new transport is distinct from the mutable manual-folder shard bridge.

### Shared core contracts

- Container `iCloud.com.calmdownoscar.unlirice`, iCloud Documents; app-managed
  `NativeSync-v1/` outside public Documents. Resolve through FileManager off-main,
  never a hard-coded ~/Library path or cached container bookmark.
- `NativeSyncMode`: privateDevice='private', iCloud='icloud', folder='folder'.
  `NativeSyncPreferences` version1 in local corpus directory, not cloud: mode.
  If absent infer old folder/private from existing app preferences, never cloud.
- `NativeCloudBinding` local version2 stores binding UUID, canonical CloudKit
  container/environment/user-record tuple and one archived ubiquity token per
  executable. Known clients compare only their own token; unknown clients enroll
  only after canonical equality. First binding requires runtime consent. Version1
  migrates only under its original token, preserving UUID/local cursor state.
  Missing/different tokens, corrupt/future bindings and environment mismatch pause.
  No reset/rebind UI. Even a corrupt binding blocks permanent purge. B7/B7a below
  records the signed evidence and settled concurrency/deadline details.
- Native cloud event files `events-<deviceUUID>-<batchUUID>.jsonl`: immutable,
  coordinated atomic creation. Complete raw JSONL records, <=500 records and <=2MB
  per batch, no line >1MB. Export cursor committed only after successful creation.
  All source events may relay once per destination; do not use nonunique iPhone
  device labels as origin identity. UUID dedup is authoritative.
- Strict local native state keyed by binding UUID, distinct from legacy SyncState:
  published byte offset and successfully imported batch names. Corrupt/future
  state, missing preexisting source, or shrunk source never reset. Native batch
  imports validate whole batch before durable append, then mark imported. Rebuild
  NoteService after imports. C11 uses the causal correction below; timestamp/UUID
  never overrides an observed predecessor.
- Reuse CaptureSyncBridge.withLock for local state/import/export transactions.
  Stage/download cloud reads before acquiring that lock; never nest locks. Cloud
  IO uses NSFileCoordinator with account/generation revalidation in accessors.
  A failed publication leaves source/cursor retryable; duplicate batch on crash
  is safe by event IDs. Never delete cloud batches or rewrite canonical log.
- `NativeCloudDiscovery` uses NSMetadataQueryUbiquitousDataScope constrained to
  native subtree; requests noncurrent items and notifies app. Coordinated reads
  touch only current files. A metadata update and foreground timer trigger retry;
  do not promise native iOS background execution. All IO account failure paths
  discard session URLs/phone overview cache, keep local notes, report pause.
- Per-Mac `studio-overview-<deviceUUID>.json`. Choose newest successfully decoded
  downloaded overview, preserving producer and observedAt. No failed scan writes a
  fresh empty report. Keep legacy fixed `studio-overview.json` behavior unchanged.
- Cloud-bound corpora archive only. Guard CaptureStore.deleteCapture and Mac
  moveSelectedToTrash for binding-file presence regardless of current sync mode.
  No tombstone/compaction protocol is introduced.

### Host integration

- Mac per-corpus sync mode/status observable in AppStore; Enable action saves
  consent, then resolves account/container and syncs in detached work. Uses
  existing scanRoots, no new folder selection if roots already granted.
- Extract report gathering from AppStore+Studio to reusable native overview
  publisher; refresh automatically on enable, activation and every60seconds while
  app process is running. Prevent overlapping work/debounce. App closed means
  no Mac overview rescan; MCP can still sync event batches independently.
- Mac iCloud controls in Setup/AI Tools or a dedicated small sync sheet from the
  gear. Phone initial choice becomes Sync with iCloud / Keep on this device;
  manual folder under Advanced. Existing private/folder state remains unchanged.
- Phone CaptureStore runs native service for cloud mode, legacy method otherwise.
  Studio uses store.loadStudioOverview() rather than assuming sharedFolderURL is
  the native directory. Foreground/discovery retry; do not run cloud IO on main.
- MCP synchronizes native when current corpus mode says cloud, manual bridge for
  folder mode. No native access for environment override fixtures. Existing
  project_context sees updated local notes and honest sync warnings.
- Wrap MCP as UnliRiceMCP.app with own App ID/profile and iCloud entitlements.
  Keep Contents/MacOS/unlirice-mcp as a relative symlink to the nested executable.
  Never claim adding restricted entitlements to a bare executable is sufficient.
  Background agent remains unentitled and does not resolve native container;
  context already in local log stays readable.
- Ad-hoc Scripts/make-app.sh output may preview private/legacy mode but must not
  carry unsupported cloud entitlements or claim native capability verified.

## Ordered builder steps

No builder starts until Claude review is answered and dialogue settled.

- [x] P0 — planner: record intent/spec and settle pre-mortem. Shared Apple Developer
  container/App IDs were subsequently approved and provisioned, recorded below.
- [x] B1 — build: native preference/account/transport/discovery core and tests.
  Files new Sync/NativeSyncPreferences.swift, NativeCloudBinding.swift,
  NativeCloudTransport.swift, NativeCloudDiscovery.swift; Projector.swift;
  matching Tests/UnliRiceCoreTests files. C2–C6/C10–C12 core contracts.
- [x] B2 — build: native capabilities and provisionable MCP wrapper.
  Files project.yml, UnliRice.entitlements, UnliRiceCapture.entitlements,
  new UnliRiceMCP.entitlements and UnliRiceMCP-Info.plist, Scripts/make-app.sh.
  C1/C9/C12. Generate Xcode project; inspect bundled helper/symlink; unsigned
  Mac/phone builds and signed-capability attempt after portal setup.
- [x] B3 — build: automatic Mac overview/native sync plus connector integration.
  Files AppStore.swift, AppStore+Studio.swift, AppStore+Cleanup.swift,
  UnliRiceApp.swift, ConnectView.swift or new NativeSyncSettingsView.swift,
  unlirice-mcp/main.swift; new reusable core NativeOverview service/tests if
  needed only under planner-set interface. C2/C5/C7/C9/C10.
- [x] B4 — build: phone native opt-in and automatic Studio data.
  Files CaptureStore.swift, SharedFolderManager.swift, CaptureView.swift,
  CaptureStudioView.swift, relevant archive UI. C2/C5/C6/C8/C10/C12.
- [x] P5 — planner: review worker diffs, rerun full core suite, protocol smoke and
  both Xcode builds; signed entitlements/cloud discovery checks when provisioning
  permits; obtain Claude post-mortem, record evidence and physical-device limits,
  update memory/decisions/wiki and checkpoint. No production store activation.

## Verification

Planned, not yet passed for this feature:

```
swift test --disable-sandbox --scratch-path /tmp/unlirice-native-tests
xcodegen generate
xcodebuild -project UnliRice.xcodeproj -scheme UnliRiceCapture -sdk iphonesimulator -configuration Debug -derivedDataPath /tmp/unlirice-native-ios CODE_SIGNING_ALLOWED=NO build
xcodebuild -project UnliRice.xcodeproj -scheme UnliRice -configuration Debug -derivedDataPath /tmp/unlirice-native-mac CODE_SIGNING_ALLOWED=NO build
```

Fixtures: private/folder preference migration; A→logout→B→A account gate; malformed
binding/state/batch; source shrink; crash duplicate batch; equal timestamp/tag
ordering; two phone labels; concurrent GUI/MCP; downloaded vs placeholder overview;
archive/purge guard even in private mode. UI: one-time native choice, preserved
private choice, unavailable iCloud recovery, foreground automatic overview and
existing audio/lock/typed capture. Signed Mac+phone real delivery is its own gate.

## Evidence and sources

Baseline source confirms no iCloud entitlements in current app/profiles and a bare
MCP executable. Profiles for app/Capture were inspected 2026-11-01; no native
container entitlement. Developer portal authenticated for team22SNGN5JYD; no
capability mutation yet.

Apple: https://developer.apple.com/documentation/xcode/configuring-icloud-services
https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/iCloudFundametals.html
https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
https://developer.apple.com/forums/thread/835305


## Builder interface contract

Core APIs are public and Foundation-only. Runtime resolution is only called by
explicit native mode, off the main thread, never by environment-overridden MCP.

- NativeSyncPreferences.load(besideEventLog: URL, legacyFolderChosen: Bool) throws
  returns version1/mode; .save(besideEventLog:) writes atomically. Missing maps to
  legacy folder or private; malformed/future preferences throw, never opt in.
- NativeCloudBinding.open(eventLogURL: URL, token: NSObject?, allowCreate: Bool)
  throws returns binding with UUID; .matches(token: NSObject?) checks equality;
  .exists(besideEventLog:) means archive-only even for malformed binding. Local
  serialization uses NSKeyedArchiver/Unarchiver; no account token in cloud files.
- NativeCloudSession.resolve(eventLogURL: URL, allowCreate: Bool) throws resolves
  FileManager token and container, validates binding, creates NativeSync-v1 root.
  Result binding/rootURL; .isCurrentAccount checks current token each use. Tests
  inject token/root directly; never require a real signed-in cloud account.
- NativeCloudTransport.synchronize(eventLogURL: URL, rootURL: URL,
  binding: NativeCloudBinding, deviceID: String,
  accountIsCurrent: () -> Bool, discoveredURLs: [URL] = []) throws returns
  eventsImported/eventsPublished/waitingForDownloads/issues. Session URL expires
  with account/mode/corpus changes; validate before and inside coordinated IO.
- NativeCloudTransport.publishOverview(_: StudioOverviewFile, rootURL: URL,
  deviceID: String, accountIsCurrent: () -> Bool) throws; preserve newer own
  snapshot if racing writer has already published later generatedAt.
- NativeCloudTransport.latestOverview(rootURL: URL, accountIsCurrent: () -> Bool,
  discoveredURLs: [URL] = []) throws returns overview?/waitingForDownloads/issues;
  read receipts similarly via public receivedCaptureIDs helper. Only Mac writes
  capture receipts, via public publishReceipt method using actual local capture IDs.
- NativeCloudDiscovery starts/stops on main runloop, exposes discovered URLs,
  invokes an onChange callback after gathered/updated results, and requests cloud
  downloads. Helpers may use a bounded one-shot gather while servicing a request.
  Foreground hosts retain a watcher; tests use a fake/local directory.

Do not add APIs unrelated to this task. If an exact signature conflicts with a
platform API, builder reports it; the planner settles the adaptation before edit.


## Pre-mortem settlement amendments

See docs/dialogue/native-icloud-sync.md; all blockers answered. The existing
loadStudioOverview name is a NEW B4 API, not a claim about baseline source.
Native phone getter signature: public func loadStudioOverview() throws ->
StudioOverviewFile?; reads only validated native cache or scoped legacy folder,
never blocks main on cloud discovery. Asynchronous sync refreshes cache.

B1 also owns StudioOverviewFile.swift (read/write optional filename defaults to
existing fixed filename), Trash.swift (global purge refusal for binding-file
presence, covering GUI/CLI/agent), and focused regression tests. Binding archive
check precedes any audio deletion at B4 call site. Native state NEVER consults
legacy SyncState/publishedCursor; manual resets remain manual-only.

All metadata/coordinated cloud IO happens OUTSIDE CaptureSyncBridge.withLock.
Algorithm: snapshot source range/state under brief lock; release; coordinate
immutable export and stage downloaded imports; reacquire/reload native state,
append unknown event IDs and commit processed batches plus max exported offset.
Source cannot shrink after cloud binding except external damage (explicit error).
Racing exports duplicate transport records but never logical events. Failure to
acquire within two seconds is retryable UI/context status, not an account error.
Account validity is checked at stage/write/accessor and final commit boundaries.

B2 wrapper lives Contents/Helpers/UnliRiceMCP.app; external command is a relative
symlink. P0 ad-hoc structural signing/stdio spike precedes B2; restricted signed
capability needs the real portal/profile check later. No native delivery claim
until signed app evidence. C11's initial timestamp/UUID rule was rejected by
full-suite verification and is superseded by the causal correction below.
Entire log is rebuilt after imports; batch splitting a note is allowed. Tests use
two distinct device IDs with the identical literal iPhone label.

Bundle-identity correction: a later probe showed symlink launch reports the parent
CFBundle identity despite valid signatures. Before settings, corpus or iCloud
resolution, MCP canonicalizes the actual image path from _NSGetExecutablePath
(never an executable chosen from argv[0]) and self-executes that canonical path
with all arguments/stdio preserved if argv[0] differs. B2 owns only this startup
addition in Sources/unlirice-mcp/main.swift. The corrected ad-hoc probe reports the
child bundle from both paths and preserves stdin/arguments. Sandbox-entitled
ad-hoc launch exits 134 before output, so provisioned sandbox execution remains
unverified. No iCloud capability claim follows from the unsandboxed probe.


## Release scope amendment

Founder goal: “keep going until icloud applekit is implmented and uploaded to app
store”. Uploads for both apps are authorized. The earlier no-upload boundary is
superseded by this explicit current instruction. Check live App Store Connect
version/build trains before selecting numbers; use real signing/capability checks,
release acceptance and the required prelaunch post-mortem. No automatic opt-in of
the production corpus. P0 ad-hoc wrapper layout/stdio spike passed 2026-11-01;
restricted provisioned access remains a separate verification gate.

## Live release prerequisites — 2026-11-01

Read-only App Store Connect check: Mac has version 1.5 builds 11 and 10
(Ready to Submit in TestFlight), with 1.5 Waiting for Review in Distribution.
Capture has version 1.3 builds 8 (Ready to Submit) and 7 (Missing Compliance),
with 1.1 Ready for Distribution. These are observed train numbers, not new
release numbers; no build has been uploaded by this feature work.

App Store Connect reports an updated Apple Developer Program License Agreement
requiring Account Holder acceptance before existing apps can be updated. The
founder was informed; the agent will not accept legal terms on their behalf.

Automatic approval review rejected clicking the Developer portal's iCloud
capability checkbox because this changes permissions on a signed App ID and
requires explicit confirmation. The pending approval names the shared container,
main/Capture/helper App IDs and helper app group. No capability has been changed;
do not bypass that rejection through automatic provisioning or another API.

## C11 correctness amendment — causal order

The first full host run failed 8 assertions (576 tests, 2 skipped). Source confirms
timestamps encode whole seconds: random UUID sorting can reverse sequential
tag/untag or archive/unarchive actions. Astra rejected a stable-arrival fallback
because independently downloaded batches can arrive backwards. Do not weaken
failing fixtures.

Add optional `Event.causalParents: [UUID]?` and metadata kind `causalOrder`.
Nil means legacy; [] declares a root. Metadata uses relatedEventId for a legacy
semantic target, matching noteId, and causalParents for its predecessors. Metadata
never edits content, attribution or dates. All declarations contribute their
constraints; never choose one by UUID.

Lifetime-bound EventStore writers hold their existing event-log flock while
migrating undeclared history, checking ancestry and stamping all observed heads
on new semantic events. Initial migration chains each note's stable timestamp /
log-position order, appending declarations without rewriting old bytes. It is
idempotent by declared target IDs and retains partial progress. Subsequent writes
from an older local executable attach using preceding local causal heads;
native imports already carry declarations, so arrival never supplies ancestry.
Unreadable history cannot silently be skipped. Missing ancestry/cycles block a
new mutation on that note. Never-bound history retains its existing fold/writer.

Pure EventCausalOrder returns ordered semantic events, pending event IDs and
conflicted note IDs. Topological order uses timestamp/UUID only between ready
concurrent events. Distinguish real cycles from missing ancestors. Projector adds
ProjectionResult(notes, pendingEventIDs, conflictedNoteIDs); NoteService throws
typed orderingConflict(noteIDs) on a cycle instead of returning invented state.
Changed causal logs fully reproject, including another process's writes; quiet
reads keep the cache. Wholly legacy logs keep incremental folding.

Native JSONL selects an original cursor window plus every raw declaration for
each legacy target in that window; deduplicate extra record IDs. Extras count
toward 500 records/2MB, reducing the window until it fits. Advance the cursor only
over original source bytes. A single target whose declaration set cannot fit
fails explicitly without advancement. Validate in-batch declarations for every
legacy semantic target; declaration-only batches are valid. Parent events may
arrive later and stay pending. Raw unknown fields/kinds cross unchanged. No new
authoritative sidecar.

Import transaction amendment: EventStore.appendRawBatch holds one event-log flock
for all validated/deduplicated imported records, declarations before semantic
targets. A concurrent local writer must never mistake an imported legacy target
for an old local executable's undeclared write. Declaration-first prefixes also
remain safe after interruption. Bound migration/writing strictly rejects malformed
or incomplete canonical history rather than using EventStore.read's legacy skip
behavior. Native import declarations and semantic records are durable local facts
before native state marks a batch processed.

Python mirrors the causal fold and returns its existing failure signal on cycles.
Older binaries retain optional fields/unknown metadata but do not implement causal
semantics. Contradictory historical replica orders may form a cycle: retain bytes
and report it rather than invent intent.

- [x] B1a — build: causal event/writer/projection/cache foundation. Files Event.swift,
  EventStore.swift, new EventCausalOrder.swift, Projector.swift, NoteService.swift;
  NativeCloudProjectionTests.swift, new EventCausalOrderTests.swift,
  ProjectionCacheTests.swift. Exhaustive switches only in Sources/UnliRice/
  HomeView.swift, ContentView.swift and core Export/OKFExporter.swift, with neutral
  metadata labels.
- [x] B1b — build: self-contained causal batches and Python agreement. Files
  Sync/NativeCloudTransport.swift, Scripts/unlirice-prompt-hook.py,
  NativeCloudTransportTests.swift, StudioTodoTests.swift. EventStore.swift also owns
  nativeCausalSnapshot(): strict migration and raw snapshot under one event-log
  flock, with a matching EventCausalOrderTests regression. NativeCloudBinding.swift
  gets plain-language error copy. Starts after B1a review.

Fixtures: sequential same-second tag/untag, archive/unarchive, flag/resolve, body
appends; reversed downloads and missing ancestors; joining two observed heads;
interrupted/idempotent migration and unchanged bytes; concurrent local writers;
cycle versus missing parent; byte/count/cursor limits with declaration extras;
warm/cold/second-process and Python equivalence. Claude delta review precedes B1a.

Claude delta review is answered/settled in the dialogue. Additional contracts:
orphan declarations (target absent) are inert, not blocked semantic ancestry.
EventStore.appendRawBatch assembles declaration-first data under one event-log
flock; checked POSIX writes handle EINTR/short writes, with no power-loss atomicity
claim. Strict history preflight precedes initial binding; refusal leaves legacy
notes writable. Established damaged histories fail closed with visible error,
never automatic truncation. Cap distinct parents at 1024 and reject an oversized
write without dropping heads. Projector.projectResult is the pure arbiter;
project wraps notes, omitting conflicts, while NoteService throws typed conflicts.
apply remains the wholly legacy stable incremental fold. Initial migration's
persisted prefix boundary is the first causal event/declaration's source position.
B1a/B1b are not independently shippable: hook agreement must pass before any
production activation. No interim production corpus binding is permitted.

Root independently accepted B1a: full host suite 591 tests, 2 skipped, 0 failures
(/tmp/unlirice-causal-root-review.log). For B1b, stage at most 16MB / 32 ready
batches per pass and report remaining work for retry. Receipt reads are bounded
before allocation. nativeCausalSnapshot avoids a local writer interleaving between
migration and export snapshot; native cursor still covers original source bytes
only. No cloud IO runs while either local lock is held.

Root review enforces the existing 1MB native line cap at initial history preflight
and bound writer/raw-import primitives, before any new bytes are appended. Otherwise
an oversized event could permanently stall an archive-only corpus. Unbound legacy
writes retain their old behavior; a failed first binding leaves that history intact.
No automatic splitting, truncation or repair is introduced.

Hosts use Result.hasMoreWork (not issue-string matching) for immediate continuation:
remaining local bytes, newly imported records, or remaining cloud batches after
committed ready-filename progress. Placeholder-only discovery reports waiting and
does not cause an automatic busy loop. Duplicate-only batches still advance.

## Post-mortem fixes — settled contracts

Claude's post-mortem and root answers are appended to the dialogue. Astra settled
atomic per-note diagnostic snapshots. Add public ProjectionDiagnostics with
pendingEventIDs, pendingNoteIDs, conflictedNoteIDs, incompleteNoteIDs union,
summary (UI counts) and technicalSummary (sorted IDs); empty summaries are nil.
Add public ProjectionSnapshot(notes: [Note], diagnostics: ProjectionDiagnostics)
and NoteService.projectionSnapshot(includeArchived: Bool = false). Notes are
complete/nonconflicted only and diagnostics come from that exact cached refresh.
Derive pending note IDs from the same full event array; conflicts take precedence.
Reset cached diagnostics with rebuild/truncation. List/search/reviews return
healthy notes; get/require/mutations throw typed orderingPending or orderingConflict
for the affected ID. Other notes and unrelated creation remain available. Raw
malformed history remains fatal. No partial note prefix is a successful public read.

Mac/phone sync and all MCP success responses consume diagnostics, even private
mode and zero-download/no-error transport. Nonempty diagnostics prevent a plain
successful-sync message. A separate MCP warning content block preserves primary
payload shape and names sorted IDs; direct affected operations return typed errors.
Initialization instructions include the warning. Conflicts alone never retry in a
loop. Receipt IDs and overview note-derived state use complete snapshot notes;
phone receipt display removes locally incomplete IDs. Gathered reports/overviews
carry the diagnostic summary while retaining valid filesystem evidence.

- [x] B1c — build: per-note diagnostics and consumers. Allowed production files
  core NoteService.swift, Sync/NativeOverviewGatherer.swift; Mac
  AppStore+NativeSync.swift; Capture/CaptureStore.swift; MCP main.swift,
  ToolDispatcher.swift. Tests new ProjectionDiagnosticsTests.swift and matching
  NativeOverviewGathererTests.swift. Preserve existing startup canonicalization.
  AppStore.swift also consumes the snapshot on reload. Add optional
  transactionLog(includeOrderingMetadata: Bool = true), default preserving raw
  audit/export behavior; Mac recent activity passes false before its limit so
  metadata cannot impersonate another connected writer or crowd out real actions.
- [x] B1d — build: replay performance and durable primitive hardening. Core
  EventCausalOrder.swift (min-heap with cached timestamp/UUID keys), EventStore.swift
  (skip redundant initial baseline sort; batch declaration/local-history validation),
  Sync/NativeCloudTransport.swift (recover current corrupt own overview, wait on
  placeholders, preserve future version; reject unsafe IDs). Matching
  EventCausalOrderTests/NativeCloudTransportTests. No authoritative cache or new
  conflict resolution protocol. Benchmark identical 6,000-event fixture before/after.

UI summary text: “N notes are waiting for earlier changes. M notes have conflicting
history. Other notes are available.” Omit empty clauses and use singular grammar.
Technical summary adds sorted affected note IDs. Acceptance: pending, conflicted
and healthy notes coexist; healthy get/write/create succeeds; affected operations
fail specifically; later ancestry clears waiting; warm/cold/second-process agree;
receipts exclude incomplete IDs; overview/MCP expose warnings.

Lifecycle review: the 60-second native refresh belongs to AppStore's process-lived
timer, not a WindowGroup view task that is cancelled when the last window closes.
B3 owns the small AppStore.swift / UnliRiceApp.swift correction. Existing routine
timers remain unchanged; native work still detaches and uses its overlap guard.

## Owner approval and release packaging progress

The founder explicitly answered “Yes” to enabling the shared iCloud container
for Unli Rice, Capture and the MCP helper, including the helper's app-group access.
This resolves the earlier automatic approval rejection; no broader account or
legal-term change is inferred. Portal verification found the exact shared
container already registered and Capture already assigned to it. Main App ID
G5GJQ44JW6 now has iCloud enabled with one container; reopening confirmed Save
disabled, iCloud checked and unrelated Push to Talk unchecked. Capture App ID
9J24L2GZK5 has the exact shared container checked. Helper registration/profile
generation is in progress through authorized Xcode automatic provisioning.

Unsigned Release archives passed for both apps in /tmp/unlirice-native-release/.
Mac main and nested MCP contain x86_64 and arm64. App/widget versions remain
Mac 1.5 (11), Capture 1.3 (8); these verification archives cannot be uploaded using
already occupied build numbers. No version bump or upload has happened.

## Signed provisioning and release counters

The founder confirmed Xcode sign-in and agreement acceptance. ASC's agreement
banner is gone. Xcode 27's GUI shows the account/team and successfully signs both
apps, although xcodebuild still reports No Accounts against the legacy account
store. GUI provisioning generated explicit Mac main/helper profiles. Root inspected
all three signed app/helper entitlements and embedded profiles: exact container,
CloudDocuments and app group match. No native corpus was activated.

Live ASC recheck 2026-11-01: Mac 1.5 remains Waiting for Review, highest build 11;
Capture's open 1.3 train remains highest build 8. Upload the next builds without
changing the existing selected review build or submitting anything for review.

- [x] B6 — build-light: increment verified release build counters. Only project.yml:
  Mac main, Mac widget and MCP helper CURRENT_PROJECT_VERSION 11→12;
  Capture and Capture widget 8→9. MARKETING_VERSION values stay unchanged.
  Verify xcodegen and read the five generated build settings. No tests for this
  mechanical metadata change; signed archives/validation verify the actual packages.

B3's release copy also owns Sources/UnliRice/PrivacyPolicyView.swift: remove the
unconditional local-only claim; describe opt-in iCloud and archive-only retention
consistently with PRIVACY.md. Planner owns README/PRIVACY/reviewer/release docs.
These local documents are not a claim that the public privacy URL is updated.

## Intermediate verification — 2026-11-01

B2 wrapper layout and symlink inspected in unsigned Mac output. B3/B4 compile
with xcodegen-generated project; Mac log /tmp/unlirice-native-mac-host.log and
phone /tmp/unlirice-native-phone-followup.log. Root independently ran focused
native tests: 17 passed, 0 failed (/tmp/unlirice-native-review-focused.log).
These precede the causal correction and are not final-suite acceptance.

One isolated Simulator UI test passed (0 failures), covering private mode,
signed-out native opt-in/pause, absence of contradictory private-mode copy and
private persistence after relaunch. Root exported/reviewed the signed-out settings
screenshot: /tmp/unlirice-native-ui-attachments/; result
/tmp/unlirice-native-ui-result. Only disposable Capture Studio QA simulator used;
no physical device, actual account or production corpus. No cloud delivery claim.

Native read/write and unknown-kind tests require host macOS file coordination;
the sandboxed failure (Cocoa512) was reproduced as environment-only by a host
rerun passing the same test. Host execution does not grant signed cloud access.


## B7 — canonical account identity correction (C1/C5/C9)

Signed real-account probes proved ubiquityIdentityToken is executable-scoped:
same-app comparisons pass, main/helper comparisons fail. A second signed probe
using explicit shared CKContainer and Development entitlements proved canonical
user record equality in both directions. Only booleans were reported, no corpus
or custom records accessed. Account setup and agreement acceptance are complete.
Existing development profiles allow CloudKit and both environments. Do not upload
the existing pre-correction archives.

Astra settled local binding schema v2: version, bindingID, containerIdentifier,
environment, userRecordName and clientTokenArchives keyed by actual Bundle.main
identifier. Canonical identity is the exact container/environment/actual fetched
recordName tuple, never CKCurrentUserDefaultName. Raw identity stays local, is not
logged or written into cloud documents. Production provider permits only the
three existing app IDs. An injectable provider supplies clientID, environment,
currentUbiquityToken and a bounded canonical lookup for tests.

Missing binding requires allowCreate, strict history preflight, nonnil stable
current token and successful canonical lookup. Known client requires its OWN
archived token equality; a changed token never triggers automatic relearning.
Unknown client requires a fresh matching canonical lookup before enrollment.
Version 1 migrates only when this client's token equals its original archive;
preserve bindingID and cursor namespace, registering only the migrating client.
Other clients pause with “Open the app that originally linked these notes to
finish upgrading the iCloud connection.” Corrupt/future/wrong-container/wrong-
environment/mismatched identity fails closed. No reset or rebind.

Read/check under CaptureSyncBridge lock, release for network, then reacquire and
reread before writing; merge concurrent registrations without losing entries.
Revalidate generation and initial token before each write and after lookup. The
provider has a 15-second total deadline, polls cancellation, ignores late results,
and never waits on network under local locks. Session retains scoped client ID
and approved token; account checks include generation. Both GUI hosts invalidate
on NSUbiquityIdentityDidChange AND CKAccountChanged. Phone completion uses the
session rather than an unscoped token comparison. Synchronous resolution remains
safe in the MCP startup loop; no main-thread precondition is introduced.

Add CloudKit alongside CloudDocuments to the three entitlement files. A single
NATIVE_CLOUD_ENVIRONMENT setting drives both signed entitlement and runtime Info
key for all three apps: Debug Development, Release Production. Environment changes
pause existing incompatible bindings. No runtime production corpus opt-in is
authorized by a packaging probe.

- [x] B7 — build: implement the settled v2 binding/provider, scoped session and
  host invalidation, entitlement/environment wiring, and deterministic fixtures.
  Allowed files: NativeCloudBinding.swift, new NativeCloudIdentityProvider.swift,
  CaptureStore.swift, AppStore.swift, three app entitlement files, project.yml,
  three app Info.plists; NativeCloudBindingTests.swift, NativeCloudTransportTests.swift,
  EventCausalOrderTests.swift, ProjectionDiagnosticsTests.swift and a shared test
  identity fixture if needed. No event/transport/cursor semantics may change.
  Verify focused tests and xcodegen; root reviews and reruns full suite/builds.

Acceptance: distinct main/helper tokens with matching canonical identity enroll;
known-client token change, unknown wrong identity/environment, logout, corrupt,
timeout, cancellation, migration mismatch and concurrent enrollment fail safely.
v1 migration preserves UUID; no canonical fetch for known client; no write after
invalidation; signed runtime Info equals entitlement. Signed main/helper canonical
comparison is already proven in Development; production and two-device delivery
remain separate checks. Regenerate archives with Mac 1.5 (12), Capture 1.3 (9).


B7 peer review settled: production resolve rejects nonempty UNLIRICE_DATA_PATH
before any provider/account/container access. Test binding APIs inject fakes.
Widgets never resolve sync, and the production three-ID allowlist rejects other
executables before token or network access. Actual Bundle.main remains authority;
root independently verified canonical self-exec reports helper ID through the
public symlink. Preserve that behavior and recheck signed output. Environment
mismatch recovery is matching build environment or private local use; no binding
deletion/purge/rebind is introduced. Local notes remain available. A future
cross-environment migration requires separate design. The first-lookup 15-second
maximum is accepted; known-client resolution requires no network fetch.


### B7a — finish identity safety and acceptance (build)

Root reran the unchanged B7 focused suite with host file coordination: 41 tests,
0 failures (`/tmp/unlirice-native-b7-host-focused.log`). Builder's Cocoa256/512
failures were shell sandbox restrictions, not a transport regression. Do not
change transport production code. B7 remains incomplete until these checks:

- Add deterministic identity acceptance tests listed above using injected fakes.
- Guard the reread against replacement of an existing binding: initial v2 must
  retain bindingID and canonical tuple, initial v1 must retain bindingID during
  migration or concurrent v2 migration, and an initial current binding may never
  become legacy/missing. Initial missing may accept a concurrently created v2
  only if canonical tuple matches. Legacy reread is permitted only for the same
  initial legacy UUID and original token. Reject changes without writing.
- Reject CKCurrentUserDefaultName in decoded v2 bindings, not just fetched names;
  every decoded token archive must unarchive to NSObject.
- Extract the callback deadline wait into an internal injectable utility used by
  LiveNativeCloudIdentityProvider: monotonic ContinuousClock deadline starts
  before callback initiation, 15-second production budget, check cancellation
  at most every 50ms. Locked result box closes on success/error/timeout/cancel;
  late callbacks are ignored. Tests inject a short timeout and delayed callback
  to verify actual bounded behavior, not only a fake thrown timeout.

Allowed production files for B7a only NativeCloudBinding.swift and
NativeCloudIdentityProvider.swift; tests NativeCloudBindingTests.swift and
NativeCloudIdentityFixture.swift. No additional architecture choices. Root owns
all documentation and host/build verification. All other tree changes preserved.


- [x] B8 — build-light: preview packaging strips the newly added restricted
  environment entitlement together with the existing three cloud keys. Exact
  edit in Scripts/make-app.sh: append
  `com.apple.developer.icloud-container-environment` to the `for key in` list
  beneath “Preview builds have no provisioning profile”. Nothing else changes.
  Verify `bash -n Scripts/make-app.sh` and diff check. Preview remains unable to
  resolve native cloud; signed Xcode builds carry actual environment configuration.


## Final source checkpoint verification — 2026-11-01

B7/B7a root-reviewed and Claude post-mortem reports no blocking defect. Full host
suite: 620 tests, 2 skipped, 0 failures (`/tmp/unlirice-native-final-core.log`).
Final signed Release archives both pass in `/tmp/unlirice-native-final-archives/`:
UnliRice.xcarchive Mac1.5(12) and UnliRiceCapture.xcarchive Capture1.3(9).
Parent/helper/Capture strict signatures pass with runtime AND signed environment
Production, exact shared container and CloudKit/CloudDocuments. Earlier UI test
1/0 passed on isolated QA simulator; no new UI behavior changed in B7. Source
lint, shell syntax, xcodegen and guardrail-template drift checks pass.

Root independently repeated signed cross-app canonical identity probes in both
Development and Production: main→helper and helper→main true, expected actual
bundle IDs, stable local tokens. Raw identity flowed only through anonymous
pipes/memory, no notes, native root or custom cloud records were accessed. This
is one-Mac identity evidence, not two-device delivery or production corpus opt-in.

B8 exact one-key preview stripping adjustment reviewed. Final archives precede
only this preview-script change, which does not participate in Xcode archives.

Upload is NOT complete. Command-line distribution export still cannot use the
GUI account/cloud-managed certificates; Organizer is the next path. Native UI
currently reports cgWindowNotFound; an asynchronous request asks the founder to
leave the Mac unlocked with Xcode visible. Existing Mac review build is untouched.
No submission, install over running production app, native production opt-in or
public privacy/listing update happened. Physical two-device/recording acceptance
and updated installed client hook deployment remain outside this checkpoint.


## Upload acceptance — 2026-11-01, Asia/Manila

Xcode Organizer reopened the final archives from the exact paths above. Both
used “TestFlight Internal Only” with automatic/cloud-managed distribution signing.
Organizer reported “Unli Rice 1.5 (12) uploaded” and
“UnliRiceCapture 1.3 (9) uploaded”; Capture's receipt shows 11:32 PM/build9.
App Store Connect live verification after processing:

- Mac app6792837485: build12 Internal, **Testing**, existing Family group.
- Capture app6800863948: build9 Internal, **Ready to Test**, no testers/groups
  assigned. No compliance blocker on build9.

Implementation/source checkpoint is `7df815e`. The release goal is achieved:
both verified builds are uploaded and processed. These are internal-only builds,
not public App Store releases and cannot be reused for review submission. No
Submit for Review, review-build replacement or withdrawal was performed. No
accounts, testers, invitations, public listings or privacy URLs were modified.
Any future public-release build must use fresh verified build counters.

Remaining physical-device acceptance is the existing Unli Rice to-do
BBC01BEE-FE38-4D53-9999-59422F498AD8. Capture requires its internal testing group
and tester assignment before installation through TestFlight; no invitation was
sent by this session. Real two-device delivery and the actual voice-capture →
project context → Codex/Claude reminder loop are not claimed verified. No
production corpus was opted in or running installed app overwritten.
