# PLAN — record a note against a repo, from the phone

**Stage:** 2 (Claude's plan). **Not built.** Codex pre-mortem next, then a stage-4
revision, then the swarm.
**Date:** 2026-09-02
**Branch:** fresh off `main` — `feature/repo-voice-notes`. Step 0, not step 4.
**Depends on:** `ReposSnapshotView` (built) and `check-repos.sh --publish` writing to the
phone's iCloud folder (built 2026-09-02 — before that the screen had nothing to render).

## Why

The phone can now show the Mac's branches. The thing you actually want to do while looking
at them — "leave a note about this branch" — is the one thing it cannot do. Every existing
capture path creates a note *about nothing in particular*; this is the first place in the
app where the subject is already on screen.

## The decision this plan turns on

**What is the note?** Two shapes, and they are not interchangeable:

| | One note per repo, appended | A new note per recording |
|---|---|---|
| Reads like | a running log for that project | a stream of separate thoughts |
| Uses | `.appended` — already exists, already projects | `create_note` — already exists |
| Title | permanent, e.g. `Repo: Nuptia` | `Voice note — <timestamp>` |
| Risk | the note grows without bound | the notes list fills with fragments |

**Recommendation: one note per repo, appended.** It matches what the subject actually is —
a project you return to — and it reuses `.appended`, which `Projector` already folds with a
`\n\n---\n` separator. It adds **no new `EventKind`**, which matters: title immutability is
load-bearing because `Projector.resolveLinks` matches wiki-links by title precisely because
no `retitled` event exists.

The bound is the risk, and it is the same one `memory.md` exists to answer. Cap the repo
note's growth the way the studio caps working state, or accept that it is a log and let it
grow — but decide, do not discover.

## Phase 1 — the write path

`appendToCapture(noteID:text:)` already exists (`CaptureStore.swift`), and
`ShardWriter.writeAppendEvents` already emits one `.appended` event mirrored through
`appendRaw`. Nothing new is needed to write.

What is missing is **resolving the note for a repo**:

- `noteID(forRepo:)` — find the note titled `Repo: <name>`, creating it on first use.
  Titles are permanent by design, so the title IS the key. Do not store a mapping; a
  mapping can disagree with the corpus, a title cannot.
- Tag it `repo` plus the repo name, so the Mac can find these without a new field.

## Phase 2 — the control

A mic button on each repo card in `ReposSnapshotView`, not a global one — the subject is
the row it sits in.

**The recorder is a singleton and so is the state machine.** `Recorder.shared` is one
instance and `CaptureStore.state` is one state machine, so this must route through
`CaptureStore` with an explicit target — the `appendTargetNoteID` seam that already exists
for note-detail voice append — rather than opening a second recording path. Disable the
repo mic whenever `state` is not idle, and the main record button while a repo recording is
running. Two recorders running at once is the failure this prevents.

## Phase 3 — what the note should say

A voice note that says only *"the paywall branch is a mess"* is worthless in a month.
Prepend the state at the moment of recording, from the snapshot already on screen:

```
[Nuptia · feature/paywall-optimization · 1ad0d48 · local only · 2026-09-02]
<transcript>
```

This is free — the data is in `RepoSnapshotFile` — and it is the difference between a
thought and a record. **Mark the snapshot's age** if it is stale: the note should not imply
the branch state was current if it was a day old.

## Out of scope — flag, do not decide

- **Acting on a repo from the phone.** No delete, no push, no branch. The phone has no
  repositories and this plan does not give it any.
- **Editing or deleting a previous entry.** Append only. The event log is append-only and
  `.appended` is the only kind used here.
- **Live repo state.** The phone renders a photograph. A note recorded against a stale
  snapshot records what you saw, which is the honest thing to capture.
- **Mac-side recording.** Different app, different plan.

## Verification

```bash
cd ~/Documents/Projects/"Unli Rice" && xcodegen generate && swift build && swift test
```

1. Record against a repo → a note titled `Repo: <name>` appears, tagged `repo`.
2. Record against the same repo again → the SAME note grows, separated by `---`. The notes
   count does not increase.
3. The header line carries repo, branch, sha and date from the snapshot.
4. Force-quit and reopen → both entries survive (they are in `events.jsonl`, not memory).
5. Main record button is disabled while a repo recording runs, and vice versa.
6. **Cross-device, the check that catches the tag-class bug:** append on the phone, open
   the Mac, confirm the text is on the same note. If it is missing, the `appendRaw` mirror
   was skipped — the exact failure `CaptureStore.swift:485-491` documents.

## For the pre-mortem (stage 3)

Weakest assumption: that one note per repo is the right shape. If these are mostly one-off
observations rather than a running log, the appended note becomes a wall nobody reads and a
per-recording note would have been right. Attack that before the code exists — it is a
one-line change now and a migration later.

Second: the header line embeds a snapshot that may be stale, and a note that *looks*
authoritative about branch state is worse than one that admits it was a photograph.
