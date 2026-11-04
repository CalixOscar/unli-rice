# PLAN — Capture startup recovery

**Planner:** codex
**Reviewer:** independent codex peer; Claude reviewer unavailable due weekly quota (recorded /private/tmp/capture-startup-peer-diagnosis.txt).
**Branch:** CalixOscar/Unli-rice-Capture
**Intent:** docs/intent/INTENT-012-production-studio.md; founder corrective instruction 2026-11-04: “fix it make no mistakes. Keep going until build 13 is submit for review”.
**Spec:** docs/SPEC-production-studio.md U2/U3/R1.
**Status:** settled correction; implementation authorized, submission awaits native cold-closed and ordinary-phone regression evidence.
**Founder skips:** none. Original approved intent explicitly requires ordinary phones/iPad to retain their full app.

## Evidence

Current CapturePresentation starts awaiting and voiceOnly hides all navigation.
Ordinary iOS 27.2 native probe receives no UIHingeInteraction callback at all,
including full-sized touch-enabled host, before-window installation, explicit
interaction enable and re-enable. Default enabled is true. SwiftUI onHingeChange
also emits no initial nil. These are runtime observations, not a promise for all OSes.
Baseline production-entry-point UI check reached hidden Settings with hit point
{-1,-1}; regression acceptance must require hittability and successful navigation.
Initial test was contaminated by a manual launch during its final Settings step;
use a new unattended baseline for causal acceptance, not this run alone.

Live ASC 2026-11-04: Capture 1.3(10) Ready for Distribution, latest upload10;
Mac1.5.1(13) is independent. Capture1.3.1 draft created; build13 reserved locally,
not uploaded or selected yet.

## Required outcomes

- Ordinary phone and iPad fresh install without Mac, account connection or sync:
  onboarding, local choice, Studio/Capture/To do and usable Settings, then relaunch.
- Actual Duo closed cold launch and fold after open expose voice controls only.
  Preserve known-hinge identity, lock precedence, recorder and form drafts.
- No model-name, screen-width, orientation or delayed-timeout inference of folding.
- Signed Capture/widget version1.3.1 build13, Production cloud, distribution archive
  provenance and upload verified; select13 and submit App Review, verify server state.

## Decision to settle

Ordinary-device absence does not produce the callback the original plan assumed.
Choose supported presentation semantics only after native Duo probe, explicitly
review any initial-state change against cold-closed disclosure and frame evidence.
No callback-enable-only patch is accepted as sufficient.

## Steps

P0 planner — diagnose actual ordinary/Duo behavior and settle correction with peer.
B1 build — bounded presentation correction and production-entry-point regression;
allowed files and exact behavior named after P0, independently rerun checks.
P1 planner — review diff, ordinary phone/iPad and native Duo acceptance, signature
and archive audit, App Store draft metadata, upload/select13/Submit for Review.
P2 planner — current-state memory, release receipt and post-mortem.

## Settled correction — 2026-11-04

P0: initial presentation policy is ordinary until actual hinge evidence. This is
not a claim to detect nonhinged capability. Ordinary devices emit no callback in
the native probe; waiting indefinitely is incompatible with approved intent U2.
Known hinged devices still fail closed on detachment/nil/unknown status. There is
no timeout or screen/model inference. Independent peer reviewed the two-line
correction and retained mandatory cold-closed first-frame acceptance before upload.

B1 — build-light: restore ordinary startup and ordinary reattachment.
Only Sources/UnliRiceCapture/CapturePresentation.swift may change. Change default
init mode from .awaiting to .ordinary; change detached() no-hinge branch from
.awaiting to .ordinary. Add a short comment that ordinary devices need not send
hinge updates and known hinged identities remain fail-closed. Do not change the
observer, callback guards, recorder, store, views, sync or other mode handling.
Verify git diff --check and generic iOS Simulator Debug build.

P1 acceptance includes first-frame record of actual production observer on native
Duo closed cold start, settled closed/open/reattachment, fresh ordinary navigation
and iPad. A detected privacy flash blocks release and returns to planner.

## Native acceptance failure and revised registration — 2026-11-04

B1 default-ordinary candidate FAILED native closed-start acceptance: onboarding
was visibly rendered on the closed outer display before the accepted hinge update.
Not uploaded. Its local archive is rejected. Phone/iPad navigation passed but cannot
justify release. Also rejected prototypes using a single main-queue completion or
viewDidAppear: native logs show both occur before the first hinge callback.

The native run-loop probe instead observed initial closed snapshot and queued
application before a one-shot CFRunLoopObserver at beforeWaiting/orderCFIndex.max.
Use that attached registration boundary rather than an elapsed delay. This is a
lifecycle policy, not a hardware-capability query or a guaranteed SDK callback order.

B2 — build: complete attached hinge registration safely.
Allowed only Sources/UnliRiceCapture/CapturePresentation.swift. Restore original
awaiting defaults/init and no-hinge detach awaiting. Unknown nil updates never
establish ordinary; known-hinge nil stays closed. Register disabled interaction,
enable only attached. Synchronously mark any accepted nonnil snapshot before
queued apply. Add one-shot main-runloop beforeWaiting observer with highest order;
on completion qualify generation/current window/exact interaction and check no
nonnil snapshot, awaiting and no known hinge before resolving ordinary. Remove the
runloop observer on invalidation; retain generation guards at callback and queued
application. No changes to store, recording, root or sheets. Actual app closed
cold-start frame recording and ordinary/iPad checks must pass before fresh archive.


B3 — build-light: retain production-entry-point UI regressions.
Allowed new Tests/UnliRiceCaptureUITests/StartupTests.swift and
Scripts/test-capture-startup.py only. Exact text supplied in
/private/tmp/capture-startup-tests-desired/. Runner generates isolated test project
outside repo, using current actual CaptureApp and all product sources, distinct
bundle ID and no injected presentation state. Modes ordinary, closed, open select
specific XCTest; native Duo pose remains real Device Hub control. Ordinary case
checks hittable onboarding/navigation/settings, typed local note and relaunch.
Verify git diff --check and python3 -m py_compile of runner (cache under /tmp).
Root independently runs tests; no product source or project changes in B3.


B4 — build-light: retry attached registration when its window becomes visible.
Peer post-build review identified a hidden→visible availability edge. Add only a
window-specific UIWindow.didBecomeVisibleNotification observer, scheduling the
same guarded registration boundary; remove it during invalidation. Exact text
supplied in the desired source. No relaxation of visible/active/hinge guards.
Verify git diff --check. Root reruns startup acceptance and rebuilds archive.
