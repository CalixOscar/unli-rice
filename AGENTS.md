# Agent conventions for Unli Rice / unlirice-mcp

Read this if you're an LLM coding agent (Claude Code, Codex, Antigravity, or
anything else) working on this project and connected to the `unlirice`
MCP server. It's a shared, append-only note log — multiple different agents,
possibly running concurrently on different parts of this app, read and write
into the *same* file. These rules exist so notes from three different tools
still add up to something coherent, including for whatever agent picks this
project up years from now with zero memory of this session.

For the underlying architecture and *why* it's built this way (append-only
log, no delete, propose-don't-apply for structural changes), see
`PROJECT_NOTES.md` — that's the authoritative technical record, not repeated
here.

## Before you start

Call `search_notes` or `list_notes` first, not just at the end of a session.
Another agent may have already written the note you're about to duplicate,
or left a decision you need to know about before touching related code.

## Identify yourself consistently

`source` is a required argument on every write tool
(`create_note`/`append_to_note`/`tag_note`/etc.) and is a plain string — the
server does not validate it against a fixed list. Use your own tool's name,
lowercase, the same way every time: `claude`, `codex`, `antigravity` (or
whatever you actually are). This is the only thing that makes multi-agent
history attributable later — get it wrong and the audit trail lies.

## `janitor` and `ingest` are reserved sources — don't write as either

Two writers aren't chat agents:

- the local janitor (`Sources/UnliRiceCore/Janitor/`) writes as
  `source: "janitor"`
- the data pipelines (`Sources/UnliRiceCore/Ingest/`) write as
  `source: "ingest"`

Never use either string as your own identity, whatever you are. They're the
only way the log can answer "did a reasoning agent conclude this, or did a
machine put it there?".

### What an `ingest` note is

A note written by `ingest` is an **index entry, not a thought.** It points at a
file in the `raw/` folder next to `events.jsonl` — a Claude Code session
transcript, or a document from a folder the user nominated — and summarises it
just enough to decide whether it's the one you want. The body carries a
`**Raw:** \`<filename>\` [raw:<digest>]` line; that marker is the pipeline's
deduplication fingerprint, so leave it in place if you quote the body.

Read these freely. But:

- **Don't treat an ingested summary as a conclusion.** It's a machine-built
  description of a file, generated without anything reading the file for
  meaning. If it matters, open the raw file.
- **Don't append your own reasoning onto one.** Write your conclusion as its
  own note and `[[link]]` to the index entry by title. Ingest re-appends to
  these notes whenever the underlying file changes, so anything you add is
  liable to end up buried under revision entries.
- **Ingest will never touch a note it didn't create**, so your notes are safe
  from it even if a title collides — it skips instead.

Two more things follow for you:

- **Flags whose `source` is `janitor` are machine-generated proposals**, not a
  colleague's considered judgement. A janitor flag reason ends in a
  `[janitor:...]` marker — that's its deduplication fingerprint, not content.
  Leave it in place if you quote the reason; stripping it can cause the same
  proposal to be raised at you again.
- **Tags added by the janitor are suggestions.** If one is wrong, `untag_note`
  it — the janitor reads the log for human/agent untagging and will not put it
  back. That's the intended correction channel, and the only one.

The janitor operates under the same hard rule you do: it can add a tag or
raise a flag, and nothing else. It cannot archive, retitle, merge, or resolve.
If you're extending it, that boundary is enforced in the type system —
`JanitorProposalKind` has no case for those, on purpose.

## Titles are permanent — choose them like it

A note's title is set once at `create_note` and never changes; there is no
rename/retitle tool, on purpose. Two things depend on that:

- **Wiki-links resolve by exact title, case-insensitive.** `[[Auth Flow]]`
  in a note body links to whatever note is titled "Auth Flow" — use this to
  connect notes across the parts of the app different agents are building.
- **Never leave a title blank or generic** ("Notes", "Update", "WIP"). An
  empty title silently becomes "Untitled" and is indistinguishable from
  every other empty-titled note two years from now. Write the title as if a
  different LLM will be scanning a flat list of fifty of these with no other
  context.

If you're adding to an existing concept, prefer `append_to_note` over
`create_note` with a similar title — a second note with almost the same
title just creates an orphaned, unlinked duplicate (there's no automatic
duplicate-title detection yet).

## Tags are your namespace

There's no separate "project" or "module" field. Use `tag_note` with a
short, stable tag per area of the app you're working on (e.g. `auth`,
`billing`, `frontend`) so notes from different agents working different
parts stay filterable later via `search_notes`.

## Never resolve a conflict yourself

If you suspect two notes (possibly written by different agents) duplicate,
contradict, or should be merged, call `flag_for_review` with a clear
`reason` and stop there. Do not try to reconcile it by editing, archiving,
or appending a "correction" to someone else's note — `resolve_review` is a
human action. This is a hard rule of the system, not a suggestion: there is
no tool that lets you apply a structural change, and none should ever be
added that does.

## There is no delete

`archive_note` is the closest thing — soft, fully reversible with
`unarchive_note`. Never treat archiving as cleanup for something you got
wrong; archive only when a note is genuinely obsolete, and say why in
`reason`.
