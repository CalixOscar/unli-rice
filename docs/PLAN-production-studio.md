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
- [x] B1 — build: iOS project sleeve deck (U1). Allowed CaptureStudioView.swift,
  CaptureView.swift, new CaptureProjectDeck.swift and CaptureStore.swift (only the transient studioSelectedProjectID field). Pass Binding into Studio. Do not alter sync or recorder semantics.
  Verify signed-out fixture Simulator build and synthetic three-project UI checks.
- [ ] B2 — build: Duo presentation and workspace (U2–U4). Allowed CaptureView.swift,
  CaptureStudioView.swift, CaptureStudioStyle.swift, TodoView.swift, TypedNoteSheet.swift,
  CaptureProjectView.swift and new CapturePresentation.swift/CaptureVoiceControls.swift.
  Keep drafts and hierarchy mounted; shared folded/privacy cover applies to ALL
  presentations. Xcodegen, iOS build, normal phone/iPad/Duo pose UI verification.
- [x] B3 — build: account schema/transition core (S1–S3). Allowed core
  Sync/NativeCloudBinding.swift, NativeCloudIdentityProvider.swift, new
  NativeCloudEnvironmentMigration.swift; EventStore.swift (read-only snapshot only),
  NativeCloudTransport.swift (namespace only); focused migration/binding/transport
  tests and identity fixture. No changes to event fold or existing cursor bytes.
  Verify focused tests then root full suite.
- [x] B4 — build: explicit migration consent/status hosts (S1/S3). Allowed
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


## Stage1.5 / B2 attachment refinement (settled)

Astra read this intent/spec/plan at9257f29 and passed intent, identifying an
initial nil hinge callback ambiguity. The observation UIView installs/enables its
UIHingeInteraction only after joining a window. Tag each attachment with a fresh
generation; disregard callbacks unless interaction.view.window is that current
window and attachment generation still matches. Invalidate before removal or
willMove(nil), and recheck queued callbacks before applying state. Detached or
superseded callbacks never establish ordinary-device status. Until a valid
attached callback arrives, awaitingCallback stays voice-only. A valid attached nil
may establish standard navigation only if no hinge was ever observed. Once hinged,
retain that identity on detachment and show safe voice-only until reattached.
Cold already-closed launch and attach/detach/reattach are explicit QA cases.

B2 keeps the known-hinged workspace hierarchy mounted in EVERY pose: switching
closed/open changes covers, not conditional creation of Studio/Todo subtrees.
ArrangementView adapts their layout without reparenting state. Each presented
sheet root shares the environment presentation state and folded/privacy cover;
keep content mounted underneath, large detent when closed, restore on open. End
editing on the affected window to hide keyboard, without clearing draft strings.
Use an INTERNAL CaptureView initializer to inject a fake presentation model for
isolated QA; retain the existing public init(store:) signature. Never build a real
store as an environment fallback in fixture views. Folded voice controls support
existing recording mode/pause/resume/stop/transcription states, omit typed/history/
project/to-do content. The currently selected project may be named as voice context.
B2 compilation waits while B3 edits shared core source, to avoid mixed snapshots.


## B3 public authorization boundary (settled clarification)

Migration's PUBLIC offer(eventLogURL:isValid:) and migrate(offer:isValid:) entry
points accept NO provider/clientID parameters. Each obtains a fresh
LiveNativeCloudIdentityProvider internally and checks actual Bundle.main GUI
identity before using it. Opaque public Offer has internal construction, private
source bytes/corpus path/issued client/target scope; migrate verifies that same
actual process identity and source scope again. Offer binds the corpus URL, so
migrate has no independently supplied alternate corpus URL. Internal injectable
methods exist only for @testable synthetic fixtures, not as public API. Normal
binding provider injection may remain public for existing callers/tests; it is not
an authorization boundary for environment migration. No MCP dispatch route exposes
migration, and actual .mcp bundle cannot obtain or consume a public offer.

## B2a review corrections (build)

Root host Simulator build passed, but source review found remaining UI issues.
Hide legacy Page picker for known-hinged workspace (both panes are already shown).
Welcome splash and initial folder-choice prompt stay deferred while voice-only,
locked or captureInFlight; retain pending flags so they appear on opening only
when appropriate, rather than dropping setup state. Folded pause/resume/save
controls have44pt minimum hit targets; disable mic while transcribing. Preserve
all active recording state. Only CaptureView.swift/CaptureVoiceControls.swift.
Rerun host build/diff check; pose/draft/accessibility QA still pending.


### Q5 — build: isolated UI verification harness

Allowed only /tmp/unlirice-production-ui-qa/**. Generate a separate QA app bundle
and UI-test target, compiling Capture sources except CaptureApp with synthetic
local store/project snapshots (three generic projects, pending capture, todo).
No production bundle ID, app group entitlement, real iCloud, real note copies,
phone data or MCP substitution. Internal presentation injection disables observer
for deterministic mode tests; hardware mode uses public init(store:) and realhinge.
QA launch flags exist in the QA-only host, never production source. Test buttons
for synthetic pose state changes live only in QA host overlays and are excluded
from production screenshots/acceptance; real Device Hub poses remain separate.

Test deck boundaries/swipes/selection refresh, closed voice-only/noWorkspace,
open Studio+Todo, fold/unfold selectedID and typed/todo drafts, synthetic recording/
paused/transcribing state retention, locked covers, ordinary phone/iPad, Dynamic
Type and Reduce Motion. Screenshots are actual QA app artifacts, no generated art.
AppLock configuration if needed stays in QA host defaults, not a production bypass.
Prepare project/tests and xcodegen first; compile/run only after CORE STABLE.
Use a NEW disposable Duo simulator and existing explicitly disposable Capture
Studio QA simulator, never erase or install over founder's existing Duo device.
Synthetic recorder-state checks do not establish physical microphone continuity.


### B2b — opened-workspace typed capture access (build-light)

Q5 found no route to a new typed note in opened Duo. Preserve existing Type instead
button by adding `else { typeNoteButton }` after the duoWorkspace in-flight recorder
condition. Only CaptureView.swift; no new sheet or draft state. This supplies the
full opened app and lets Q5 open a real typed editor before folding. QA initializes
presentation.open first (hasSeenHinge true), then changes closed/open; it does not
fake a hinged device by starting ordinary and setting mode alone.

B3 focused root verification:38tests,0failures
(/tmp/unlirice-production-migration-root-focused.log). External Claude code review
was automatically rejected as private-source disclosure; founder was asked to
approve that limited payload or keep review inside Codex. Do not bypass rejection.
No new release/post-mortem acceptance is claimed from these tests.


### B3a — build: retry-safe migration recovery (settled)

Founder explicitly approved external Claude source review: “Keep going and yes you
can send to claude”. Authorized source-only review identified fixed transition
recovery-directory collisions after interrupted writes. Use a fresh attempt UUID
for EACH recovery snapshot, directory <transitionUUID>-<attemptUUID>, manifest
records both IDs. Retain partial copies; never overwrite, resume or delete them.
The binding transition ID remains stable for idempotent repeated consent ticket.
Exclusive recovery files are fsynced before closing; fsync snapshot directory and
recovery root before binding commit; fail closed if durability check fails. This
does not claim a global freeze of concurrent append-only event writers.

Reject v3 transport namespace equal to binding ID. Address Data slice indices
relative to startIndex. Keep exact-source binding guard: concurrent enrollment
requires a fresh offer, never implicitly merges changed account archives. Add
regressions for failure at each snapshot/manifest boundary then same-offer retry,
helper consuming a valid GUI offer, cancellation before commit, token change
during lookup, append between offer/migration included in recovery, namespace
alias rejection and nonzero-index Data state validation. No host UI or live data
changes in this step. Allowed migration/binding/transport core files and their
three focused test files only. Verify focused tests and diff check.


### B4a — build: Mac explicit migration consent/status host

Only AppStore.swift, AppStore+NativeSync.swift, ConnectView.swift. Track typed
Development→Production mismatch separately from status strings. Show a recovery
action only for that mismatch. Clicking it invalidates native generation/discovery
and asynchronously obtains the public nonmutating Offer, serialized by existing
nativeWorkLock and protected security-scoped corpus access. Publish confirmation
only after offer succeeds. Store opaque offer privately; no token/record text UI.

Confirm text: “Move this device to the released iCloud connection?” Message:
“Your notes stay on this device, with a recovery copy. Notes, transcripts, to-dos
and project summaries will sync with the same Apple account. Other devices may
need this update too. Recordings and repositories stay local.” Buttons Continue
and Cancel. This confirmation is separate from ordinary Enable/Retry; never
migrate automatically. Cancel discards offer, leaves binding/preferences/events
unchanged, remains paused.

Confirm captures offer, invalidates generation again, runs public migrate with
that generation/corpus checks and existing work lock/security scope. Busy/offered
state suppresses timer sync; disable duplicate actions. Completion must still
match generation, corpus URL, iCloud mode. On success clear mismatch, reload local
projection, resume ordinary sync. On failure remain paused with error, no deletion
or resets; fresh explicit action obtains a fresh offer. Account/folder/mode change
and invalidate cancel work, discard offer, dismiss confirmation. Migration task
uses existing nativeTask ownership; no extra untracked task. Verify macOS build
and diff check. Capture host is a separate B4b step after UI review fixes.


### B2c — build: folded and locked accessibility isolation

Q5 rerun reached editors after moving its overlay. Closed workspace still exposed
Projects, locked closed exposed Record, and locked presented editor exposed its
TextView in XCTest accessibility queries. Preserve mounted draft hierarchy but
explicitly set accessibilityElement(children: .ignore) plus accessibilityHidden
for covered workspace/root/sheet content; use .contain when uncovered. Keep
allowsHitTesting false under covers. CaptureVoiceControls owns no draft state;
observe AppLock and omit its entire controls subtree while locked, so Record
cannot survive beneath lock. Root and sheet opaque lock overlays keep precedence.
Type instead hit target gets minHeight44. Only CaptureView.swift,
CaptureStudioStyle.swift, CaptureVoiceControls.swift. No recorder/store/lifecycle
changes. Verify iOS build/diff then Q5 rechecks actual absence, never weaken tests.
Full core suite independently passed633, skipped2, failures0 after B3a.


### B4b — build: Capture explicit migration consent/status host

Only CaptureStore.swift and CaptureView.swift, preserve B2c covers. Same typed
mismatch and explicit request/confirmation as B4a, exact same copy. Keep private
Offer and tracked migration task; invalidateNative cancels/discards migration
state with the existing generation. Introduce a host native work lock to serialize
existing native sync with offer/migrate; keep all locking in detached synchronous
work and never on MainActor. Core generation checks still gate commit.

finishNative carries Error rather than lossy string so it can detect only typed
Development→Production mismatch. Native sync/retries suppressed while mismatch,
migration busy or offer pending. On confirmation success maintain/rebuild local
projection then resume ordinary sync; failure remains paused. Preference/mode/
account invalidation cancels work without touching binding or events. Preserve
recorder, drafts and selected project. Settings action disabled while locked,
voice-only or migration busy. Confirmation is attached to settings sheet root,
visible only when open/unlocked; fold/lock discards pending offer and dismisses
confirmation. Already confirmed work may complete under normal generation checks;
fold is not an account change. No automatic migration on retry/startup.

Verify iOS host Simulator build and diff check; Q5 fixture tests must later cover
visibility/cancellation where feasible without real cloud. No live-store test
bypasses or production launch flags.


### B4c — build-light: modal migration confirmation

Review found confirmationDialog outside-tap dismissal can strand Capture's opaque
offer while visible state is false. Avoid ordering-dependent deferred cleanup or
a second consent-ticket slot. Use SwiftUI .alert for migration confirmation only
on both platforms, same exact text/buttons; modal alert has explicit Cancel and
Continue rather than iPad popover outside-tap dismissal. Existing invalidation
and Capture fold/lock cancellation remain. ConnectView.onDisappear discards
pending offer. As fail-closed recovery, a fresh Capture request may clear an
existing unpresented offer before obtaining a fresh one (never migrate it).
No generation/canonical/source safety changes. Allowed ConnectView.swift,
CaptureView.swift and CaptureStore.swift only; verify both host builds/diff.


### B2d — build: owned UIKit privacy boundary for presented content

Astra reviewed B2c's remaining UIKit-backed TextView hierarchy membership. Retain
root workspace boundaries; put ONLY CapturePrivacyCover private content in stable
CapturePrivateContentHost<Content>: UIViewControllerRepresentable. Its owned
container owns one UIHostingController<EnvironmentBridge<Content>>, attached once
with proper child containment and pinned edges. Capture @Environment(\.self) at
mounted modifier/representable, apply full captured EnvironmentValues with
content.environment(\.self, values) in stable bridge, update same concrete root
type. SDK/typecheck verified writable self keypath forwards read-only dismiss
and environment objects; no default/new environment bag, no injected fake dismiss.

When concealed call endEditing(true), set owned container view accessibilityElementsHidden,
isUserInteractionEnabled=false and hosted child view.isHidden=true. Keep it mounted
and size unchanged; reveal reverses flags. Voice/lock overlays remain siblings
outside boundary. No ancestor/window scanning, conditional controller creation,
.id reset, or sheet dismissal on fold. Fill sheet frame; sizingOptions=[]; optional
sizeThatFits returns finite full proposed size only, otherwise nil. All callers
are full-sheet NavigationStack/NavView content; no intrinsic sizing feedback.

Allowed new CapturePrivateContentHost.swift and CaptureStudioStyle.swift only.
xcodegen generate then iOS host build/diff. Q5 must check two fold/open cycles,
draft preservation, keyboard removal, concealed editor/sentinel absence, lock,
Cancel/Save dismissal, voice/unlock accessibility. Native containment keeps draft
identity; runtime verification remains mandatory. XCTest exists alone is hierarchy
membership, not proof of actual VoiceOver disclosure. Do not overstate evidence.


### B4d — build: Mac preparation lifecycle cancellation

Claude source review identified pane-disappearance while offer preparation is
busy. Track nativeMigrationConfirmed on Mac (false on invalidate, true only after
Continue consumes offer, false on valid completion). cancelNativeMigration guards
!confirmed, discards any offer, and if preparing/offered/presented invalidates
native generation/task then restores typed mismatch pause. ConnectView calls this
unconditionally onDisappear. Confirmed migration is unaffected by pane navigation,
but account/mode/corpus changes still invalidate. No deferred cleanup or extra
consent slot. Allowed AppStore.swift, AppStore+NativeSync.swift, ConnectView.swift.
Mac host build + diffcheck, root review. Mismatch after Cancel deliberately stays
paused; explicit Retry rechecks it, Move prepares fresh offer, account observers
invalidate stale pause. No automatic binding rewrite.


### B1b — build: exclusive project flip and open gestures

Q5 diagnostic proved Beta→Gamma swipe also opened Beta detail (before reverse
gesture screenshot already shows detail). Card Button tap recognizer coexists with
parent simultaneous DragGesture, causing dual action. Replace card Button with
its sleeve view and a single exclusive gesture composition per card: DragGesture
(minimumDistance40).exclusively(before: TapGesture()), attached simultaneously
so parent vertical scrolling remains possible. On first result, only horizontal
dominant translation selects neighboring front; on second result run existing
tap behavior (front opens, future peek selects). Remove duplicate parent drag.
Keep accessibility button trait, explicit action performing same tap behavior,
existing identifier/label, adjustable action and44pt arrows. No draft/sync/recorder
changes. Only CaptureProjectDeck.swift. Build then Q5 verifies swipe does not open
detail, reverse swipe and tap still open expected project, selection refresh/fold.


B1b1 review correction (build-light): replacing Button exposed multiple sleeve
children with inherited button trait/identifier. Insert
`.accessibilityElement(children: .ignore)` on sleeve before button traits/actions
and explicit label/identifier, producing one semantic button per front sleeve.
Only CaptureProjectDeck.swift. Retain Q5 single-match selector; do not mask
duplicates with firstMatch. Generic Simulator build/diff and deck UI recheck.


### B2e — build-light: combined hosted SwiftUI accessibility exclusion

Astra verified synthetic native probes: same editor identity and draft through two
folds; concealed actual native ancestors hidden/AXhidden and interaction disabled,
firstResponder false. Plain UIKit calibration disappears from XCUI query, so
claim that XCTest always includes hidden UIKit is unsupported. Remaining SwiftUI
snapshot projection is hypothesis, not proven VoiceOver disclosure. Restore BOTH
layers: add concealed Bool to stable CaptureEnvironmentBridge, pass from host
at all construction/update sites. Its body applies content.accessibilityElement
(children: concealed ? .ignore : .contain).accessibilityHidden(concealed)
.allowsHitTesting(!concealed).environment(\.self,values). Keep UIKit concealment,
root concrete type and mounted identity unchanged. Only CapturePrivateContentHost.swift.
Build/diff then strict editor/sentinel absence plus identity/draft/dismissal checks.
If this fails stop source changes again, inspect actual AX projection/VoiceOver;
no speculative modifier accumulation or assertion weakening.


Q5 privacy investigation gate after B2e: strict concealed-editor query still fails,
while native flags/identity/drafts and opaque lock screenshot pass. STOP production
changes. Astra says cross-host ViewModifier.Content proxy hypothesis is plausible
but unproved. QA-only matched A/B: identical synthetic concrete editor + NavigationStack
in identical sheet, environment and overlays, (A) current .modifier(CapturePrivacyCover())
proxy path, (B) same concrete view directly in CapturePrivateContentHost under a
QA-only copy of exact overlay/conditions/detents. Never change content identity
while folding; vary launch choice only. Include ordinary SwiftUI TextEditor native
visibility calibration. Two folds/dismissal, exact hierarchy/value/native flags/
identity/keyboard/hit-test and screenshots. If concrete succeeds and proxy fails,
settle explicit generic wrapper design before builder touches production. If both
fail, inspect Accessibility Inspector/actual VoiceOver, no speculative rewrite or
assertion weakening. Only existing /tmp Q5 harness files may change.


## Current verification gate — 2026-11-02

Root final combined Capture build passed (/tmp/unlirice-production-capture-root-final-local.log),
Mac rootbuild passed; core633tests2skipped0failed. Q5 currentstrictsuite6of9pass:
deckboundary/swipe/tap/selection, large type, ordinaryphone, closedvoice, lockedclosed,
syntheticrecordingstates. Three concealed editor.exists assertions fail; all3 separate
native/draftdiagnostics pass. iPadordinary1of1pass. Real DeviceHub public-init cold
closed/open/partiallyopen/editorfold/reopen/finalclosed callbacks observed by root.
No physical mic or actual VoiceOver acceptance. B2 and P5 remain open.

Matched proxy/concrete A/B both failstrictqueries identically but preserve draft
identity2folds/Cancel/nativehidden+AXhidden/no keyboard/no hit. Ordinary SwiftUI
TextEditor with opacity0/accessibilityHidden/nohit remains queryable in XCT, even
reports hittable; plain UIKit calibration disappears. Root inspected harness: hidden
state is @Published, not a missing observation bug. This does not prove actual
VoiceOver disclosure or justify a proxy-only rewrite. Evidence under /tmp/unlirice-
production-ui-qa/{attachments-ab,native-ab,result-ab.xcresult,ab.log}. Source changes
STOP pending independent Accessibility Inspector/actual VoiceOver verification.

Root launched Accessibility Inspector and selected synthetic QA process only;
no element traversal obtained. CUA DeviceHub pointer click failed windowNotFound;
WindowFill then caused ScreenCaptureKit -3812 invalid-parameter on all DeviceHub
reads, including rebind/reset. Other apps remain accessible. Asked founder to reopen
DeviceHub. QAapp remains synthetic fixture, current unsaved draft marker typed by
root is Inspector draft sentinel; CaptureKeyboard toggled on in QAviewer. No real
notes/accounts/apps changed. AppStoreConnect browser session also expired at
authResult=FAILED; founder asked to sign in. Capture latest9/1.3 was read immediately
before expiry, Maclatest12 only priorverified context, must recheck before counters.
No speculative release bump, archive/upload or live migration. Original purple
lantern targeted MCP search remains empty.


### B6a — build-light: Mac candidate counters after live check

Founder restored browser and DeviceHub, then requested “just use Terra until done”.
Live ASC Nov2 confirms Mac1.5latest12, Capture1.3latest9. Mac source/consent/core
checks pass independently of Capture's unresolved AX gate. Prepare Mac-only
candidate13 for signed local capture/MCP acceptance; no public submission or
Capture upload approval inferred from this preparation. Change exactly three Mac
CURRENT_PROJECT_VERSION12 values to13 (MCP, widget, app); keep marketing1.5 and
Capture9 unchanged. project.yml only; xcodegen generate, show Release buildsettings
for version/env, diffcheck. Root archives/verifies candidate and reviews resulting
build/runtime before any installation/upload. Capture AX verification continues
on Terra; no speculative privacy-source changes.


B6a verification: exactly3 Mac counters12→13, Capture9unchanged; generatedproject
and Release settings pass. Root signed Mac archive succeeded at
/tmp/unlirice-studio-mac-candidate-13/UnliRice.xcarchive. Host deepstrict signature
passes, all5executablesuniversal, app/MCPProduction cloud entitlements/correctgroup/
container/no taskallow. Widgetmatches13/group-only. Terra independent read-only
review found no new source issue; sandboxtrusterror differs from passinghostcheck.
No install/upload/submission yet. Source checkpoint candidate can support Mac
runtime acceptance while Capture's separate AX gate remains unresolved.


### Mac candidate 13 distribution checkpoint — 2026-11-02

The candidate archive remains at /tmp/unlirice-studio-mac-candidate-13/UnliRice.xcarchive.
Xcode GUI lookup by name and bundle ID hung and was aborted without any action. One
host CLI export with automatic signing and provisioning updates failed exit 70:
“Failed to Use Accounts”; App Store Connect access for team 22SNGN5JYD is required
in Accounts settings. No upload or installation was verified. Log:
/tmp/unlirice-studio-mac-candidate-13-export.log. Restore Xcode Organizer/account
access before retrying; do not replace the installed App Store app with the
development-signed archive. Independent Capture accessibility and real receipt
gates remain open. ASC previously showed 1.5 build 11 waiting for review with
automatic release; founder subsequently reported it went live, not independently
verified at this checkpoint. Founder authorized review withdrawal if still possible,
not removal from sale.

### B6b — build-light: Mac public update version after 1.5 release

Fresh ASC read confirms 1.5 (11) Ready for Distribution; it can no longer be
withdrawn from review. Use 1.5.1 (13) for the next Mac update. In project.yml
change exactly the three Mac MARKETING_VERSION values 1.5→1.5.1 for MCP,
widget and app. Keep their build counters 13 and both Capture targets 1.3 (9).
No other edits. Run xcodegen generate, verify generated Release settings and
`git diff --check`. Root reviews before archiving; old 1.5 (13) archive remains
an unuploaded candidate, not the public update archive.

Mac 1.5.1 (13) archive succeeded at /tmp/unlirice-studio-mac-151-13/UnliRice.xcarchive; host deep/strict codesign verification passed. This is development signed, not uploaded or installed; Apple-managed distribution export remains blocked by Xcode account access. Capture remains 1.3 (9).


### Installed Mac migration and capture receipt — 2026-11-03

ASC shows Mac 1.5.1 (13) Ready to Submit in existing Family test group;
TestFlight update installed and opened. Founder explicitly approved moving the
existing development binding to the released iCloud connection and reading Nuptia
context for receipt verification. GUI offer described an on-device recovery copy;
Continue completed and the app reports iCloud sync on. Original human capture
80688A57-D1ED-4DA6-9AD7-DA9C498BB888 is present unassigned in installed-store
search and fresh installed-helper project context. No conversion to a to-do.
Existing registered MCP process reported unsupported binding v3; fresh installed
helper accepts it and reports no sync error. Reconnect the old session helper.
Claude runtime, physical microphone/phone production sync and independent Capture
accessibility remain unverified; no public review submission. Minimal fresh-helper
check: /tmp/unlirice-fresh-helper-check.py and /tmp/unlirice-fresh-helper-check.log.
