# PLAN — Typing a note into Capture

**Intent:** `docs/intent/INTENT-003-keyboard-capture.md`
**Stage:** 4 — revised against Codex's pre-mortem. **Settled. Ready for the swarm.**
**Verified against:** `a962a26`

## For the swarm — how to execute this

- **Implement it; do not re-plan it.** Anything unanticipated comes back as a plan change.
- **§8 is a hard boundary.** Do not add anything listed there.
- **Follow the order in §7.** The existing voice path is repaired *before* anything new
  calls it.
- **Verify, do not assert.** `swift test` is 366 passing / 0 failures / 2 skipped at
  `a962a26`. Run it.
- **Adding a file under `Sources/` requires `xcodegen generate`.** `swift test` globs
  sources and passes while the Xcode build fails. This has bitten four times.
- Do not touch `Screenshots/app-panes/` or `Screenshots/repos-pane/` (untracked, awaiting a
  founder decision). Do not commit.

## 0. Stage-4 disposition

Every one of Codex's ten objections was re-verified against `a962a26`. **All ten are
confirmed and accepted.** Two are sharpened where the repo showed the problem is worse than
described.

| # | Objection | Disposition |
|---|---|---|
| 1 | Extraction turns a persistence failure into a second, empty voice note | **Accepted.** §2.2a |
| 2 | Concurrency guard must be mandatory and include `.transcribing` | **Accepted.** §2.2c |
| 3 | The shared path cannot establish the durable success §2.3 promises | **Accepted and sharpened — worse than stated.** §2.2b |
| 4 | "No play control" is not what the UI does; archive not audited | **Accepted.** §2.6 |
| 5 | The voice-append branch must not be absorbed | **Accepted.** §2.2a |
| 6 | Core tests do not prove the phone-to-Mac invariant | **Accepted.** §3, test 3 |
| 7 | `saveTypedNote` has two success authorities | **Accepted.** §2.4 |
| 8 | The sheet has a real speed cost, unsettleable on paper | **Accepted as conditional.** §2.5 |
| 9 | Rename inventory is wrong and misses a public API | **Accepted.** §2.1 |
| 10 | "No destructive delete" is not literally true here | **Accepted as a correction.** §0.1 |

### 0.1 A constraint statement that was wrong

The stage-3 brief listed "no destructive delete" as a live invariant. On the phone it is
not: `CaptureStore.deleteCapture` (`CaptureStore.swift:393`) removes the audio file and
calls `TrashService.purge` on `events.jsonl`. The locked decision holds for the *Mac's*
note tools, where `archive_note` is the only removal and is reversible. Nothing in this
plan touches `deleteCapture`, but no reasoning below leans on that phrase.

`memory.md`'s active-constraints line carries the same imprecision and should be qualified
next time it is edited. Not part of this change.

### 0.2 What the pre-mortem cost the scope

Objection 3 cannot be honestly deferred, and accepting it means **this plan now repairs an
existing defect in the voice path before adding the typed one**. That is a real scope
increase over the stage-2 draft and the founder should see it as one. The alternative —
shipping a Save button that dismisses on a write that may have gone nowhere — would make
the app assert a success it has not established, which is precisely the bug class
`PLAN-unknown-stays-unknown` was written to remove. Doing it here is cheaper than doing it
twice.

## 1. The finding that shapes the design

`CaptureStore.finishRecording()` fuses two separable jobs: transcribe audio to a `String`,
then turn that `String` into a note. A typed note needs only the second. So the feature is
an extraction — and the extraction is the risk, which is what the pre-mortem confirmed.

The second half carries details learned the hard way and documented in place: every event
mirrored to the local log rather than just `created`; the audio index keyed by
`event.noteId`, not `event.id`; titles derived by `ShardWriter` because
`Janitor.duplicateProposals` scores titles alone at ≥ 0.85 overlap. A second copy would
re-acquire all of them.

`SentCaptureItem.audioURL` is already `URL?` — *"the note outlives its audio"* — so a typed
note needs **no model change, no new `EventKind`, no migration**.

## 2. File-by-file

### 2.1 `Sources/UnliRiceCore/Sync/ShardWriter.swift` — the rename, corrected

The stage-2 draft said "six references" and missed a second public API. Corrected
inventory, verified with `rg 'writeCapture(Events)?\(' --glob '*.swift'`:

- `writeCaptureEvents(transcript:date:tags:)` — declaration, one internal call from
  `writeCapture`, two call sites in `CaptureStore`, one in `ShardWriterTests`.
- `writeCapture(transcript:date:tags:)` (`ShardWriter.swift:29`) — a separate **public**
  method returning only the `created` event, with nine call sites across `ShardSyncTests`
  and `ShardWriterTests`.

Rename `transcript:` → `text:` on **both**. The label is equally wrong on both, and leaving
one behind is how a naming cleanup becomes permanent confusion.

Keep `writeCapture`'s doc comment warning that callers mirroring into a second log must use
`writeCaptureEvents` — that warning is load-bearing and §2.2b depends on it.

### 2.2 `Sources/UnliRiceCapture/CaptureStore.swift`

This is the whole plan. Three changes, in this order.

#### 2.2a Split the `catch` before extracting anything

Confirmed at `CaptureStore.swift:632-700`: one `do` block wraps transcription, the
voice-append branch, and normal persistence. Its `catch` assumes any failure was a
transcription failure and writes a **second event batch with an empty transcript** so the
audio survives.

Today that is survivable, because only `transcribe` and the shard write can throw and the
distinction rarely matters. The moment persistence is a throwing helper, a failed shard or
log write falls into that `catch` and creates an *additional* empty note. So the stage-2
claim of "no observable change" was false, and this must be fixed **first**:

- Narrow the `do` to the transcription call alone, or bind the failure so the `catch` can
  tell the two apart.
- **The empty-audio fallback runs only for a transcription failure.**
- A persistence failure propagates. It must not create a second capture, and it must set
  `state = .error(...)` rather than `.completed`.
- **Preserve the voice-append branch exactly** (objection 5): when `appendTargetNoteID` is
  set, `finishRecording` calls `appendToCapture`, returns `"Appended to note"`, and creates
  no `SentCaptureItem`. That branch is **outside** the extraction and keeps its own result
  contract. The helper covers only the normal new-capture branch.

Confirm before moving on: inject a `ShardWriter` failure after transcription and observe
that exactly one note — or none — results, never two.

#### 2.2b Make the local mirror a real write, and define durable success

Codex's objection 3 is correct, and the repo shows it is worse than described.

- `writeCaptureEvents` writes to `shardWriter.shardFileURL`, which `CaptureStore` builds as
  `baseDir/shards/events-phone-<id>.jsonl` (`CaptureStore.swift:221-223`) — the **local**
  shards directory.
- `sync()` publishes with `ShardPublisher.publishLocalEvents(eventLogURL: events.jsonl, to:
  syncFolder/events-phone-<id>.jsonl)` (`CaptureStore.swift:352-375`), where `syncFolder`
  is the **shared** folder when one is configured.

So when a shared folder is set — the normal case — **the shard write is a dead end. The
only route to the Mac is `events.jsonl`.** And the mirror into it swallows both failures:

```swift
if let rawData = try? jsonEncoder.encode(written) {
    try? eventStore.appendRaw(rawData)          // ← both try?
}
```

If that append fails, the note exists only in a local shard nothing publishes from.
`rebuildCaptures()` rebuilds the list from `events.jsonl`, so it disappears from the phone
at the next sync and never reaches the Mac — and the current code reports success.

Required:

- **Both `try?`s become real error handling.** An encode or append failure throws.
- **Durable success is defined as: every event in the batch — `created` and every
  `tagged` — is appended to `events.jsonl`.** The shard write alone is not success. Write
  that definition into the code as a comment, because it is not obvious from the call
  order.
- Partial failure — some events appended, then a throw — must not be reported as success.
  The events already written stay (the log is append-only; nothing rewrites it), and the
  error names what happened. **Do not attempt a rollback**; that would mean deleting from
  an append-only log.
- `audioIndex.record` / `save` stay best-effort (`try?`) and are **not** part of durable
  success: losing the index costs playback of one recording, not the note.

This changes voice-capture behaviour: a mirror failure that used to pass silently now
surfaces. That is the intended direction.

#### 2.2c Extract the save, with a mandatory in-flight guard

```swift
/// Turn finished text into a note: shard write, local mirror, list entry, sync.
///
/// Extracted from `finishRecording` so a typed note and a spoken one take the
/// same path. Covers ONLY the normal new-capture branch — voice append is a
/// different contract and stays in `finishRecording`.
///
/// Throws if the batch does not reach `events.jsonl`. That log, not the shard,
/// is what `sync()` publishes from, so a shard write alone is not a saved note.
@discardableResult
private func saveCapturedText(_ text: String, audioURL: URL?) throws -> SentCaptureItem
```

- `audioIndex.record(...)` only when `audioURL != nil`. Never index a file that does not
  exist.
- `finishRecording` calls it with the transcript and the real `audioURL`; its observable
  behaviour is otherwise unchanged (as amended by §2.2a and §2.2b).

The public entry point:

```swift
/// Save a typed note. Same events, same tag, same sync as a spoken one.
public func saveTypedNote(_ text: String) throws -> SentCaptureItem
```

- **The in-flight guard is mandatory and lives here, not in the UI** (objection 2).
  `isRecordingOrPaused` in `CaptureView.swift:362` is only `.recording || .paused`, and
  `finishRecording` spends its entire awaited transcription interval in `.transcribing`
  (`CaptureStore.swift:629`). A typed save landing in that window would set `.completed`,
  insert an item, and then be overwritten by the voice continuation.
  **`saveTypedNote` throws for `.recording`, `.paused` and `.transcribing` alike.** The UI
  disables the entry point on the same predicate — add a `captureInFlight` property on the
  store so both read one definition, rather than the view re-deriving it.
- Trim with `.whitespacesAndNewlines` and throw on empty; preserve interior line breaks.
- Tag with `currentProjectTab`.
- `state = .completed(title:)` on success only. A typed note never enters `.recording` or
  `.transcribing`; do not fake a pass through them.

### 2.3 `Sources/UnliRiceCapture/TypedNoteSheet.swift` (new)

A sheet. Match the existing keyboard idiom at `NoteDetailView.swift:230-275` — placeholder
`Text` behind a `TextEditor` in a `ZStack`, `Theme.bgField`, `Theme.borderLight`,
`cardStyle(cornerRadius: 12)`, accent Save, `Theme.crit` for the error line.

- Focus the editor on appear.
- Save disabled while the trimmed text is empty; the throw is the backstop.
- Cancel discards without a confirmation prompt.
- **Dismiss only on a returned success** — which §2.2b now makes a real guarantee rather
  than a hope. On a throw: keep the sheet, keep the text, show the message.

### 2.4 Ownership of success — one authority

`CaptureStore` is the **sole** owner of `captures` and `state` (objection 7). The sheet must
not insert the returned item, must not mutate `state`, and must not infer durability from
the return value beyond "no throw".

The return value exists for one purpose: the caller may name the saved note. If the sheet
does not need it, **delete the return and make the method `Void`** — two ways to learn one
outcome is how they drift.

### 2.5 `Sources/UnliRiceCapture/CaptureView.swift` — the way in

`@State private var showTypedNote = false`, and a keyboard button in `recordSection` beside
the mic — not replacing it.

- Disabled/hidden on `store.captureInFlight` (§2.2c).
- **Verify the SF Symbol renders.** This repo has a live example of one that does not:
  `shield.checkmark.fill` at `MoreView.swift:25` logs "No symbol named … found in system
  symbol set". Check the console.
- Must be reachable in all three layouts — iPad regular width (where `recordSection` sits
  in a fixed `.frame(width: 320)`) and both `layoutPlacement` orders.

**The sheet stands** (objection 8). Codex is right that the mic records straight from its
tap gesture (`CaptureView.swift:343`) while typing costs a presentation first, and right
that the repo cannot settle whether that matters. It is recorded as a founder check after
first use, not a blocker: if open→type feels slow in practice, an inline composer is a
contained follow-up, not a redesign.

### 2.6 Audio-less rendering — three surfaces, and a claim to stop making

Objection 4 confirmed. All three render a **disabled** `Button` with a `waveform` glyph,
not the absence of a control:

- `CaptureView.swift:527` — the main list.
- `NoteDetailView.swift:132` — detail, labelled **"Recording no longer stored"**.
- `ArchivedNotesView.swift:64` — the archive, which the stage-2 audit missed entirely.

For a typed note "Recording no longer stored" is simply false — nothing was ever stored.
And nothing in the model distinguishes *pruned* from *never had audio*: a typed note has no
`audioIndex` entry, and neither does a pruned one after `forget(noteID:)`.

So do not guess. Apply this repo's own rule:

- **Render no playback control at all when `audioURL == nil`** in the list and the archive.
  A disabled button is a control that says "this could play, but not now" — a claim about
  history that is not known.
- In detail, keep an explanatory line but stop asserting what happened: **"No recording"**.
  True whether the audio was pruned or never existed.

Adding a field to distinguish the two is out of scope; the honest label costs nothing.

## 3. Tests

`UnliRiceCapture` has no test target and this change does not add one. What can be tested
in Core, must be.

**Regression — must fail before, pass after**

1. `ShardWriterTests`: `writeCaptureEvents(text:)` and `writeCapture(text:)` after the
   rename. Compatibility, not regression — passes on both sides.
2. **The round-trip Codex asked for** (objection 6). The existing bidirectional test at
   `ShardSyncTests.swift:99-101` uses `writeCapture`, mirrors only the single `created`
   event, and therefore never exercises a capture *batch* through the real path. Add a
   Core-only test that writes `writeCaptureEvents(text:tags:)`, mirrors **every** encoded
   event into a local log, publishes with `ShardPublisher`, imports into a Mac log, and
   asserts body, derived title, device label **and project tag** survive. Run it with a
   no-audio batch. This is the phone-to-Mac invariant the feature depends on and nothing
   currently proves it.
3. A batch whose mirror fails partway does not report success (§2.2b), exercised at the
   `EventStore` level.

**By hand, on a device or simulator**

4. Type a note → it appears at the top of the list under the current project tab.
5. It reaches the Mac and is indistinguishable from a spoken note.
6. **No playback control** in the list or the archive; detail says "No recording".
7. A pruned *voice* note renders the same way and has not regressed.
8. Whitespace-only cannot be saved.
9. Cancel discards; a save failure keeps the sheet and the text.
10. The keyboard button appears correctly in all three layouts, and its symbol renders.
11. Typing is impossible while recording, paused **and transcribing** — test the
    transcribing window specifically, with a slow transcription.
12. **A spoken note still works end to end.** The extraction plus §2.2a/§2.2b touch the
    working path; a regression here costs more than the feature is worth.
13. A voice **append** still appends to the target note and creates no new capture.
14. A transcription failure still produces one empty-transcript note with playable audio —
    and exactly one.

## 4. Order of work

1. §2.1 rename — mechanical, isolated.
2. **§2.2a split the catch, then §2.2b fix the mirror.** Both are repairs to the existing
   voice path. Verify by hand (tests 12, 13, 14) **before writing a line of typed capture.**
3. §2.2c extract and add `saveTypedNote` + `captureInFlight`.
4. §2.6 audio-less rendering across all three surfaces.
5. §2.3 sheet, §2.5 entry point, §2.4 ownership.
6. Test 2, the round-trip, can be written at any point and is the most valuable single
   artifact here.

## 5. Explicitly not in this plan

- Editing an existing note's body. Append exists.
- Rich text, Markdown, attachments, images.
- Any change to the mic, hold-to-record, the Action Button intent, transcription locale, or
  audio retention.
- A separate note type, list, filter, or "typed" badge.
- A user-entered title field.
- A field distinguishing "audio pruned" from "never had audio" (§2.6).
- A test target for `UnliRiceCapture`.
- `deleteCapture` / `TrashService.purge` (§0.1).
- An inline composer (§2.5) — a follow-up if the founder check says so.
- The Mac app.

## 6. Residual risk, stated plainly

- **§2.2b changes voice-capture failure behaviour.** Errors that were swallowed now
  surface. If the mirror was failing routinely for some user, this turns a silent
  data-loss bug into a visible error — correct, but it will look like a new bug.
- **§2.2a rewrites control flow in the app's most important method** on the strength of
  reading it, not of a test that pins today's behaviour. Tests 12-14 are by hand, which is
  the weakest part of this plan and is a direct consequence of `UnliRiceCapture` having no
  test target.
- **The sheet-versus-inline question is deferred to first use**, not resolved.
