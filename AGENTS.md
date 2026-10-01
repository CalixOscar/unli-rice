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

> Before writing a new technical claim into these notes — or repeating one
> already here — verify it against the current repo (git log, grep, actual
> code), not just against what a prior note says. Notes can be wrong; code is
> ground truth. If a claim can't be verified from this repo (e.g. App Store
> Connect status), mark it explicitly as unverified instead of stating it as
> fact.

## Open plan — Note Contract validation

`docs/PLAN-note-contract.md` is a stage-2 plan — architecture, files to
touch, edge cases, gotchas — for structural validation on the MCP write path,
so `create_note`/`append_to_note` stop accepting note shapes that contradict
themselves. **Not built, and not yet pre-mortemed.** Next step is Codex
against §9 "Open questions", then Claude revises, then the swarm builds it.
If you are picking up implementation work here, read it first rather than
re-deriving the design. Left by Claude Code 2026-08-29.

## Before you start

Read the note titled **`Wiki: index`** first — not `list_notes`. It is the top of
the wiki layer and it exists precisely so you don't have to list a corpus of a few
hundred index entries to find the four that matter.

Then call `search_notes` for your specific topic. Another agent may have already
written the note you're about to duplicate, or left a decision you need to know
about before touching related code.

## The wiki layer

Three layers, and knowing which one you're holding is most of using this well:

1. **`raw/`** — verbatim copies of ingested files and session transcripts, next to
   `events.jsonl`. Hundreds of them. Nothing reads these by default.
2. **Index entries** — the `Session:` and `Doc:` notes written by `ingest`, one per
   raw file. Machine-built descriptions, *not* conclusions (see below).
3. **Wiki hubs** — notes titled `Wiki: <topic>` and tagged `wiki`, written by a
   reasoning agent. Each says what exists for a topic and where the authority
   actually is. `Wiki: index` links to all of them.

The hubs are the only layer with judgement in them, which is exactly why they're
the layer that rots. **If you add something substantial, update the relevant hub in
the same session.** Don't leave it for a routine — a hub that has drifted from the
corpus is worse than no hub, because it gets trusted. Equally: if a hub has stopped
earning its place, archive it. The system serves you, not the reverse.

A hub is a table of contents, not an essay. If you're writing a third paragraph of
reasoning into one, that reasoning wants to be its own note that the hub links to.

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

## Filing a to-do item for another project

Noticed something worth doing later, but not now — a version gate, a field that
unlocks on next release, a small inconsistency not worth stopping for? File it:

1. `create_note`. **The title is one plain sentence a non-developer understands.**
   Say what needs doing and, if it fits, why. Keep file paths, branch names, code
   names, version numbers and acronyms out of the title; they go in the body. The
   list is shown on a desktop widget that anyone at the screen may read.
   - ✗ "Bump ClearSpace Marketing URL field post-redirect"
   - ✓ "Update the website link on the ClearSpace App Store page"
   - ✗ "Fix flaky SnapshotTests on CI"
   - ✓ "Fix the automatic check that sometimes fails for no reason"

   **Body:** first line exactly `Handoff-ID: <uuid of your handoff note>` (the id
   `create_note` returned; see "At every handoff" below). Nothing else goes on that
   line. The app links by this id, never by title. Then two parts, in this order:
   - **Plain part, for the founder** — two or three sentences a non-developer can act
     on: why it matters, and either what *they* need to do (sign in somewhere, decide
     something, approve something) or "An AI can do this — use Fix with AI." No
     commands, file paths, code names or acronyms here; explain a product name the
     first time ("Vercel, the service that hosts the website").
   - **`For the AI picking this up:`** on its own line, then everything technical:
     what you found, why it's deferred, commands, paths, branches, evidence.

   ✓ *"The website's hosting account is full, so new changes to calmdownoscar.com
   can't go live. You need to sign in to Vercel (the service that hosts the site) and
   delete old copies of the site — an AI can walk you through it."*
2. `tag_note` with the fixed tag `todo`.
3. `tag_note` again with the target project's exact folder name under
   `~/Documents/Projects`, lowercased — e.g. `calmdownoscar`, not `CalmdownOscar` or
   `clearspace`. This has to be the *project* (the repo), not the feature inside it;
   the To Do pane matches by repo name.

It surfaces in the To Do pane's "flagged by AI" section next time anyone looks, on
both the Mac app and Capture. You don't file it against the project you're in by
default — name the one it's actually about, which may not be this one.

`todo` joins `janitor` and `ingest` as a reserved string, but as a *tag*, not a
`source` — do not use it for anything other than these deferred items.

Before you start on a project, check whether it has open to-do items — the prompt
hook injects them if one is installed, and `search_notes` for the project's tag
finds them if not. If there are any, ask the founder whether to fold them into this
pass. Ask; do not just do them. They were deferred deliberately and the reason may
still hold.

## At every handoff

Every LLM, every project. Do this at each checkpoint, meaning each commit where you
update `memory.md` (or the Handoff in `PROJECT_NOTES.md`), not only at the end. A session
can be cut off without warning.

0. **Catch up first.** If `**To-dos:**` says an earlier session "would have filed"
   items because Unli Rice wasn't connected, file them now, then say so.
1. **Write one handoff note — only if you are filing a to-do in step 2.** It is the
   note the founder lands on when they tap that to-do, and it feeds the "copy a prompt to
   pick this up" action; with no to-do filed, nothing links to it and `memory.md` already
   holds the same fields. `create_note`, titled
   `Handoff — <Project> — YYYY-MM-DD HH:MM — <tool>`. The body is the handoff fields
   as they stand now, plus `git rev-parse --short HEAD`, written for someone resuming
   cold. `tag_note` it `handoff` and the project tag (lowercased folder name). `handoff`
   is a reserved tag, like `todo`. Never append to an earlier handoff note; each
   checkpoint that files a to-do writes a new one. (Narrowed 2026-09-24, founder
   decision: a handoff note at every checkpoint duplicated `memory.md`.)
2. **File what you deferred** as to-do items (above), each body starting
   `Handoff-ID: <the uuid create_note returned for that note>`.
3. **Close what you finished, and only that.** `archive_note` with a reason naming the
   evidence: "done in a1b2c3d". Never close something you did not do. Never close one
   because it looks stale or obsolete; use `flag_for_review` for that. Closing is
   soft: the founder sees it under Archived and can reopen it.
4. **Record it in the `**To-dos:**` field**: "filed 2 (<titles>); closed 1
   (<title>, a1b2c3d)", or "none this checkpoint". The pre-commit linter refuses a
   `memory.md` / Handoff where the field is missing or empty. It cannot check that
   what you wrote is true; the evidence rule does that job, as for every other claim.

No MCP server connected? Say so in `**To-dos:**` ("Unli Rice not connected; would
have filed: …"). That keeps the items from being lost.

Chat apps (claude.ai, the ChatGPT app) have no `memory.md` and no pre-commit. For them
this section is advisory only. A short version is planned for the MCP server's
instructions (`docs/PLAN-todo-widget.md` Part C); it is not built yet.

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
wrong; archive only when a note is genuinely obsolete, or when it is a to-do
item you finished in this session (see "At every handoff", step 3), and say why in
`reason`.
