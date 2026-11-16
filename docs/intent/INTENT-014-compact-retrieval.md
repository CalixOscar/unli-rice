# INTENT-014 — Compact retrieval for AI tools

**Date:** 2026-11-16
**Author:** Claude Code (planner), drafted from the founder's handoff of 2026-11-16
**Status:** settled — approved by the founder 2026-11-16 ("Approve, carry on")
**Intent read:** not run — founder skip 2026-11-16 ("Skip both, record it")
**Plan:** docs/PLAN-compact-retrieval.md

## The problem

When an AI tool searches Unli Rice today it gets back every matching note in full:
the whole body, every review flag, every link and backlink. One search over a vault
of a few hundred notes can return hundreds of thousands of characters, most of it
unread. The AI pays for all of it in context, and so does the founder in usage.

The founder's words (handoff, 2026-11-16): "Reduce the amount of data and number of
calls an LLM needs to retrieve useful evidence from Unli Rice, while preserving
correctness and provenance."

There is also no measurement. Nobody can say how many bytes or calls a typical
lookup costs, so nobody can say whether a change made it better.

## Who hits it, and when

Any AI assistant connected to the vault (Claude Code, Codex, a chat app), at the
moment it tries to find a past decision. It calls `search_notes`, receives full
notes it mostly doesn't need, and its context fills. The more the founder uses the
app, the worse each search gets. The founder hits it as usage limits reached sooner.

## What "solved" looks like

- An AI can find which notes are relevant from a short, bounded answer: note id,
  title, a short piece of the real text around the match, tags, date, archived or
  not. Never more than the size it asked for.
- It can then fetch the full text of only the notes it chose, several in one call,
  again within a stated size, and is told plainly about anything left out.
- Nothing is cut silently. A shortened title or excerpt says so; a note left out
  for size says so; results that may be incomplete say so.
- A repeatable benchmark on made-up notes records, for old and new retrieval:
  whether the needed notes were found, how many calls it took, and how many bytes
  came back. If the new way is worse for some task, the report says so.
- Every existing tool behaves exactly as before.

## How it should feel

No user-facing surface: this is a connector change the founder never sees. For the
AI on the other end it should feel like a good librarian: a short list first, the
full text only on request, and an honest "there is more" when there is. The generic
version to avoid is a "smart summary" that paraphrases notes with a model. Excerpts
here are the note's own words, not a generated summary.

## Scope boundaries — explicitly NOT this

- No ranking changes, no SQLite full-text search, no embeddings, no model calls.
- No all-in-one "task context" tool, no typed relationships, no graph traversal.
- No per-client tracking of what an AI has already seen, no automatic deltas.
- No new review states, no UI, no sync changes, no event-log migration.
- No change to the existing tools' contracts, and no change yet to the connector's
  own instructions, the app's copy or the public guide. Telling assistants to prefer
  the new tools is a later step, once the benchmark shows they earn it.
- No promise of faster model responses, and no claim that a byte limit is a token
  limit: models count tokens differently.

## Constraints that are already fixed

- The append-only event log stays the source of truth; notes stay a rebuilt
  projection; no destructive delete (`PROJECT_NOTES.md`, locked-in decisions).
- No new dependencies and no new persisted format. Both tools are read-only.
- Notes whose history is incomplete or conflicting stay excluded, as today, and
  their text is never leaked.
- Tests use made-up notes in temporary stores. The founder's vault is never copied
  into tests, and no development connector is pointed at the live vault.
- Note text is user data. Retrieval never treats it as instructions.

## Open questions for stage 2

- What "the corpus changed" should mean for a half-finished page-through of results:
  any write anywhere, or only a write that changes this search's results.
- Exactly which bytes the size limit covers (the answer alone, or the whole reply
  line the connector writes).
- Which note fields a full read should carry so provenance survives without the
  bulk (history, flags and backlinks are the bulk).

## Feasibility notes from discovery

- Verified in code on 2026-11-16 (`699d3bd`): `search_notes` returns whole `Note`
  values, including `body`, `flags`, `outboundLinks` and `backlinks`
  (`Sources/unlirice-mcp/ToolDispatcher.swift:132-136`,
  `Sources/UnliRiceCore/Note.swift`). Matching is a case-insensitive substring test
  on title, body and tags (`Sources/UnliRiceCore/NoteService.swift:226-234`).
- The projection is already cached and updated incrementally, and already knows
  which notes are incomplete or conflicted (`NoteService.swift:261-294`).
- There is no existing corpus revision to reuse: the only cursor is a private byte
  offset (`EventStore.swift:32-38`).
- **Idea Clinic:** not run by this session. The founder arrived with a finished
  handoff whose scope, deferrals and acceptance list show the idea had already been
  questioned elsewhere (it cites a conceptual review that had no repo access). What
  is evidence: the code facts above. What is assumption: that smaller answers
  change how assistants behave, and by how much. The benchmark exists to test the
  second; real cross-model results are later validation, not part of this work.
- Unknown until measured: whether two calls (find, then read) beat one large call
  for small lookups. The benchmark must report this honestly.
