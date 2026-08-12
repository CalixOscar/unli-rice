# Handoff plan: Unli Rice Capture → free iOS App Store release

> **Superseded pricing decision, 2026-08-09.** This plan was written for a paid
> release. The founder decided the same day to ship Capture **free, MIT, and open
> source like the macOS app**. The engineering phases below are unchanged — every
> blocker in Phase 1 blocks a free release exactly as hard — but the commercial
> framing throughout has been updated, and three things are now dead:
> the App Store Bundle with Unli Disk (bundles require every app in them to be
> paid), the price-anchor problem against Just Press Record at $6.99, and the
> no-trial friction. The pre-launch post-mortem that produced this reversal is
> summarised at the end of this file.

**Audience:** ChatGPT (GPT-5.6 Sol), the execution engine. Phases 1, 3, 4 and 6 are
mechanical with binary verification. Phase 2 is not — see its own note.
**Authored by:** Claude Code, 2026-08-09, at the founder's request.
**Branch:** `feature/folder-first` is currently checked out and carries unrelated UI
work. Do this on a fresh branch off `main`: suggested `feature/ios-paid-release`.
**Source of truth:** `project.yml`. The `.xcodeproj` is gitignored and generated —
run `xcodegen generate` after every spec edit, before building.

> **Shipping rule — no exceptions.** Do not upload, submit, archive for distribution,
> or bump the version of any studio app while executing this plan. Every phase below
> stops at "builds and validates locally". `UnliDisk/PROJECT_NOTES.md:23-28` records a
> session that read handoff wording as a work order and uploaded an unauthorised build.
> Phase 6 is founder-only and is listed for completeness, not for you to perform.

---

## Gate 0 — the pre-launch post-mortem (founder, before any of this)

`_AI Context/04_Guardrails.md` requires that a shipping signal triggers an offer to run
the 6-Month Post-Mortem in `_AI Context/07_Prelaunch_Post_Mortem.md` before Submit for
Review. "Release it for a price" is that signal. Every base in that note should be
covered before Phase 6. It is not a blocker for Phases 1–5, which are code.

**Run and acted upon, 2026-08-09.** Its finding was that a paid Capture record charged
for the on-ramp to a free product, and lost on every visible axis to Just Press Record
($6.99, one-time, unlimited length, on-device transcription, iCloud Drive folder) while
its actual differentiator — the memory loop — is invisible in App Store screenshots. The
outcome is the free/MIT decision at the top of this file. Gate 0 is therefore **closed**;
it does not need re-running before Phase 6 unless the pricing decision changes again.

One finding that survives the pivot: **`IPHONEOS_DEPLOYMENT_TARGET` is 26.0**, forced by
`SpeechAnalyzer`, which was chosen deliberately because `SFSpeechRecognizer` cuts off on
a pause. That still limits the installable base at launch. It matters less now that no
one is being asked to pay — but do not "fix" it by reverting to the legacy recognizer,
which would undo the reason the app exists.

---

## Phase 1 — make the build uploadable

Four hard blockers, verified against the built bundle on 2026-08-09, not inferred from
the spec. Reproduce the evidence yourself before and after:

```bash
xcodebuild -project UnliRice.xcodeproj -scheme UnliRiceCapture -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO
plutil -p ~/Library/Developer/Xcode/DerivedData/UnliRice-*/Build/Products/Release-iphoneos/UnliRiceCapture.app/Info.plist
```

Today that bundle contains only `Info.plist`, `Metadata.appintents`, `PkgInfo` and the
binary — no icon, no privacy manifest, no version keys.

### 1.1 Version keys — upload fails without these

`MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are set on the `UnliRice` macOS target
(`project.yml:176-177`) and on no other. Add both to the `UnliRiceCapture` target's
`settings.base`. Start at `1.0` / `1`.

**Verify:** `CFBundleShortVersionString` and `CFBundleVersion` appear in the dumped
plist. They do not today.

### 1.2 App icon — validation fails without it

The target has no `resources:` block and no asset catalog at all. The only icons in the
repo are macOS sizes under `Sources/UnliRice/Resources/Assets.xcassets`.

- Create `Sources/UnliRiceCapture/Resources/Assets.xcassets/AppIcon.appiconset` with a
  single 1024×1024 entry (`"idiom": "universal"`, `"platform": "ios"`). Modern Xcode
  needs only the one size.
- Add to the target: a `resources:` source entry mirroring how the macOS target does it
  (`project.yml:150-152`), plus `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`.
- **Interim art:** `Sources/UnliRice/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`
  is 1024×1024 with **no alpha channel** (verified), so it is directly legal as an iOS
  icon. Do not source from `dist/master_icon.jpg` — `dist/` is gitignored.
- **Flag for the founder, do not decide yourself:** this is a separate paid App Store
  record, and shipping it with the Mac app's icon is an ASO decision, not a build
  detail. Ask whether Capture gets its own mark.
- `Scripts/make-icons.sh` is macOS-only and hardcodes the macOS catalog path. Do not
  extend it for one file; write the `Contents.json` by hand.

**Gotcha:** iOS rejects icons with an alpha channel. If new art arrives, check it with
`sips -g hasAlpha <file>` before wiring it up.

### 1.3 Privacy manifest — upload fails without it

The macOS target ships `Sources/UnliRice/Resources/PrivacyInfo.xcprivacy`; the iOS
target has none. Capture uses the same required-reason APIs: `UserDefaults` (CA92.1) and
file timestamps (C617.1, 3B52.1). Copy the macOS manifest to the new Capture resources
directory. It needs no edits — `NSPrivacyTracking` false and an empty
`NSPrivacyCollectedDataTypes` are both still true for the phone app, which transcribes
on device and has no account.

**Verify:** `PrivacyInfo.xcprivacy` appears inside the built `.app`.

### 1.4 Encryption declaration

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption: NO` is set on macOS (`project.yml:181`)
and missing on iOS. Not fatal — it just prompts on every upload. Add it.

### 1.5 The Files-app key that silently does nothing — **DONE 2026-08-09**

`INFOPLIST_KEY_UIFileSharingEnabled: YES` is in `project.yml` **and** in the generated
pbxproj, and does **not** reach the built `Info.plist`. Xcode 26 does not map that
setting; `LSSupportsOpeningDocumentsInPlace` next to it does come through. So the intent
— on-device captures reachable from the Files app — is not happening today.

Fix by giving the target a real Info.plist file (`UnliRiceCapture-Info.plist`, alongside
the existing `UnliRice-Info.plist`) carrying `UIFileSharingEnabled`, and setting
`INFOPLIST_FILE` on the target. Keep `GENERATE_INFOPLIST_FILE` semantics in mind: once
you supply a file, the `INFOPLIST_KEY_*` settings still merge into it, so the mic and
speech usage strings can stay where they are.

**Verify:** `UIFileSharingEnabled => true` in the dumped plist. Then confirm on a device
or simulator that "Unli Rice Capture" appears under Files → On My iPhone.

**Done.** `UnliRiceCapture-Info.plist` now exists at the repo root and is wired via
`INFOPLIST_FILE`; it also carries `UIBackgroundModes: [audio]` (see 1.7). Both keys are
confirmed present in the built plist, and the `INFOPLIST_KEY_*` usage strings still merge
into it. The remaining device check — Files → On My iPhone — has not been done.

### 1.7 Recording length has no cap — **DONE 2026-08-09**

`Recorder.record()` was already called without `forDuration:`, but three things outside
that call ended long recordings anyway. All three are fixed in
`Sources/UnliRiceCapture/Recorder.swift`:

- **Screen auto-lock**, the invisible one. Tap record in `tapToToggle` mode, set the
  phone down, and iOS locked after ~30 seconds and suspended the app mid-recording.
  `UIApplication.isIdleTimerDisabled` is now held for the duration of a recording and
  released in `stopRecording()`.
- **Backgrounding.** `UIBackgroundModes: [audio]` lets a recording survive the user
  switching apps or locking deliberately.
- **Interruptions.** A call, Siri, or another app claiming the mic stopped the recorder
  while the UI went on saying "Recording…". `AVAudioSession.interruptionNotification` is
  now observed; the recording pauses and resumes into the same file when the system
  offers `.shouldResume`, and `Recorder.onInterruption` reports whether it did.

**Not yet wired:** `CaptureStore` does not consume `onInterruption`, so a
non-resumable interruption still leaves the UI in `.recording`. Wire it to set
`.error` or `.completed` with an honest message. Also consider showing elapsed time
while recording — there is currently no way for a user to see how long they have been
talking, which matters much more once recordings can run for hours.

The only cap left anywhere in the app is the Action Button intent — see Phase 3.

### 1.6 Decide iPad, deliberately

`TARGETED_DEVICE_FAMILY: "1,2"` puts iPad in scope: iPad screenshots become mandatory
and a reviewer will test on iPad. Nothing in `CaptureView` is iPad-designed — it is a
single-column phone layout.

**Founder decision, not yours.** Ask: drop to `"1"` and remove a whole review surface,
or keep iPad and budget a layout pass. Default recommendation if no answer: drop to
`"1"` for v1.0 — a stretched phone UI on a 13" iPad is a worse first impression on a
paid app than not supporting it.

---

## Phase 2 — close the round trip (do not treat this as mechanical)

**This is the one that matters commercially, and the one where a plausible-but-wrong fix
still passes its tests.** Per `04_Guardrails.md`, escalate to Claude at the *first*
failure here rather than the second: this touches the append-only log and the sync
loop-prevention invariant, and a green test suite is not evidence those survived.

**The gap:** `ShardImporter` exists in `Sources/UnliRiceCore/Sync/` and is well covered
by `Tests/UnliRiceCoreTests/ShardImporterTests.swift` and `ShardSyncTests.swift` — and
**nothing in the macOS app calls it.** Only the tests do. Meanwhile
`CaptureStore.sync()` (`Sources/UnliRiceCapture/CaptureStore.swift:157-188`) is a
complete, working reference implementation of both halves: import foreign shards, then
publish local events to its own shard.

So the phone writes `events-phone-<id>.jsonl` into the shared folder and reads back what
it finds there, and the Mac never participates. The app is sold on "ideas reach your
Mac", and today that sentence is false.

**What to build:** the Mac equivalent of `CaptureStore.sync()`, driven from
`RoutineDriver.tick` (which already runs ~every 5 minutes and already ingests
`Notes for Unli Rice/`) plus a manual trigger in the UI.

Mirror the reference implementation exactly rather than inventing a second design:

- Import first, publish second — the order in `CaptureStore.sync()` is not incidental.
- Pass `ownShardFilename` so the Mac never re-imports its own shard.
- `ShardPublisher.publishLocalEvents`'s `isLocallyOriginated` closure is the loop
  guard. On the phone it is `event.device == ownDeviceLabel`. The Mac's inverse is
  documented in the comment at `CaptureStore.swift:182-186` — read it before writing
  the Mac predicate, and preserve the property that imported events are never
  re-published.
- `SyncState` lives beside the event log. The Mac has its own vault path; do not share
  a sync-state file between profiles.
- The export folder is security-scoped. Wrap access in
  `startAccessingSecurityScopedResource()` / `defer stop`, the way
  `CapturePromo.phoneShardCount(in:)` in `Sources/UnliRice/CapturePromoView.swift`
  already does.

**Where the UI already has a hole to fill:** `CapturePromoSheet` (same file) shows a
live status block that counts `events-phone-*.jsonl` files in the export folder and
currently ends with an honest admission that the Mac does not fold them in. When this
phase lands, that paragraph must be deleted and replaced with a real receipt — imported
count and last import time. **Do not delete the admission before the import works.**
This repo has already shipped one misleading connection status (`bfb330e`) and the
Trust Center exists because of it.

**Tests:** extend `ShardSyncTests` with a Mac-side round trip — phone writes, Mac
imports, Mac appends, phone imports the Mac's event, neither side re-imports its own.
Assert the event count does not grow on a second no-op sync in either direction.

---

## Phase 3 — the Action Button intent records exactly 3 seconds

`RecordCaptureIntent.perform()`
(`Sources/UnliRiceCapture/CaptureIntents.swift:24-28`) starts the recorder, sleeps a
hardcoded `3_000_000_000` nanoseconds, and stops. The intent is titled "Record Voice
Capture" and is surfaced to Siri and the Action Button with the phrases "Capture voice
note in Unli Rice" / "Record note in Unli Rice". Every capture made that way is
truncated at three seconds.

For a free companion this is a rough edge. For a paid app it is a headline feature that
does not do what its name says. **As of 2026-08-09 it is also the only remaining cap on
recording length anywhere in the app** (Phase 1.7 removed the others), which makes it
blocking rather than cosmetic if "no limit on how long you can talk" is going to appear
in the App Store listing.

Two viable shapes — **ask the founder which**, since it changes the interaction model:

1. **Start/Stop pair.** `StartCaptureIntent` + `StopCaptureIntent`, with the recorder
   held in a shared singleton. Truest to "hold the button, talk"; needs care so a
   start with no stop cannot leave the mic hot.
2. **`openAppWhenRun = true`** and auto-arm recording on launch. Much simpler, keeps one
   intent, loses the background capture that makes the Action Button worth binding.

Whichever is chosen, the current behaviour must not ship as-is at a price.

---

## Phase 4 — test coverage for the iOS half

All 200+ tests live in `Tests/UnliRiceCoreTests` and run on macOS. `ShardWriter` and the
sync core are covered; `CaptureStore`, `Recorder`, and `SpeechAnalyzerTranscriber` are
not touched by anything.

Add a `UnliRiceCaptureTests` target (`platform: iOS`, depends on `UnliRiceCoreiOS`) and
cover the seams that do not need real hardware:

- `CaptureStore` project-tab persistence and `updatePulledNotesForCurrentTab` filtering.
- `CaptureStore.sync()` against a temp directory standing in for the shared folder —
  the same round trip Phase 2 adds on the Mac side.
- `Transcriber` is already a protocol; inject a stub and assert that a transcription
  failure still leaves the recording on disk, which is the behaviour the comment at
  `SpeechAnalyzerTranscriber.swift:33-34` promises.

Do not chase coverage of `Recorder`'s AVFoundation calls or the real speech models.
Those need a device and a human.

---

## Phase 5 — small, unblocked, do it any time

- **`shield.checkmark.fill` is not an SF Symbol.** `Sources/UnliRice/MoreView.swift:30`,
  Trust Center's icon. It logs `No symbol named …` at runtime and renders nothing. The
  real name is `checkmark.shield.fill`. macOS app, unrelated to the release, one word.
- **`APP_STORE_SUBMISSION.md:29-32` is wrong and will misdirect a submission.** It states
  that `calmdownoscar.com/unlirice` is a 404 and must never be used in an App Store
  Connect field. That page now exists —
  `~/Documents/Projects/CalmdownOscar/unlirice/index.html`, created 2026-08-05. Correct
  the line. While there, note that the whole document describes the **free macOS**
  release and none of it carries over to a paid iOS record.
- **`PROJECT_NOTES.md` still has no entry for the iOS app.** The 2026-08-08 fact-check
  pass (`PROJECT_NOTES.md:1706`) flagged that the last ten commits — the entire iOS
  companion, the shard sync, the design-system port — were never written into the living
  status doc. That gap is now a year-old-feeling hole in front of a release. Write the
  reconstruction as part of this work.

---

## Phase 6 — App Store Connect (founder only, no code)

Listed so the plan is complete. **Do not perform any of this.**

- A new **free** app record for `com.calmdownoscar.unlirice.capture`: category, age
  rating, screenshots (iPhone, plus iPad only if Phase 1.6 kept it), description,
  keywords, copyright. No price tier, no IAP, no trial — nothing to configure there.
- Privacy label: **Data Not Collected**. On-device transcription, no account, no
  analytics, and the only network call is Apple's speech-model download. **This holds
  only while the app has no outbound LLM connection** — see the note below.
- Privacy policy and support URLs. `PRIVACY.md` covers the Mac app; check whether it
  needs an iOS section before pointing a store listing at it.
- Marketing copy should say **free and open source** explicitly. It is the strongest
  thing the listing has against a category full of subscriptions, and unlike the memory
  loop it is legible in one line without a Mac.
- **The App Store Bundle plan is dead.** App Store Bundles require every app in them to
  be paid, so a free Capture cannot be bundled with Unli Disk. This also retires the
  open question of whether a bundle may span macOS and iOS — it no longer matters. Two
  independent records, one free (Capture) and one paid (Unli Disk), with no shared
  entitlement and no StoreKit anywhere. `~/.claude/.../memory/unli-disk-ecosystem.md`
  records the superseded bundle plan and needs updating.
- Unli Disk is with App Review. Nothing in this plan touches it, and no new Unli Disk
  build should be created while this work happens.

---

## Standing rails for whoever executes this

- **No StoreKit, no IAP, no subscriptions, no trial code.** Now trivially satisfied —
  the app is free. Do not let a future "pro tier" idea reintroduce any of it.
- Capture is MIT and open source, same as macOS Unli Rice. `Sources/UnliRiceCapture/`
  is already tracked in this MIT repo, so no license work is needed — the pivot is a
  pricing decision, not a licensing one.
- `AGENTS.md` applies: identify writes as `source: "chatgpt"`, never as `janitor` or
  `ingest`.
- The locked-in architecture decisions in `PROJECT_NOTES.md:47` are non-negotiable —
  append-only log, no destructive delete reachable by any agent, structural changes
  proposed and never applied, every write attributed.

## Suggested order

1. Phase 1 end to end, then confirm the plist dump shows every fix. This is the cheapest
   way to know the thing can actually reach App Store Connect.
2. Phase 5's three items — minutes each, and the stale-doc one prevents a real mistake.
3. Phase 2. Escalate on first failure.
4. Phase 3, once the founder picks a shape.
5. Phase 4.
6. Phase 6, founder-led. Gate 0 is already closed.

---

## Appendix — the post-mortem that produced the free decision (2026-08-09)

Run against `_AI Context/07_Prelaunch_Post_Mortem.md`. Terse findings only:

- **Charging for the on-ramp to a free product inverts the funnel.** macOS Unli Rice is
  free and MIT; a paid satellite makes every install decision "pay to find out whether
  the free thing is for me."
- **The differentiator is invisible at the point of sale.** The memory loop cannot be
  shown in three App Store screenshots. What *can* be shown is a mic button, which
  Voice Memos does for free and Just Press Record does for $6.99 one-time — the latter
  with unlimited length, on-device transcription and an iCloud Drive folder, i.e. the
  whole visible feature set, since 2015.
- **Unlimited recording length is table stakes, not a differentiator.** Phase 1.7 fixed
  real caps and moved the app up to parity. Do not put it in the subtitle as though it
  were news.
- **The real paywall was never the money — it was the setup.** Asking a buyer to reason
  about iCloud Drive paths and a sync folder is a far larger ask than $6.99.
- **The name is invisible in ASO.** "Unli Rice Capture" contains no term anyone searches
  in the most saturated category on the store. Free removes the need to win that fight.
