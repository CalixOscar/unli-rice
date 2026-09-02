# PLAN — Typing a note into Capture

**Intent:** `docs/intent/INTENT-003-keyboard-capture.md`
**Stage:** 2 (Claude's plan). **Not built.** Next stop is Codex's pre-mortem, then a
stage-4 revision, then the swarm. Nothing in this file has been implemented.
**Verified against:** working tree at `1d7a77d` + the uncommitted `PLAN-unknown-stays-unknown` change set

## 1. The finding that shapes the design

`CaptureStore.finishRecording()` does **two separable jobs fused into one method**:

1. Stop the recorder, transcribe the audio to a `String`.
2. Turn that `String` into a note — write shard events, mirror every event into the local
   log, index the audio, build a `SentCaptureItem`, insert it at the head of the list, set
   `state`, and `sync()`.

A typed note needs job 2 and none of job 1. So this feature is **not** new persistence
logic — it is an extraction. That matters, because job 2 carries details that were learned
the hard way and are documented in place:

- **Every event is mirrored to `eventStore.appendRaw`, not just the `created` one.** The
  comment says dropping the `tagged` events left captures untagged, so the project-tab
  filter matched nothing and the list showed "No synced notes found." over a corpus that
  had them.
- **`audioIndex` is keyed by `event.noteId`, not `event.id`** — "the created event's id is
  a different UUID and never appears again."
- **Titles are derived by `ShardWriter`**, which explains at length that a constant or
  empty title scores 1.0 against every other capture in `Janitor.duplicateProposals` and
  fills the review queue with proposals to merge unrelated notes.

**A second copy of that logic would re-acquire every one of those bugs.** The whole plan is
therefore: extract job 2, call it from two places.

The model already anticipates this. `SentCaptureItem.audioURL` is `URL?`, documented as
*"Nil once retention has pruned the recording… The note outlives its audio."* A typed note
is an existing case, not a schema change. **No model change, no new `EventKind`, no
migration.**

## 2. File-by-file

### 2.1 `Sources/UnliRiceCore/Sync/ShardWriter.swift` — a parameter that stops lying

`writeCaptureEvents(transcript:date:tags:)` will now receive typed text as often as
transcribed text. Rename the label `transcript:` → `text:`.

Six references, all mechanical:

- `ShardWriter.swift` — the declaration and one internal caller.
- `CaptureStore.swift` — two call sites (one is `transcript: ""`).
- `ShardWriterTests.swift` — one.

Keep the parameter's doc comment; only the name is wrong, not the reasoning. This is a
small rename and it is in scope precisely because this repo keeps paying for names that
describe how a value happened to arrive rather than what it is.

### 2.2 `Sources/UnliRiceCapture/CaptureStore.swift` — extract the save

Split the second half of `finishRecording()` into one method, used by both paths:

```swift
/// Turn finished text into a note: shard events, local mirror, list entry, sync.
///
/// Extracted from `finishRecording` so a typed note and a spoken one take
/// EXACTLY the same path. The details here were expensive — every event is
/// mirrored, not just `created`; the audio index is keyed by note id, not
/// event id — and a second copy of this logic would re-acquire both bugs.
///
/// `audioURL` is nil for a typed note. `SentCaptureItem.audioURL` has always
/// been optional because a note outlives its audio; a note that never had any
/// is the same case reached from the other direction.
@discardableResult
private func saveCapturedText(_ text: String, audioURL: URL?) throws -> SentCaptureItem
```

- `finishRecording()` calls it with the transcript and the real `audioURL`. Its behaviour
  must not change in any observable way — same events, same list entry, same `state`
  transitions, same return value.
- `audioIndex.record(...)` and the index save happen **only when `audioURL != nil`**. Do
  not write an index entry pointing at a file that does not exist.

Then the public entry point for typed notes:

```swift
/// Save a typed note. Same events, same tag, same sync as a spoken one.
///
/// Throws `CaptureTextError.empty` on whitespace-only input rather than writing
/// a note whose derived title would be the timestamped fallback — see
/// ShardWriter on why empty titles poison duplicate detection.
@discardableResult
public func saveTypedNote(_ text: String) throws -> SentCaptureItem
```

- Trim with `.whitespacesAndNewlines`; throw on empty. Save the **untrimmed-interior**
  text (leading/trailing trimmed only) — do not reflow or collapse the user's line breaks.
- Tag with `currentProjectTab`, exactly as `finishRecording` does.
- Set `state = .completed(title:)` on success. A typed note never enters `.recording` or
  `.transcribing`; do not fake a pass through them.
- **Guard against saving while a recording is in flight.** If `isRecordingOrPaused`, either
  disable the entry point in the UI or throw — decide in build, but do not let a typed save
  land in the middle of `finishRecording()` and race the `captures` array. State the choice
  in the code comment.

### 2.3 `Sources/UnliRiceCapture/TypedNoteSheet.swift` (new) — the composer

A sheet, not an inline composer. `mainContent` has three layouts — iPad regular-width
side-by-side, and two phone orders driven by `store.layoutPlacement` — and an inline
composer has to be correct in all three while the keyboard is up. A sheet is one surface
that behaves the same in every layout, and it matches how the app already presents
`settingsSheet`.

Match the existing keyboard idiom in `NoteDetailView.swift:230-275` rather than inventing
one: a placeholder `Text` behind a `TextEditor` in a `ZStack`, `Theme.bgField`,
`Theme.borderLight` stroke, `cardStyle(cornerRadius: 12)`, and an accent Save button. The
error line uses `Theme.crit`, as `appendError` does.

- **Focus the editor on appear.** A composer that needs a second tap to start typing fails
  the "fast in and out" constraint in the intent.
- **Save is disabled while the trimmed text is empty** — the thrown error is the backstop,
  not the interaction.
- Cancel discards without saving and without a confirmation prompt.
- Save dismisses immediately on success. Do not keep the sheet open showing a success
  state; the note appearing at the top of the list is the confirmation.
- On a thrown error, keep the sheet open, keep the text, show the message. **Never dismiss
  a sheet whose content was not saved.**

### 2.4 `Sources/UnliRiceCapture/CaptureView.swift` — the way in

Add `@State private var showTypedNote = false` and a keyboard button in `recordSection`,
beside the mic — not replacing it. Voice stays the primary affordance; this is the second
way in, not a competing one.

- Place it in `recordingControlBar` (line ~274) or immediately below `recordButton`
  (~311), wherever it reads as a peer of the mic without displacing it. `keyboard` is the
  SF Symbol; **verify it renders** — this project has a live example of an SF Symbol that
  does not resolve (`shield.checkmark.fill` at `MoreView.swift:25` logs "No symbol named …
  found in system symbol set" at runtime). Check the console, do not assume.
- Hide or disable it while `isRecordingOrPaused`, consistent with §2.2's choice.
- The button must be reachable in all three layouts. Check iPad regular width explicitly —
  `recordSection` is inside a fixed `.frame(width: 320)` column there.

### 2.5 The list and the player — no play control for a note with no audio

A typed note has `audioURL == nil`. Audit every place that renders a capture and confirm
it degrades honestly rather than offering a control that does nothing:

- `capturesList` / the row view in `CaptureView.swift:493`.
- `NoteDetailView` — its playback affordance and `CapturePlayer` usage.
- `CapturePlayer` itself, if it is handed a nil URL anywhere.

Retention-pruned captures already produce `audioURL == nil`, so this path may already be
correct — **verify it, and fix only what is actually broken.** If a play button is shown
for an audio-less note today, that is a pre-existing bug this feature makes far more
common, and fixing it is in scope.

Do **not** add a "typed" badge or otherwise mark these notes as a second class. The absence
of a play control is the honest signal, and the intent's open question on this is
deliberately answered the minimal way.

## 3. Tests

`UnliRiceCapture` has no test target — only `UnliRiceCoreTests` exists. So the testable
surface is what lives in Core, and the rest is by hand. Do not invent a test target.

**`ShardWriterTests.swift`**
1. `writeCaptureEvents(text:)` compiles and behaves identically after the rename — the
   existing test, updated. Compatibility, not regression: it must pass before and after.
2. Typed-length text (multi-line, with punctuation and a URL) derives a non-empty,
   non-constant title. Guards the duplicate-detection reasoning the writer documents.

**By hand, on a device or simulator**
3. Type a note → it appears at the top of the list, under the current project tab.
4. It syncs to the Mac and appears there, indistinguishable from a spoken note.
5. It has **no play control** anywhere it is rendered.
6. Whitespace-only input cannot be saved; Save is disabled and the error path is unreachable
   by normal use.
7. Cancel discards; nothing is written.
8. A save failure keeps the sheet open with the text intact.
9. The keyboard button is present and correctly placed in all three layouts: iPad regular
   width, and both `layoutPlacement` orders on the phone.
10. The button's SF Symbol actually renders — check the console for "No symbol named".
11. Typing while a recording is in flight is impossible (button hidden/disabled).
12. A spoken note still works end to end, unchanged. **This is the one that matters most:**
    the extraction in §2.2 touches the existing path, and a regression there costs more
    than this feature is worth.

## 4. Order of work

1. §2.1 rename. Mechanical, isolated, makes the rest read correctly.
2. §2.2 extraction, with the spoken path verified unchanged **before** anything new calls
   it. Do not write the typed path until a spoken capture still works.
3. §2.5 audit — find out what an audio-less note renders as today.
4. §2.3 sheet, §2.4 entry point.

## 5. Explicitly not in this plan

- Editing an existing note's body. Append exists; append-only stands.
- Rich text, Markdown, attachments, images.
- Any change to the mic, hold-to-record, the Action Button intent, transcription locale, or
  audio retention.
- A separate note type, list, filter, or badge.
- A user-entered title field — titles stay derived, for the reason `ShardWriter` documents.
- A test target for `UnliRiceCapture`. Worth having; not this change.
- The Mac app.

## 6. For the pre-mortem

- **The extraction is the risk, not the feature.** §2.2 rewrites the working spoken path to
  serve a new one. Is a private `saveCapturedText(_:audioURL:)` the right seam, or should
  `finishRecording` keep its body and the typed path get a deliberately narrow duplicate?
  I judged one path worth the edit risk; that judgement is the thing to attack.
- **The concurrency guard in §2.2 is stated as a choice to make during the build**, which is
  the kind of thing that gets skipped. Should the plan just mandate throwing?
- **`saveTypedNote` returns `SentCaptureItem` and also mutates `captures` and `state`.**
  That mirrors `finishRecording`, but it means the sheet has two ways to learn what
  happened. One may be redundant.
- **A sheet may be the wrong call** if the founder wants typing to be as fast as tapping the
  mic. An inline composer is fewer taps and worse layout risk.
