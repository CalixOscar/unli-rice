# REVIEW — pre-mortem of docs/PLAN-restore-stranded-notes.md

**Requested by:** the founder, 2026-11-08
**Reviewer:** codex, on its best model
**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/restore-stranded-notes.md`. Change nothing else: no code, no config, no
other docs, no `memory.md`, no commits. Don't edit `docs/PLAN-restore-stranded-notes.md`
or this brief. Don't start any nested `codex` run. **Do not call any Unli Rice tool that
writes** (`create_note`, `append_to_note`, `tag_note`, `untag_note`, `archive_note`,
`unarchive_note`, `flag_for_review`, `resolve_review`), and do not move, copy over or edit
any `events.jsonl`. Reading is fine: the source files, and the old log at
`~/Library/Application Support/Unli Rice/events.jsonl` if your sandbox allows it (say so
if it doesn't; that is not a failure). No build or test run is needed: the plan changes no
code.

## What you are reviewing

`docs/PLAN-restore-stranded-notes.md` is Claude's plan to repair data, not a feature. On
2026-07-21 the default event log moved into the App Group container and a 237-note log in
`Application Support/Unli Rice/` was left behind. The founder chose the plan's
recommended options on 2026-11-08:
- D1: bring back only the six hand-written notes that are truly missing (5 `Wiki:` hubs
  and `Corpus reset 2026-07-20`).
- D2: re-create them through the installed connector (`create_note` + `tag_note`, as
  `claude`), each with a provenance line, instead of building an import that replays the
  original events.
- D3: after verification, move (never delete) the old log into `Backups/` so the
  `CorpusHealth` "Found notes in an older location" notice clears.

## Try to break it

Check the plan against the code. The code wins over the plan. For each point, say whether
the plan is right, wrong (with file:line), or missing a step.

1. **Notice clearing (D3, A4).** Does moving the file out of
   `DataLocation.predecessorEventLogURLs()` really clear the notice? Is the notice
   persisted or dismissed anywhere (`notices.json`, `AppStore+Notices.swift`) so that it
   lingers, or comes back? Does anything else look at that directory: the launch
   adoption in `migrateLegacyStoreIfNeeded`/`storeToAdopt`, the agent, the CLI, a
   fresh-install path? Could the move cause a *re-adoption* or a fork on some launch path?
2. **Title resolution.** The plan claims duplicate titles resolve oldest-first
   (`Projector.swift:161`), and excludes clashes for that reason. Is that right? Do the
   six restored titles collide with anything, including case-insensitively or after the
   normalisation `WikiLink`/`LinkIndex` applies?
3. **Connector writes.** Can `create_note` take a body this long (up to ~4,400 chars)
   with `[[links]]` intact? Does it apply its own title rules, add a source, or trigger
   the janitor/autopilot to retag or rewrite the restored notes? Is `tag_note` needed, or
   does `create_note` take tags?
4. **Sync.** Will the new events reach the phone without trouble (`Sync/ShardPublisher.swift`,
   `ShardImporter.swift`)? Is there any risk to the live log from the move in A4 while the
   app, its agent or the ~10 running `unlirice-mcp` processes hold the old file open?
5. **Link health.** After restore, will the hubs' `[[links]]` resolve to the live notes the
   plan counts (19/20 for `Wiki: Nuptia`, and so on)? Is it right that appending to
   `Wiki: index` is enough to make them reachable?
6. **Anything the plan gets wrong about what is missing**: the counts in §1, the choice to
   leave the 165 ingest summaries behind, or the vault's own `events.jsonl` being out of
   scope.
7. **Order and rollback.** If A2 fails halfway (three notes written, then an error), what
   state is the founder left in, and does the plan say how to recover? Should A4 wait for
   a phone sync check?

## Format of `docs/dialogue/restore-stranded-notes.md`

```
# Dialogue — restore-stranded-notes

## Pre-mortem — codex, 2026-11-08
Verdict: ship as is | ship with changes | rethink

### Findings
1. <severity: blocker | should-fix | nit> — <one-line claim>
   Evidence: <file:line or command and output>
   Change to the plan: <exact change>
...

### What I checked and found fine
- ...

### What I could not check, and why
- ...
```

Put the most severe findings first. Write plainly: the founder is not a senior developer.
Stop when the file is written.
