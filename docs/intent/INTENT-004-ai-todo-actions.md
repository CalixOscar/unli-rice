<!-- INTENT — the WHY, written at stage 1, before any architecture exists.
     Template: ~/Documents/Unli Rice Vault/scripts/templates/INTENT.md
     Never edited to match what got built; superseded by a new INTENT if it turns
     out to be wrong. -->

# INTENT-004 — Letting an LLM file a to-do item

**Date:** 2026-09-03
**Author:** founder, via Claude Code (a one-line brief, not a Spark session)
**Status:** draft
**Plan:** `docs/PLAN-ai-todo-actions.md`

## The problem

An LLM coding agent, mid-session on any project in `~/Documents/Projects`, routinely
notices something worth doing later that isn't worth interrupting the current task
for. The founder's own example: an agent working on the CalmdownOscar site notices a
Marketing URL field is stale now that a redirect has shipped, but the fix is gated
behind a version bump that isn't due yet. That observation is true, specific, and
useful — and today it has nowhere to go. It gets said in chat and then the session
ends, or it survives only if the founder happens to ask for a handoff before running
out of context.

The To Do pane already has a place for "what you meant to do next" — `StudioTodo.Kind
.declared`, sourced from each project's `memory.md` **Next step:** field. But that
field is singular and already occupied by whatever the project's *current* task is;
it is not a place to drop a small, low-urgency, easily-forgotten aside without
overwriting the thing actually in flight. There is no capture surface for the backlog
of small things an AI noticed along the way.

## Who hits it, and when

The founder, across every project in the studio, every time a coding agent — this one
or another tool entirely — surfaces a minor deferred action mid-session: a version
gate, a field that unlocks later, a small inconsistency not worth stopping for, a
"remind me next time I touch this" note. The cost today is that these are lost the
moment the terminal closes, unless the founder personally remembers to write them
down somewhere that gets read again.

## What "solved" looks like

1. An LLM agent working in any project — not just Unli Rice — can file a short,
   titled action item addressed to a specific project, using tools it already has
   access to.
2. It shows up as its own section in the To Do pane, on both the Mac app and Unli
   Rice Capture, next to (not merged into) the existing at-risk / next-step /
   unshared / clutter sections.
3. Each item names who flagged it and when, so a plausible-sounding claim can be
   checked rather than trusted.
4. The founder can mark one done from the UI itself — a real action, not a copied
   shell command — because unlike git state, there is nothing here the app is
   sandboxed away from.
5. "Done" is soft and reversible, consistent with the rest of the note system. Nothing
   is ever silently and permanently gone.

## Explicitly out of scope

- **Due dates, scheduling, or push notifications.** This is a list you read, not a
  reminder system with its own clock.
- **Priority levels beyond where the section sits in the existing ordering.**
- **Editing a filed item's text.** Consistent with title permanence and the
  append-only log: an item can be filed and later archived, not rewritten.
- **A reply thread on an item.** The phone's existing "leave a note about this" sheet
  already covers wanting to think out loud against an item.
- **A new MCP tool.** `create_note` / `tag_note` / `archive_note` already exist and
  are already documented; this is a read-side feature plus a naming convention, not a
  new write surface.
- **Replacing `.declared`.** The memory.md Next step field stays what it is — the
  current task. This is the backlog of small things beside it.

## Fixed constraints

- **No new `EventKind`, no new MCP tool, no `Note` schema change.** Everything needed
  — tags, `creator`, `createdAt`, `archived` — already exists on `Note`.
- **Propose, don't resolve, stays true to the agent.** An agent files the item; only
  the founder archives it as done. This mirrors decision #2 (archive is soft,
  reversible, and not something an agent does to someone else's item) more than
  decision #3 (`flag_for_review`) — this isn't a structural conflict between notes,
  it's an ordinary note an agent is allowed to create outright, the same as any other
  `create_note` call.
- **Discoverability rides the existing convention, not a new one.** Every other
  project's `AGENTS.md` already reads "conventions for using it are in Unli Rice's
  `AGENTS.md` — read that... for how to title, tag, and when to flag." A tag
  convention documented there is already reachable from every project without a
  second distribution mechanism.
- **The eval gate.** `unli-001`…`unli-008` are unconfirmed hypotheses about predicted
  agent *misbehavior*. Nothing here is a predicted failure mode — it's a new
  capability — so the gate does not block it, same reasoning as INTENT-003.

## Questions discovery could not settle

- **Where `.aiFlagged` ranks against the existing four kinds.** The plan proposes
  directly after `.declared`; it's a judgement call, not a derived fact.
- **Whether the phone should be able to mark an item done**, or whether archiving
  stays Mac-only for this pass and the phone keeps its existing "leave a note" action
  unchanged. The plan proposes the latter.
- **What happens when two sessions file near-duplicate items** against the same
  project. There is no janitor-style dedupe here; left to the founder to notice and
  archive the extra one.
