# Unli Rice Capture — transcription languages + note append (keyboard & voice)

> **Execution rules, read first.**
> - Work on a **fresh branch off `main`** (suggested `feature/languages-and-append`).
>   `feature/folder-first` carries unrelated UI work — do not build on it.
> - `project.yml` is the source of truth. The `.xcodeproj` is generated and
>   gitignored — run `xcodegen generate` after every spec edit, before building.
> - **Do not ship.** No uploading, submitting, archiving for distribution, or
>   version bumping (`docs/IOS_CAPTURE_RELEASE.md:22-26`). Stop at "builds and
>   validates locally".
> - Verify claims against the repo, not against notes. Notes can be stale; code is
>   ground truth.

## Context

The founder's prioritisation call: **sticky notes are parked**, and the two things
worth building next are (1) more transcription languages and (2) being able to add to
a note after the fact, by keyboard or by voice.

Both are real gaps in the iOS Capture app (target `UnliRiceCapture`):

- **Language.** `SpeechAnalyzerTranscriber` uses `Locale.current` and nothing else
  (`SpeechAnalyzerTranscriber.swift:40`). There is no picker, no way to see or
  choose a language, no model-reservation call anywhere in the repo. If the device
  locale has no `SpeechTranscriber` equivalent, `transcribe` throws
  `.localeUnsupported` and `finishRecording` lands in `state = .error` — **the audio
  survives on disk but no note is ever created** (`CaptureStore.swift:481`, `:523`).
  A thought spoken in the wrong language is silently lost from the notes list.
- **Editing.** A note's text cannot be changed at all on iOS, by any means. There is
  exactly one `TextField` in the whole target (the "New Project Tab" alert,
  `CaptureView.swift:135`), no `TextEditor`, no note detail view, and no call site
  for `appendToNote`. Every voice recording can only ever create a brand-new note.
  The macOS app has had append since day one.

Intended outcome: pick your transcription language and see its model state before you
rely on it; and open a note to read its full transcript and add to it — typed or
spoken — the way the Mac app already allows.

### Decisions already made (do not relitigate)

- **Append only. No revision, no rename.** The event log is append-only and title
  immutability is load-bearing — `Projector.resolveLinks` matches wiki-links by title
  precisely because no `retitled` event exists (`Projector.swift:131-135`). This plan
  adds **no new `EventKind`**. It uses `.appended`, which already exists and already
  projects (`Projector.swift:68-75`, concatenating with a `\n\n---\n` separator).
- **One transcription language, chosen in Settings**, defaulting to "Follow system".
  Not per-recording, not per-project-tab.
- **Sticky notes: parked, not cancelled.** Do not build them. If picked up later, the
  tint decision is already made — *tint by project tab*, one colour per tab derived
  from the tag string, no new field in the event log.

---

## Phase 1 — Transcription language

### 1.1 Make locale a per-call argument, not an init constant

Today `SpeechAnalyzerTranscriber.locale` is a `let` captured at init
(`SpeechAnalyzerTranscriber.swift:38-42`), and `CaptureStore` builds the transcriber
once in its own `init` (`CaptureStore.swift:133-136`, `:157`). A settings change
would therefore never take effect until relaunch.

Change the seam in `Transcriber.swift` (all 6 lines of it):

```swift
public protocol Transcriber: Sendable {
    func transcribe(audioURL: URL, locale: Locale) async throws -> String
}
```

`SpeechAnalyzerTranscriber` drops its stored `locale` and takes the argument. The
rest of `transcribe` is unchanged — it already does the right thing per call:
`SpeechTranscriber.supportedLocale(equivalentTo:)` for equivalence matching (`:52`),
then `installAssetsIfNeeded` (`:56`), then a fresh `SpeechTranscriber` and
`SpeechAnalyzer` (`:55`, `:58`). Update the test doubles that inject a `Transcriber`.

### 1.2 Persist the setting

Follow the existing three-part pattern in `CaptureStore.swift` exactly — key constant
(`:56-60`), `@Published` with a write-through `didSet` (`:98-102`), raw-string
read-back with a `??` default in `init` (`:137-151`).

`transcriptionLocaleID: String`, key `UnliRiceCapture_transcriptionLocale`, empty
string meaning "follow system". Store the identifier, **not** an enum case — the
supported set is a runtime list from the OS, so the `String, CaseIterable` enum shape
used by `RecordingMode`/`AudioRetention` does not fit here.

Add a resolved accessor and use it at the call site (`CaptureStore.swift:481`):

```swift
public var effectiveTranscriptionLocale: Locale {
    transcriptionLocaleID.isEmpty ? Locale.current : Locale(identifier: transcriptionLocaleID)
}
```

### 1.3 Enumerate and reserve the models

None of this exists in the repo today (verified: no `supportedLocales`,
`installedLocales`, `reserve`, or `allocate` anywhere in `Sources`).

New file `Sources/UnliRiceCapture/TranscriptionLanguages.swift`:

- `supported() async -> [Locale]` wrapping `SpeechTranscriber.supportedLocales`,
  sorted by localized display name.
- `status(for: Locale) async -> LanguageStatus` (`.installed` / `.available` /
  `.downloading` / `.unsupported`) via `AssetInventory.status(forModules:)`, the same
  call `installAssetsIfNeeded` already uses (`SpeechAnalyzerTranscriber.swift:93`).
- `install(_ locale: Locale) async throws` with progress, wrapping
  `AssetInventory.assetInstallationRequest(supporting:)` + `downloadAndInstall()`.
- `reserve(_ locale: Locale) async throws` — `AssetInventory.reserve(locale:)`, so the
  chosen model is not evicted. **There is a per-app cap**
  (`AssetInventory.maximumReservedLocales`): release the previously reserved locale
  when the setting changes, and surface a plain-language error rather than throwing
  into the void if the cap is hit.

Cache the enumeration on `CaptureStore` as `@Published var availableLocales: [Locale]`,
populated once on first settings-sheet appearance — not in `init`, which is
synchronous and runs on app launch.

### 1.4 Settings UI

Add a "Transcription" `Section` to `settingsSheet` in `CaptureView.swift`, between
"Recording Behavior" (`:642`) and "Interface Layout" (`:652`). Match the surrounding
style: `Section(header:footer:)`, `Theme.textSecondary` headers, `Theme.textLight`
footers, `Theme.textPrimary` rows.

Not a `.segmented` picker — the list is long. Use a `NavigationLink` to a pushed
language list (the settings sheet already wraps a `NavigationView`, and
`ArchivedNotesView` is pushed from it at `:578`, so this needs no new navigation
plumbing). Each row: localized language name, a right-hand status label (`installed` /
size + `Download` / a progress view), checkmark on the selection. First row is always
"Follow system", showing the resolved language in parentheses.

Footer copy should say plainly that transcription happens on the device and the model
is a one-time download. Do not imply mixed-language speech works — see Out of scope.

### 1.5 Stop losing the note when transcription fails

Directly in scope: an unsupported or not-yet-downloaded language currently costs you
the whole note. In `finishRecording`'s `catch` (`CaptureStore.swift:522-525`), before
rethrowing, write the capture anyway with an empty transcript so
`ShardWriter.writeCaptureEvents` produces its `timestampedFallbackTitle` note
(`ShardWriter.swift:75-77`, `:108-113`) and `audioIndex.record` still runs. The audio
is already saved; the note should exist so the recording is reachable and re-playable
from the list. Keep `state = .error(...)` so the failure is still visible.

Do **not** change the fallback-title scheme — the comment at `ShardWriter.swift:43-49`
explains that a constant fallback title floods `Janitor.duplicateProposals`.

---

## Phase 2 — Append to a note (keyboard and voice)

### 2.1 A write path for `.appended` on iOS

iOS does not write through `NoteService` — `finishRecording` hand-builds events and
writes them to the sync shard via `ShardWriter`, then mirrors **every** event into the
local `eventStore` with `appendRaw` (`CaptureStore.swift:482-500`). An append must
follow the identical path or it will never reach the shared folder or the Mac; the
comment at `:485-491` records exactly this bug happening once already with tags.

Add to `ShardWriter.swift`, alongside `writeCaptureEvents`:

```swift
public func writeAppendEvents(noteID: UUID, text: String, date: Date = Date()) throws -> [Event]
```

One `Event` with `kind: .appended`, `noteId: noteID`, `text:`, `source: "human"`,
`device: deviceLabel`, no `title`. Factor the file-handle append loop
(`ShardWriter.swift:118-138`) into a private `write(_ events: [Event]) throws` that
both methods call, rather than duplicating it.

Then `CaptureStore.appendToCapture(noteID:text:)`, mirroring `finishRecording`'s
structure: trim, guard non-empty (as `AppStore.append` does,
`Sources/UnliRice/AppStore.swift:1331-1342`), write events, mirror with `appendRaw`,
`rebuildCaptures()`, `sync()`.

### 2.2 A note detail view — the actual prerequisite

There is no way to read a note's body on the phone. `captureRow`
(`CaptureView.swift:517-568`) renders title + timestamp only, and `SentCaptureItem`
carries no body at all (`CaptureStore.swift:5-23`). Nothing is pushed from the main
screen; the root is a bare `ZStack` in a `WindowGroup` with no `NavigationStack`
(`CaptureApp.swift:7`, `CaptureView.swift:29-47`).

New `Sources/UnliRiceCapture/NoteDetailView.swift`, presented as
`.sheet(item: $selectedCapture)` from `CaptureView`. **A sheet, not a NavigationStack
at the root** — the root `ZStack` also carries the `AppLock` overlay (`:366`) and
`WelcomeSplashView` (`:37`), and wrapping it risks the lock rendering underneath a
pushed screen.

Make `captureRow`'s text column a `Button` that sets `selectedCapture`. Keep the
play/archive/delete buttons as they are.

Contents:
- Full body, read via `store.noteService.getNote(id:)` on appear. Do not try to route
  this through `pulledNotes` (`CaptureStore.swift:67`) — it is filtered to the current
  tab and is not a general note lookup.
- Timestamp, tags, and the existing `CapturePlayer` playback control — `CapturePlayer`
  is already per-view `@StateObject` and keyed by note id (`CapturePlayer.swift:15,
  :24, :28`), so it drops in unchanged.
- **Keyboard append:** a `TextEditor` + "Append" button, following
  `Sources/UnliRice/ContentView.swift:1150-1184` (`appendSection`) including its
  placeholder-overlay trick and its disabled-when-blank rule. Style with
  `.cardStyle(cornerRadius: 12)` and `Theme.bgField`.
- **Voice append:** a record button that runs the same record → transcribe → write
  cycle, but calls `appendToCapture` instead of `writeCaptureEvents`. Reuse
  `Recorder.shared` and `store.effectiveTranscriptionLocale` from Phase 1.

### 2.3 The recorder is a singleton — guard it

`Recorder.shared` is one instance and `CaptureStore.state` is one state machine
(`CaptureStore.swift:45`, `:397-459`). Voice-append must not run while the main
capture is recording, and vice versa. Simplest correct approach: route voice-append
through `CaptureStore` too, with an explicit target — e.g. an
`appendTargetNoteID: UUID?` set for the duration — so `finishRecording` branches to
append-or-create at its single write site (`:482`) instead of a second, parallel
recording path. Disable the detail sheet's record button whenever `state` is not idle,
and disable the main record button while the sheet is recording.

### 2.4 Fix the welcome copy while you are here

`WelcomeSplashView.swift:36` promises "swipe to archive or delete". That gesture does
not exist — the rows use tap buttons. It is one line and it is already wrong.

---

## Out of scope — flag, do not decide

- **True revision / rename.** Correcting a typo in place needs a new `EventKind`,
  changes `Projector` body folding from concatenation to last-write-wins, and breaks
  the title-immutability guarantee `resolveLinks` depends on. If it comes up, it is an
  architecture decision for the founder, not a feature. Do not implement it.
- **Code-switching (e.g. Taglish).** `SpeechTranscriber` takes one locale per session;
  mixed-language speech is not solved by a picker. Name it honestly in the settings
  footer rather than implying it works.
- **Sticky notes / widgets.** Parked. No WidgetKit scaffolding exists anywhere in the
  repo, and a widget would additionally need a new extension target, an iOS App Group,
  and the event log moved out of the app's private Documents
  (`CaptureStore.swift:153-155`).

---

## Verification

Per-phase, binary where possible:

```bash
cd ~/Documents/Projects/"Unli Rice"
xcodegen generate
swift build && swift test
xcodebuild -project UnliRice.xcodeproj -scheme UnliRiceCapture \
  -destination 'generic/platform=iOS' -configuration Release build CODE_SIGNING_ALLOWED=NO
```

**Phase 1, in the Simulator:**
1. Settings → Transcription shows a language list with per-language status.
2. Pick a non-system language, force-quit, reopen — selection persisted.
3. Record in that language; transcript comes back in it. Confirms the locale reaches
   `transcribe` per call and is not stale from init.
4. Record with a language whose model is absent → a note still appears in the list
   with a `Voice note — <timestamp>` title and playable audio (Phase 1.5).

**Phase 2, in the Simulator:**
1. Tap a note → sheet opens showing the **full transcript**, not just the title.
2. Type into the append box, tap Append → the body shows the original, a `---`
   separator, then the new text.
3. Speak into the append control → same, appended not created; the notes list count
   does **not** increase.
4. Force-quit and reopen → appends survived (they are in `events.jsonl`, not just in
   memory).
5. Confirm the main record button is disabled while the sheet is recording.

**Cross-device, the part that actually catches the tag-class bug:**
Point the phone at the shared folder, append on the phone, then open the Mac app and
confirm the appended text is present on the same note. If it is missing, the
`appendRaw` mirror in 2.1 was skipped — the exact failure the comment at
`CaptureStore.swift:485-491` documents.

**Unit tests** in `Tests/`: `ShardWriter.writeAppendEvents` emits one `.appended` event
with the right `noteId` and no `title`; feeding `[created, appended]` through
`Projector` yields the `\n\n---\n`-joined body; `effectiveTranscriptionLocale` returns
`Locale.current` for an empty identifier.

---

## When you are done

Report what you actually changed, file by file, and paste the real output of
`swift test` and the `xcodebuild` command. Do not report SUCCESS without it — the
founder checks `git diff` against the report.
