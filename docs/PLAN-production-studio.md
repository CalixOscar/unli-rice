# PLAN — Production Studio

**Intent:** docs/intent/INTENT-012-production-studio.md
**Spec:** docs/SPEC-production-studio.md
**Planner:** codex
**Reviewer:** claude
**Branch:** CalixOscar/Unli-rice-Capture
**Baseline:** 385fb1a, clean tree before planning
**Stage:** 5 — peer pre-mortem answered/settled; bounded implementation in progress
**Founder skips:** none

## Product and layout decisions

Retain the Mac's project-sleeve interaction rather than adding a conventional list.
New CaptureProjectDeck uses stable project IDs/cover hashing, the current project
and next three sleeves, max78pt peek, responsive square side within its container,
spring response0.45/damping0.78; Reduce Motion uses a short opacity transition.
Horizontal drag threshold40pt and horizontal dominance; vertical drags scroll.
Tapping a behind sleeve selects it; front opens detail. Buttons and VoiceOver
adjustment duplicate swipe access. Selection stays by ID across refresh/folds in transient CaptureStore.studioSelectedProjectID. Selection/refresh/swipe never starts recording. At accessibility type sizes, allow the cover to grow vertically rather than clip its content.

Duo detection uses public iOS27.1 UIHingeInteraction, whose SDK header guarantees
an initial callback and updates. Attach an invisible noninteractive observation
view to the root hierarchy. Closed => voice-only; partially/fully open => workspace;
Before first callback, awaitingCallback is voice-only. First nil => existing navigation on a nonhinged device. Preserve last known hinged
identity if temporarily detached; unknown hinged state is voice-only. No device
model string, screen/orientation or size-class inference of folding. Compile with installed iOS27.2 SDK, retain deployment minimum26.0. Guard every UIHingeInteraction/ArrangementView use with if #available(iOS27.1,*); older OSes retain existing behavior. Layout still uses scene geometry and size classes.

Root owns presentation state; the shared CaptureStore owns transient selected project ID and the existing recorder.
Keep workspace view identity mounted when folding, hide its interaction/accessibility
and overlay voice-only controls. Extend the existing presentation privacy wrapper
with the same folded cover for settings/detail/note/todo/typed sheets. Present
those at large detent while closed, preserving underlying editing/draft state;
restore original presentation on opening. Hinge observer ends editing on its own window when closing; never erase drafts. Wrap ALL sheet roots, including settings, typed notes and to-do sheets which lacked the current privacy wrapper. Inject store/presentation through environment; never instantiate a real store as a fixture fallback. App lock takes precedence over recording
controls everywhere. No automatic recording on fold/unfold.

Opened Duo workspace presents Studio and To Do together, using iOS27.1 split
ArrangementView to accommodate reserved regions. Fit content to actual space,
use scrolling when narrow, and avoid fixed 320pt columns overflowing split view.
Keep one accessible live recorder control; background workspace is not duplicated
in the accessibility tree when covered. Non-Duo app navigation remains unchanged.

## Account transition decisions (Astra read-only architecture)

Do not touch the founder's current runtime connection as part of editing code.
Separate structural decode from environment validation: normal v2 open gains a typed environmentMismatch(source:destination:) and explicit migration offer, not a reset. Explicit one-way
Development→Production migration is available only to a GUI client already in the
source map whose OWN current token equals its archive. Fresh Production canonical
fetch is required, outside locks, stable token/generation guarded. Never compare
record names across environments or permit the MCP helper to initiate consent.

Schema3 keeps bindingID; adds transportNamespaceID, source canonical tuple and
transition provenance, retains ALL existing client archives, and tracks clients
verified against the active canonical tuple. Only the initiating GUI is verified
at commit. A previously known client's own old token must match before fresh target
canonical enrollment. Truly unknown clients may enroll through canonical equality.
Known changed tokens never relearn. Version1, corrupt/future, wrong-container,
unknown GUI and reverse transitions fail closed with appropriate instructions.

CloudDocuments remains at NativeSync-v1; do not assume CK identity environments
imply different document roots. Keep all cloud batches and old cursor files.
Migrated cursors use transportNamespaceID, start from zero, replay/dedup safely.
Normal v2 cursors retain bindingID filenames. No event schema changes.

Consent names the Development→release transition and a private local recovery copy.
After consent, invalidate GUI work/discovery, snapshot exact source binding under
CaptureSyncBridge lock, fetch target identity outside lock, reacquire and require
exact source bytes/token/generation/history. Before commit create unique0700
NativeSyncRecovery/<transitionUUID>/ with0600 original binding, old cursor (or
absence manifest), preferences and validated exact event-log snapshot. Snapshot
failure leaves source binding unchanged. Add EventStore.validatedNativeRawSnapshot() as a NEW read-only method under its existing log flock; do not call nativeCausalSnapshot() or prepareNativeCausalHistory(). No ancestry writes during backup. Complete
and verify snapshot bytes before atomically replacing ONLY binding with v3.
Cancellation after commit pauses, never restores/deletes snapshots or old state.

Session guard checks current token/generation AND atomically read persisted canonical
binding/namespace before cloud side effects, without taking CaptureSyncBridge lock
inside another lock or holding a lock across cloud IO. Old in-flight v2 code may
finish an append-only pass using its old LOCAL cursor namespace against the SAME flat cloud folder; subsequent v3 opens reject it. No cloud payload partition or global fencing is claimed.
No instantaneous cross-process shutdown claim. Per-process invalidation plus checks
inside coordinated accessors fences new code as far as the existing contract allows.

## Ordered bounded steps

- [x] P0 — planner: intent/spec, peer pre-mortem and settled dialogue.
- [ ] B1 — build: iOS project sleeve deck (U1). Allowed CaptureStudioView.swift,
  CaptureView.swift, new CaptureProjectDeck.swift and CaptureStore.swift (only the transient studioSelectedProjectID field). Pass Binding into Studio. Do not alter sync or recorder semantics.
  Verify signed-out fixture Simulator build and synthetic three-project UI checks.
- [ ] B2 — build: Duo presentation and workspace (U2–U4). Allowed CaptureView.swift,
  CaptureStudioView.swift, CaptureStudioStyle.swift, TodoView.swift, TypedNoteSheet.swift,
  CaptureProjectView.swift and new CapturePresentation.swift/CaptureVoiceControls.swift.
  Keep drafts and hierarchy mounted; shared folded/privacy cover applies to ALL
  presentations. Xcodegen, iOS build, normal phone/iPad/Duo pose UI verification.
- [ ] B3 — build: account schema/transition core (S1–S3). Allowed core
  Sync/NativeCloudBinding.swift, NativeCloudIdentityProvider.swift, new
  NativeCloudEnvironmentMigration.swift; EventStore.swift (read-only snapshot only),
  NativeCloudTransport.swift (namespace only); focused migration/binding/transport
  tests and identity fixture. No changes to event fold or existing cursor bytes.
  Verify focused tests then root full suite.
- [ ] B4 — build: explicit migration consent/status hosts (S1/S3). Allowed
  Mac AppStore.swift, AppStore+NativeSync.swift, ConnectView.swift; CaptureStore.swift,
  CaptureView.swift; focused host/UI fixtures. No migration on retry or launch.
- [ ] P5 — planner: review diffs and Claude post-mortem; full suite, signed builds,
  actual capture→Mac receipt→fresh project_context acceptance A1; unassigned captures use all-project context without automatic tagging; resolve existing test
  to-do inclusion with founder. Verify no recording/draft losses across folds.
- [ ] B6 — build-light: exact release counters in project.yml only after live ASC
  numbering; no speculative marketing bump. Regenerate, archive and inspect.
- [ ] P7 — planner: exact screenshots/public privacy/reviewer copy, prelaunch analysis
  per vault07 before public review; explicit release destination; uploads/processing
  and submission verification. No invitations or unrelated settings changes.

## Evidence and boundaries

Local iOS SDK27.2/Xcode27.2 expose public UIHingeInteraction and SwiftUI hinge APIs;
installed Duo simulator type iPhone19,4 / runtime iOS27.2-iPhone19-4 exists.
Use an isolated QA simulator or authorized existing disposable QA device, not the
founder's active device data. Runtime prototype and test fixtures never resolve
real iCloud. New Sources files require xcodegen generate.

Astra's canonical-migration design is not an instruction to edit/delete the real
binding. The earlier blocked clipboard copy and whole-Capture-log export stay
blocked; do not bypass. Read-only Quick Look reported only version/environment.

Actual saved-recording test2026-11-02: targeted searches purple/lantern/photographer
return no match in registered or fresh installed MCP. Capture cursor exportedBytes
1483240 equals its event-file size, imported22batches; this proves publication
progress, not successful transcription. Fresh Production project_context(Nuptia)
reports0pending captures and syncIssue unreadable link. A1 remains failing until
actual capture identity/transcript and pending context can be verified.


SDK evidence: public UIKit/Headers/UIHingeInteraction.h under the installed
/Applications/Xcode.app iPhoneOS27.2.sdk explicitly documents an initial handler
callback. SwiftUICore arm64e-apple-ios.swiftinterface exposes DeviceHingeContext
and onHingeChange, availability27.1. Root verified these directly, not from a note.
The pre-mortem response in docs/dialogue/production-studio.md is authoritative for
all clarified choices. No minimum-OS raise or new cloud-file namespace is intended.


## B3 exact persisted/API contract

Normal v2 creation and nontransition opens remain v2. Support v3 only for the
explicit one-way migration. Extend NativeCloudBinding with optional Codable
properties (nil on v2): transportNamespaceID:UUID, verifiedClientIDs:Set<String>,
previousCanonicalIdentity:CanonicalIdentity, transition:EnvironmentTransition.
CanonicalIdentity contains containerIdentifier/environment/userRecordName.
EnvironmentTransition contains id:UUID, initiatedByClientID:String,
fromEnvironment:String, toEnvironment:String, occurredAt:Date. Use ISO8601 dates
for v3 encoding/decoding. Structural v3 validation requires every added field,
active Production and previous Development, exact same supported container,
valid nonplaceholder record names, nonempty verified subset of archive keys,
initiator GUI ID in the verified set and archives, matching provenance environments.
V2 must not accept nonnil v3 fields. Preserve all old token archive bytes.

Expose transportStateID computed v2.bindingID / v3.transportNamespaceID. Only
stateURL's identifier changes for v3; no cloud prefix/root format change. Version3
normal open checks known own token first, fetches target canonical only if client
is not verified; unknown matching client adds token+verified flag; known matching
but unverified retains token bytes and adds verified flag. Reread/merge protects
bindingID, namespace, canonical and provenance; changed known token never fetches.

Expose a typed NativeCloudError.environmentMismatch(source:String,destination:String)
only AFTER strict structural decode. Unknown/invalid runtime/provider stays a
separate unreadable error. A nonmutating migrationOffer reads the source under
CaptureSyncBridge lock, requires v2 Development, target Production and known GUI
own-token match, returning a ticket scoped to exact original bytes/bindingID,
clientID and target environment. Only the explicit GUI confirmation passes this
ticket to NativeCloudEnvironmentMigration.migrate; MCP cannot create a valid offer
because its actual clientID is not a GUI ID. Tests use fake providers with the
real allowed GUI client IDs. No general rebind API/boolean escape hatch.

Migrate snapshots exact bytes before network, fetches Production identity outside
lock, then reacquires/revalidates exact source and token/generation. Within that
transaction obtain validatedNativeRawSnapshot(), validate original state if present
using existing strict state decoder, create recovery snapshot and verify every
written byte. Manifest records explicit state absence, source schema, transition
UUID and file digests (not token/account identifiers in logs). Use CryptoKit SHA256
for verification. Snapshot path is besideEventLog/NativeSyncRecovery/<UUID>; root
and child0700/files0600, exclusive-create paths, no overwrite. Copy only eventlog,
source binding, preferences if present and old cursor if present; no audio/raw/repo
files. Verify before a single atomic v3 binding commit. Keep snapshots on all
failures and never auto-restore/delete. Invalid prefs/state/history or write failure
aborts unchanged active binding. Recovery closure injection is internal/test-only
and tests use synthetic corpora. No real corpus is migrated by verification.

New session isCurrentAccount also atomically reads a lightweight persisted binding
reference (UUID, version, canonical tuple, namespace) and compares with its original
reference. It never acquires CaptureSyncBridge, avoiding nested-lock deadlock.
Validate own token and generation at the same existing cloud IO boundaries. Real
cross-process publication already underway may finish append-only; local old state
and all raw cloud files remain recoverable. Public session initializer need not
allow bypass of these checks. Data snapshots contain private note history and remain
inside the app's local corpus folder, never clipboard/export/cloud.

UI source test count and capture receipt remain separate: do not silently assign
an unassigned voice note to Nuptia from text. A1 can verify its unassigned pointer
in all-project context and interpret the founder's literal Nuptia instruction.


### B1a — empty-deck guard (build-light)

Root review found the isolated deck's visible-range expression traps if its input
is empty. Replace inline range construction with computed visibleIndices:[Int],
returning[] when projects.isEmpty; select also returns immediately for empty input.
Keep all nonempty behavior unchanged. Only CaptureProjectDeck.swift. Verify
xcodegen, iOS Simulator build and diff check; root reruns independently. No new
storage or live tests. B1 UI interaction tests remain part of B2/P5 acceptance.


## B1 source checkpoint — 2026-11-02

Terra implemented project sleeves and the empty-deck guard. Root reviewed all four
source diffs and independently reran the generic iOS Simulator Debug build:
passed (`/tmp/unlirice-production-deck-root-build.log`). Xcodegen/diff check pass.
No app launched, no live connection changed. B1 interaction/accessibility/pose
acceptance is still pending the combined B2/P5 fixture run; no visual claim yet.
