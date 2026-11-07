# PLAN — bring back the notes left behind in July's old store

**Intent:** none. This is a data repair, not a feature; §0 is the brief.
**Planner:** claude. **Reviewer:** codex.
**Stage:** 2 draft, founder decisions taken (§2); in pre-mortem
**Pre-mortem:** requested from codex 2026-11-08, `docs/dialogue/restore-stranded-notes.md`
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
- **The notice clears only when every missing id reaches the live log, or the old file is no
  longer at that path.** Re-creating notes under new ids does not clear it.
- Sync publishes appended events by cursor, and treats events with no `device` as from this
  Mac (`Sync/ShardPublisher.swift:63-72`). Restored events would therefore sync to the phone.
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
  after the restore is verified. The 228 notes left behind remain readable there.
- Alternative: leave it, and keep a permanent warning in the app.

**Decided by the planner (dated, so they don't age):** the restored hubs keep their July
text unedited. The provenance line says "written 2026-07-20; may be out of date". They are
linked from the live `Wiki: index` by an append, not a rewrite.

## 3. Point of view and patterns

No user-facing surface.

## 4. Journey and states

No user-facing surface. The only visible effect is the stranded-notes notice going away
after A4.

## 5. Tasks

Assumes D1 = six notes, D2 = connector, D3 = move. Re-plan if any answer differs.

### A0. Preconditions
- [ ] `planner` Confirm the installed app is the one serving the connector. Done when:
      `unlirice-mcp` stderr names the App Group log. Verify: start the connector and read
      its first stderr line.
- [ ] `planner` Snapshot before writing. Done when: the live note count and the list of
      ids and titles are saved to the session scratchpad. Verify: `list_notes(include_archived: true)`
      returns 540 notes (or the current count, recorded).
- [ ] `planner` Back up the old file, read-only copy. Done when: a byte-identical copy
      exists. Verify: `shasum -a 256` of the original and the copy match.

### A1. Dry run
- [ ] `planner` Rebuild each chosen note from the old log: the `created` text plus its
      `appended` texts in order, with its tags. Done when: six files in the scratchpad hold
      the body and tags each note would get, with the provenance line on top. Verify: the
      founder reads the list of titles; every body is non-empty.
- [ ] `planner` Re-check clashes right before writing. Done when: none of the chosen titles
      are live. Verify: `search_notes(<title>)` returns no exact title match for each.

### A2. Restore
- [ ] `planner` For each note: one `create_note`, then a `tag_note` per original tag
      (`wiki` or `changelog`). Done when: each `create_note` returns an id; record them.
      Verify: `get_note(<new id>)` body equals the dry-run file byte for byte;
      `note_history` shows `source: claude`.

### A3. Wire up
- [ ] `planner` Append to `Wiki: index` one dated block linking the restored notes.
      Done when: `get_note(Wiki: index)` shows `outboundLinks` containing all restored ids.
      Verify: `danglingLinks` on each restored hub matches §1 (only the old-store-only links
      dangle).

### A4. Retire the old file (founder approves this step separately)
- [ ] `planner` Move the old log into `Backups/` under the D3 name. Done when: the original
      path no longer exists and the moved file's SHA-256 equals the A0 copy. Verify:
      `shasum -a 256`, then relaunch Unli Rice; the "Found notes in an older location"
      notice is gone. `CorpusHealth` runs at launch.

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
- The 1 old-store-only link in `Wiki: Nuptia`, 3 in ClearSpace and 1 in CalmdownOscar will
  dangle, because they point at July ingest summaries that stay in the backup.
- The vault's own `events.jsonl` (242 lines, 2026-07-20) is a separate, abandoned store and
  out of scope.

## 8. Rides along or deferred
- None. If the founder later wants the 165 ingest summaries, that is D2's alternative
  (the `unlirice-cli` restore command) as its own tier-2 plan.

## 9. Pre-mortem responses

Not run yet.

## Handoff

Every step is `planner`: each one writes the founder's data through the connector or moves
a data file, and none of it is code. No builder is used.

## Build notes
