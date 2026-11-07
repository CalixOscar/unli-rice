# PLAN — bring back the notes left behind in July's old store

**Intent:** none. This is a data repair, not a feature; §0 is the brief.
**Planner:** claude. **Reviewer:** codex.
**Stage:** 5 built: A0–A4 done 2026-11-08; Clear in Notices is the founder's call
**Pre-mortem:** `docs/dialogue/restore-stranded-notes.md` (codex, 2026-11-08: ship with changes), answered there and in §9
**Founder decisions (2026-11-08):** "go with the recommended options". D1 = the six
hand-written notes, D2 = re-create through the connector, D3 = move the old file to
`Backups/` after verification.
**Branch:** `claude/restore-stranded-notes-plan`
**Verified against:** `8e67d95` on `main`, live store read through the installed 1.5.1 (13) connector on 2026-11-07

## 0. What was asked for

> "draft the merge plan for the stranded notes" (founder, 2026-11-07)

Context: the August proposal on `Wiki: index` (flag `B0638231`, marked resolved) was to
append the old log into the live one. It never happened: the old file is unchanged since
2026-07-20 23:15 and `search_notes("Wiki: Nuptia")` finds no hub.

## 1. What already exists (checked, not assumed)

**The old store:** `~/Library/Application Support/Unli Rice/events.jsonl`. It has 724
events, all parse, and they run from 2026-07-19 to 2026-07-20. It holds 237 notes, none of
them archived. 697 of the events come from `ingest`, 22 from `claude`, 2 from `janitor`,
2 from `unlirice` and 1 from `antigravity`. The events predate the `device` and
`causalParents` fields. Both are optional in `Sources/UnliRiceCore/Event.swift:65-67`.

**The live store:** the App Group log, as opened by `unlirice-mcp` ("ready, event log at
…/group.com.calmdownoscar.unlirice/Unli Rice/events.jsonl"). It has 540 notes, 5 of them
archived. Shell access to it is denied by macOS; the connector is the only way in.

**What is actually missing.** Compared by note id, then by title:

| Group | Count | Status |
|---|---|---|
| Hand-written, missing | 6 | `Wiki: Nuptia`, `Wiki: ClearSpace`, `Wiki: CalmdownOscar`, `Wiki: Architecturally`, `Wiki: studio context and guardrails`, `Corpus reset 2026-07-20` |
| Hand-written, title already live | 3 | `Wiki: index`, `Wiki: Unli Rice`, `How to use these notes`. The live versions are newer. |
| Hand-written, same id already live | 1 | `Janitor role and permission boundary` |
| Ingest summaries, title already live | 62 | re-ingested 2026-08-20 |
| Ingest summaries, not live | 165 | 154 `Session:` summaries of July Claude sessions, 11 `Doc:` copies of July files |

**Link health of the six missing notes.** Links resolve by title, counted as
links / live / old store only / nowhere:
- `Wiki: Nuptia`: 20 / 19 / 1 / 0
- `Wiki: ClearSpace`: 6 / 3 / 3 / 0
- `Wiki: CalmdownOscar`: 4 / 3 / 1 / 0
- `Wiki: Architecturally`: 4 / 4 / 0 / 0
- `Wiki: studio context and guardrails`: 11 / 1 / 9 / 1. It mostly points at July copies of
  the studio files, which `_AI Context/` has since replaced.
- `Corpus reset 2026-07-20`: 4 / 3 / 1 / 0

**Relevant code:**
- The app warns but never merges. `CorpusHealth.check` (`Sources/UnliRiceCore/CorpusHealth.swift`)
  compares the note ids in `DataLocation.predecessorEventLogURLs()`. Those are exactly
  `Application Support/Unli Rice/events.jsonl` and `Application Support/SecondBrain/events.jsonl`
  (`DataLocation.swift:122-130`). It posts the "Found notes in an older location" notice
  (`NoticeFactory.swift:175`).
- **A new warning stops appearing** only when every missing id reaches the live log, or the
  old file is no longer at that path. Re-creating notes under new ids does not do it.
  **A warning already saved is never taken back.** `checkCorpusHealth` returns early when
  there are no findings (`AppStore+Notices.swift:95-97`), and `NoticeStore` keeps notices
  until the founder uses Clear (`NoticeStore.swift:49-93`). Clear removes every notice.
- Sync: the connector stamps its own device label on new events (`unlirice-mcp/main.swift:74`),
  and which path carries them to the phone depends on the sync mode: the shared folder
  (`AppStore.swift:836-856`) or native iCloud (`AppStore+NativeSync.swift:71-95`).
  Reading the code proves neither the mode nor delivery, so phone delivery is checked in A3b.
- Duplicate titles are tolerated, but the oldest note wins resolution (`Projector.swift:161`).
  A restored July `Wiki: index` would quietly replace the live one in every `[[link]]`.
  That is the reason title clashes are excluded.

## 2. Decisions (founder)

**D1: which notes come back.**
- Recommended: the 5 project hubs plus `Corpus reset 2026-07-20`. These are the only
  hand-written notes that are truly missing.
- Optional extra: skip `Wiki: studio context and guardrails`. It is superseded by
  `_AI Context/` and 9 of its 11 links lead to July copies.
- Not recommended: the 165 ingest summaries. They are automatic July indexes, not
  conclusions (studio rule). The files they summarised have moved on.
- Never: the 66 title or id clashes.

**D2: how they come back.**
- Recommended: re-create the chosen notes through the installed connector (`create_note`,
  `tag_note`) as `claude`. Each body starts with a provenance line naming the original id,
  author and date. No code change and no app build, and it is append-only.
  Cost: the original timestamps and authorship stay only in the old file.
- Alternative: build a one-off "restore from older location" command into `unlirice-cli`
  that appends the original events verbatim (same ids, timestamps and sources). It keeps
  full history, but it is a tier-2 code change to the persistence layer, with its own build,
  tests and pre-mortem. That is a lot of work for six notes.

**D3: the old file afterwards.** It has to move for the warning to clear (see §1).
- Recommended: move it, never delete it, to
  `~/Library/Application Support/Unli Rice/Backups/events-stranded-2026-07-20.jsonl`
  after the restore is verified. The backup keeps all 237 original notes and their
  history; six of them are re-created in the live store.
- Alternative: leave it, and keep a permanent warning in the app.

**Decided by the planner (dated, so they don't age):** the restored hubs keep their July
text unedited. The provenance line says "written 2026-07-20; may be out of date". They are
linked from the live `Wiki: index` by an append, not a rewrite.

## 3. Point of view and patterns

No user-facing surface.

## 4. Journey and states

No user-facing surface. Visible effects: six notes appear in the app; after A4 the
stranded-notes warning stops being raised, and the old saved copy goes when the founder
uses Clear in Notices (A4, step 5).

## 5. Tasks

Assumes D1 = six notes, D2 = connector, D3 = move. Re-plan if any answer differs.

### A0. Preconditions
- [x] `planner` Confirm the installed app is the one serving the connector. Done when:
      `unlirice-mcp` stderr names the App Group log. Verify: start the connector and read
      its first stderr line.
- [x] `planner` Snapshot before writing. Done when: the live note count and the list of
      ids and titles are saved to the session scratchpad. Verify: `list_notes(include_archived: true)`
      returns 540 notes (or the current count, recorded).
- [x] `planner` Back up the old file, read-only copy. Done when: a byte-identical copy
      exists. Verify: `shasum -a 256` of the original and the copy match.

### A1. Dry run
- [x] `planner` Rebuild each chosen note from the old log: the `created` text, then each
      `appended` text in order, joined with the projector's exact `\n\n---\n` separator
      (`Projector.swift:82-85`). Keep the tags as well. Done when: six files in the
      scratchpad hold the body and tags each note would get, with the provenance line on
      top (original id, author, date, "may be out of date"). Verify: every body is
      non-empty and its link count matches §1.
- [x] `planner` Re-check clashes right before writing. Done when: none of the chosen titles
      are live, archived notes included, compared case-insensitively. Verify:
      `search_notes(<title>, include_archived: true)` has no exact match for each.
- [x] `planner` Start the ledger: one JSON row per note in the scratchpad with original id,
      title, the expected body's SHA-256, new id (empty) and tags done (empty).

### A2. Restore
- [x] `planner` For each note in turn: `create_note`, then **write the returned id to the
      ledger at once**, then one `tag_note` per original tag, logging each. Done when: the
      ledger has six ids with all their tags. Verify: `get_note(<new id>)` body equals the
      dry-run file byte for byte; `note_history` shows `source: claude`. A later janitor
      tag is not corruption.
- [x] **On any error or unclear reply: stop. Do not start A3 or A4.** Before retrying a
      note, search for its title (archived included, case-insensitive) and read the body
      and history of any match. If it is our note, record the id and finish its tags. Create
      a note only once it is confirmed missing. If a match differs from the expected note,
      stop and report it; do not fix, merge or archive it. Rollback is "stop with the ledger
      and the old file intact". The live log is never overwritten from a backup.

### A3. Wire up
- [x] `planner` Check `Wiki: index` for an existing restore block first. If there is none,
      append one dated block linking the six titles. Done when: `get_note(Wiki: index)`
      lists all six new ids in `outboundLinks`.
- [x] `planner` Verify each hub's `danglingLinks` against the post-restore expectation,
      recomputed now against live titles plus the six: Nuptia 0, ClearSpace 3,
      CalmdownOscar 0, Architecturally 0, studio context 9, Corpus reset 1 (computed
      2026-11-08). Any difference: stop and explain it before A4.

### A3b. Phone check (founder)
- [x] Record the sync mode shown in the Mac app's settings. On the phone, open Capture and
      check that `Wiki: Nuptia` and the `Wiki: index` block are there. If the phone isn't
      checked, record phone sync as **unverified** in the record. A4 does not touch the
      restored notes either way.

### A4. Retire the old file (founder approves this step separately)
- [x] `planner` 1. Before the move, check that every running Unli Rice process (app, agent,
      each `unlirice-mcp`) reports the App Group log, and that no override or chosen
      folder points elsewhere: the `UNLIRICE_DATA_PATH` environment variable or the app's
      folder setting.
      2. Recheck the old file's SHA-256 against A0. Abort if it changed, or if the backup
      name already exists. Never overwrite a backup.
      3. Move it with `mv -n` into `Backups/` under the D3 name. Done when: the old path is
      gone and the moved file's hash equals A0's.
      4. Relaunch Unli Rice. Verify: the old path is still absent, and the six restored
      notes still read back byte for byte. If the old path reappears, stop and find what
      wrote it; do not move it again.
      5. The saved warning stays in Notices: the app never takes one back (§1). The founder
      chooses whether to use Clear, which removes **every** notice. Nobody edits
      `notices.json` by hand.

## 6. Acceptance — against reality, not a report

**Mechanical**
- [ ] Live note count = A0 count + the number restored (verified: `list_notes`, date).
- [ ] No title in the live store appears twice where it didn't before (verified: count
      titles in `list_notes`).
- [ ] The old file is unchanged until A4, and moved with the same hash after it.
- [ ] No repository file changes except this plan.

**Record**
- Built: the notes recreated, with their new ids.
- Verified: which checks ran, with evidence. Unverified: phone sync of the restored notes,
  unless checked on the phone.

## 7. Known limits, accepted
- Restored notes carry today's timestamp and `claude` as creator; the original attribution
  lives in the provenance line and the backup file.
- After restore, 13 links stay dangling: 3 in ClearSpace, 9 in studio context and 1 in
  Corpus reset. They point at July `Doc:` copies that stay in the backup, plus one that
  was missing even in July. The Nuptia and CalmdownOscar gaps close, because they point at
  restored notes.
- The move stops this file from raising a new warning. It does not prevent a fork on every
  possible launch path, for example an unsigned build that falls back to Application Support.
- The vault's own `events.jsonl` (242 lines, 2026-07-20) is a separate, abandoned store and
  out of scope.

## 8. Rides along or deferred
- None. If the founder later wants the 165 ingest summaries, that is D2's alternative
  (the `unlirice-cli` restore command) as its own tier-2 plan.

## 9. Pre-mortem responses

Codex, 2026-11-08, ship with changes. All six findings were accepted. Findings 1 and 3
were re-checked by Claude against the code and the old log before being accepted.
1. Blocker, the saved notice is never removed: accepted. A4 now separates "no new
   warning" from "old warning cleared", and Clear is the founder's call. No code change.
2. No restart path after a partial A2: accepted. A ledger was added, plus a stop-and-check
   retry rule.
3. Wrong dangling-link expectations: accepted. A3 and §7 now use post-restore counts
   0/3/0/0/9/1.
4. Sync delivery unproven: accepted. A3b was added, and phone sync stays "unverified"
   unless checked.
5. A4 needs writer checks and a no-overwrite rule: accepted, as A4 steps 1–4.
6. The "228" count: accepted. D3 now says all 237 stay in the backup.

Not acted on: Codex's test run (638 executed, 24 failure reports in the NativeCloud tests,
inside its sandbox). This plan changes no code. The suite was re-run outside the sandbox
and the result is recorded under Build notes.

## Handoff

Every step is `planner`: each one writes the founder's data through the connector or moves
a data file, and none of it is code. No builder is used.

## Build notes
- 2026-11-08, Claude: `swift test` outside Codex's sandbox on `d51e528` ran 638 tests,
  2 skipped, 0 failures. Codex's 24 NativeCloud failures were sandbox-only (file
  coordination errors 256/512).
- 2026-11-08, Claude ran A0–A3 through the installed 1.5.1 (13) connector, which
  logged the App Group store. A0: 540 live notes; the old log's SHA-256 is `8fb86fd3…0829`,
  matching Codex's, and a copy is in the session scratchpad. No `UNLIRICE_DATA_PATH`
  override was found on any running process. A2 new ids: Nuptia `7C598ECB`, ClearSpace
  `C3D9BBA4`, CalmdownOscar `B753E042`, Architecturally `C7594599`, studio context
  `CE7B48A0`, Corpus reset `70114150`. Each body read back byte for byte, with its
  original tag. A3: the `Wiki: index` block links all six. Dangling links are
  0/3/0/0/9/1, as expected. The live store now has 546 notes and no duplicate titles. The
  old log's hash is unchanged after the restore.
- 2026-11-08, A3b: the phone shows "Published to iCloud", so sync is native iCloud
  (founder's screenshot, 00:16). The restored notes can't be seen on the phone: Capture
  lists only notes tagged with a project name (`UnliRiceCapture/CaptureStore.swift:704-706`),
  and the hubs are tagged `wiki`. **Phone delivery: unverified.**
- 2026-11-08, A4: before the move, no process held the old file, none of the 12 running
  Unli Rice processes set `UNLIRICE_DATA_PATH`, the app has no folder setting, the hash
  matched A0 and the backup name was free. The file was moved with `mv -n` to
  `Backups/events-stranded-2026-07-20.jsonl`, and its hash is unchanged (`8fb86fd3…0829`).
  The app was quit and relaunched; the old path is still absent, all six restored bodies
  read back exactly, and the store holds 546 notes. The saved warning in Notices is left
  for the founder to Clear.
