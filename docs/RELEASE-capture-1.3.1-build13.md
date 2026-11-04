# Capture 1.3.1 (13) — startup recovery release

Founder instruction: “fix it make no mistakes. Keep going until build 13 is submit for review”.
Scope: restore standalone navigation on ordinary phones/iPad, preserve actual Duo
folded recording presentation, submit corrected Capture build13 for public App Review.
Mac build13 is independent; do not mutate its existing review submission.

## Product premortem (release gate)

Context: free private voice/text capture with local transcription and optional Mac
sync. Audience wants immediate thought capture and recoverable local notes. No
pricing/paywall/monetization change. The reported real failure is a mic-only dead
end before onboarding/settings, even when no Mac connection is expected.

1. Intent versus reality: adding a folding-device optimization obscured the core
   value for ordinary phones. Empty synced projects must not hide the product.
2. Distribution/friction: discovery is irrelevant if the first launch blocks all
   navigation. Acceptance begins with a disconnected fresh install, then local
   note save/relaunch; compilation alone cannot establish usability.
3. Conversion: this free app still charges cognitive cost. Do not require iCloud,
   Mac setup or unexplained device terminology before local use.
4. Blind spots: the original plan assumed an initial nil hinge callback on ordinary
   hardware. Native runtime contradicts it. Synthetic mode fixtures and exists-only
   accessibility queries failed to catch the real dead end.
5. Lessons: test actual entry points; require hittable/working controls; treat native
   closed-start frames as a release gate; keep upload and review receipts distinct.

## Corrective design and reviewed limitations

Initial awaiting remains concealed. Attach/enable a public UIHingeInteraction,
retain any accepted nonnil snapshot synchronously, and complete no-hinge registration
at the end of an attached active-scene main runloop. Ignore unknown nil, preserve
known-hinged closure and cancel stale registration/callback work. This is tested
runtime lifecycle policy, not a public capability query or a universal API timing
promise. No model names, widths, orientation guesses or elapsed timeout.

The first default-ordinary candidate was rejected after native cold-closed onboarding
flash. Its archive /private/tmp/capture13-release/UnliRiceCapture.xcarchive is NOT
eligible for upload. Final candidate path is UnliRiceCapture-registered.xcarchive
in the same directory, rebuilt from B2 source. Do not confuse them.

## Evidence collected so far

- Unattended baseline: /private/tmp/capture-startup-regression/baseline-clean.xcresult
  fails ordinary startup; screenshot exactly matches reported mic-only screen.
- Initial B1 phone/iPad pass was insufficient; closed native flash rejected it.
- B2 actual entry-point navigation: registration-fix.xcresult passes on ordinary
  phone and iPad (two destinations). Stronger persisted tests add typed-note save
  and relaunch; results pending.
- B2 final native closed cold-start recordings closed-full-1/2/3.mp4 under
  /private/tmp/capture13-qa, frame/privacy audit pending. No injected pose state.
- Final signed archive build passes; signature/production entitlement audit pending.
- ASC live inventory observed Capture1.3(10) Ready for Distribution, latest upload10.
  New1.3.1 draft exists; correction release notes saved, automatic release inherited.
  No13 upload or review submission yet.

## Existing unrelated limitations

No new physical-device cloud transfer claim, full VoiceOver sign-off or resolution
of the prior draft screenshot task. No cloud/account/reset/data migration changes
are included in this startup correction. Existing outstanding items remain open.


## Final B4 acceptance checkpoint

Same-window visibility retry accepted by peer, and actual observer probe passes
initial ordinary, hidden active-scene awaiting, visibility retry, visible reattach
and absence of synthetic hinge identity. Final ordinary phone/iPad note-save tests
and native open/closed tests pass (verified: final-ordinary.xcresult,
final-native-open.xcresult, final-native-closed.xcresult; lifecycle runtime.log,
2026-11-04). Final video OCR pending.

FINAL archive is /private/tmp/capture13-release/UnliRiceCapture-final.xcarchive
(B4). The -registered archive above is superseded by this visibility correction.
Root independently verified deep/strict signature, Capture+widget1.3.1(13),
NativeCloudEnvironment Production and production cloud entitlement. Archive is
development signed; managed distribution signing is performed in Organizer.
Xcode cloud-managed validation succeeded for the preceding B2 candidate; final
B4 upload validation remains to verify. No source change after final build.

Chrome and the existing Connect web app are both at owner login; a sign-in request
is pending. No App Review success is claimed.


## Final receipt — uploaded, browser login gates review

Code matches1e178ef. Final B4 phone/iPad local-note persistence, native open and
three cold-closed launches pass. Actual observer hidden/visible/reattachment probe
passes. Final native recording has482 encoded frames: ALL visually reviewed in
contact sheets1–8, with only launch cover/voice controls/system transitions. Apple's
text-recognition checker stalled on its semaphore (sample saved) and was deliberately
stopped; final visual audit, not an OCR pass, is the evidence. No source changes
followed final archive. Source/config manifest138 inputs remains exact.

Organizer: “UnliRiceCapture1.3.1(13) uploaded”, build number13,09:28Asia/Manila.
ContentDelivery: “UPLOAD SUCCEEDED with no errors”. Actual distribution app/widget
pass deep/strict signature, version1.3.1/build13, team22SNGN5JYD, get-task-allow false;
app environment Production. Uploaded executable UUIDs match final archive. Signed
IPA preserved at /private/tmp/capture13-release/UnliRiceCapture-1.3.1-13.ipa.
Machine-readable receipt: docs/qa/capture-startup-build13.json.

NOT submitted for App Review. Both Chrome and existing Connect web app are at
owner login; sign-in request is pending. After login inspect processing/eligibility,
select13 in1.3.1 draft, save, submit and verify server review state and submission ID.
No implicit success from upload, no need to re-upload a successful build.


## App Review submission receipt

On 2026-11-04, App Store Connect confirmed version 1.3.1, build 13,
was submitted: “1 Item Submitted” and “Waiting for Review”. Submission ID:
bda33754-5e0d-4223-8e37-d246f3ef75c6. Automatic release and immediate
release to all users were selected. The earlier login-blocked status above is
superseded by this receipt; Apple approval and public release remain pending.
