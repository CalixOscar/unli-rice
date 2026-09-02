<!-- INTENT — the WHY, written at stage 1, before any architecture exists.
     Template: ~/Documents/Unli Rice Vault/scripts/templates/INTENT.md
     Never edited to match what got built; superseded by a new INTENT if it turns
     out to be wrong. -->

# INTENT-003 — Typing a note into Capture

**Date:** 2026-09-03
**Author:** founder, via Claude Code (a one-line brief, not a Spark session)
**Status:** draft
**Plan:** `docs/PLAN-keyboard-capture.md`

## The problem

On the phone, a note can only *start* as speech. `CaptureStore` exposes
`toggleRecording`, `startRecording`, `finishRecording` — and no way to originate a note
from typed text.

The keyboard is already in the app, which is what makes the gap odd rather than merely
missing:

- `NoteDetailView.swift:242` — a `TextEditor` to **append** to a note that already exists.
- `TodoView.swift:162` — a `TextEditor` to note **against a to-do item**.
- `CaptureView.swift:139` — a `TextField`, but for naming a project tab.

So you may type into a thought you already had, and not type a new one. The first word of
every note must be spoken.

## Who hits it, and when

The founder, and anyone using the capture app, in the ordinary situations where speech is
unavailable or unwise:

- In a meeting, a lecture, a waiting room, a library, a quiet carriage.
- Beside someone asleep.
- In a room loud enough that transcription will mangle it — where the failure is not
  "cannot speak" but "speaking produces a wrong note", which is worse, because a wrong
  note enters the corpus and has to be found and fixed later.
- Any note containing things speech-to-text reliably ruins: an identifier, a file path, a
  command, a URL, a name it has never heard.
- Anyone who does not want to talk to their phone in public, which is most people, most of
  the time.

The cost is not inconvenience — it is a lost note. This studio's whole premise is that the
thought is captured at the moment it occurs. A capture surface that is unavailable half the
time is a capture surface that silently drops half the thoughts.

## What "solved" looks like

From outside the app:

1. On the capture screen, there is an obvious way to type a note, reachable in one tap
   from the same screen the mic is on.
2. What it produces is **the same kind of thing a spoken note produces**: it appears in the
   same list, carries the current project tab, syncs to the Mac by the same path, and is
   indistinguishable downstream except that it has no audio.
3. It never presents a play control for a note that has no recording.
4. Typing a note is fast in and out — open, type, save, gone. It is a capture box, not a
   writing app.
5. An empty or whitespace-only note cannot be saved.

## Explicitly out of scope

- **Editing an existing note's body.** Append already exists and is the append-only
  model's answer; nothing here introduces an edit-in-place path.
- **Rich text, Markdown rendering, attachments, images.**
- **Changing the voice flow** — the mic, hold-to-record, the Action Button intent,
  transcription locale, audio retention. None of it moves.
- **A separate note type or list.** A typed note is a capture with no audio.
- **Offline/queueing behaviour.** Whatever sync does today, it keeps doing.
- **The Mac app.** This is the phone's capture surface only.
- **Titles as a user-entered field.** See constraints.

## Fixed constraints

- **Append-only. No new `EventKind`.** A typed note writes the same events a transcribed
  one does.
- **One persistence path.** The typed note must not get its own copy of the save logic.
  The existing path has hard-won details in it — every event mirrored into the local log,
  not just the `created` one, because dropping the `tagged` events once left captures
  untagged and the project-tab filter matched nothing.
- **Titles are derived, not typed.** `ShardWriter` derives a title and documents why in
  detail: `Janitor.duplicateProposals` scores titles alone and proposes merges at ≥ 0.85
  overlap, so a constant or empty title poisons the review queue. A user-supplied title
  field would be a second title rule to keep consistent with that one.
- **Reduce screen time.** The studio guardrails are explicit that apps exist to let someone
  finish and put the phone down. This must not become a place to compose.
- **`SentCaptureItem.audioURL` is already `URL?`** — "the note outlives its audio". A typed
  note is a case the model already anticipated, not a schema change.
- **The eval gate.** `unli-001`…`unli-008` are unconfirmed hypotheses. Nothing here is
  predicted agent behaviour, so the gate does not block it.

## Questions discovery could not settle

- **Sheet or inline composer?** The capture screen has three layouts — iPad regular-width
  side-by-side, and two phone orders driven by `store.layoutPlacement`. An inline composer
  must work in all three; a sheet sidesteps that. The plan picks one.
- **Should a typed note be visually marked in the list** as having no audio, or should its
  absence of a play button be the only signal? Distinguishing is honest; marking it may
  imply a second-class note.
- **Does the Action Button / App Intent surface need a typed equivalent?** Probably not —
  an intent exists to start recording hands-free, which is the opposite need. Left alone.
