<!-- INTENT — the WHY, written at stage 1, before any architecture exists.
     Template: ~/Documents/Unli Rice Vault/scripts/templates/INTENT.md
     Never edited to match what got built; superseded by a new INTENT if it turns
     out to be wrong. -->

# INTENT-005 — The AI to-do list, on screen, in plain words, kept current by every LLM

**Date:** 2026-09-19
**Author:** founder, via Claude Code (three one-line briefs in one session, not a Spark session)
**Status:** draft
**Plan:** `docs/PLAN-todo-widget.md`
**Builds on:** `docs/intent/INTENT-004-ai-todo-actions.md` (shipped in `1b4779a`)

## The problem

INTENT-004 gave LLMs a way to file a to-do item, and the To Do pane shows them. But the
list only exists when the founder opens the app and goes to that pane. It is a place you
visit, not something you see. The founder's brief: *"a widget on the screen that has an
actionable to do list based on the chats with various llms."*

Two more briefs came in the same session:

- *"The to do list needs to be understandable by anyone reading it, also non developers."*
  Items today are written by coding agents for coding agents. The example title in
  `AGENTS.md` is "Bump the ClearSpace Marketing URL field". The subtitle reads "Flagged
  by claude, 2 days ago", where `claude` is a raw source string.
- *"All LLMs need to update the to do list as part of their hand off."* Today filing an
  item is optional, and closing one is reserved to the founder. So the list only
  grows. It is only as current as whichever agent last remembered it exists.

## Who hits it, and when

The founder, at a glance, between sessions, without opening Unli Rice. The same goes for
anyone else who looks at that screen: the list is meant to be readable by someone who
has never opened a terminal.

## What "solved" looks like

1. A Mac desktop / Notification Center widget shows the open AI-filed to-do items across
   all projects.
2. Each item can be marked done from the widget itself. Tapping an item opens the
   specific handoff it came from. A second action copies a prompt, built from that
   handoff, to paste into any AI assistant to pick the work back up. (This comes from a
   fourth brief: "pressing an item … takes me to that specific handoff, or generates a
   prompt based on the hand off.")
3. Every word on the widget reads correctly to a non-developer: who suggested it (by
   product name), how long ago, which project, and the action itself.
4. Every LLM that works on a project leaves the to-do list current at each handoff
   checkpoint. It files what it deferred and closes what it finished. This is enforced
   where the studio already enforces handoffs, not left to good intentions.
5. "Unknown" stays distinct from "nothing to do" (INTENT-002). A widget that cannot read
   the list says so and never shows an empty list.

## Explicitly out of scope

- An iOS / Capture widget. Capture reads its data a different way
  (`SharedFolderManager`), so it gets its own pass once the Mac one is proven.
- Extracting to-dos automatically from chat transcripts. "Based on the chats" is served
  by LLMs filing items through the existing MCP tools. Mining transcripts from other
  apps is a different product with a different privacy story.
- Showing the other To Do kinds (at risk, next step, unshared, clutter) in the widget.
  They are git-derived and phrased for developers.
- Rewriting existing item titles. Titles are permanent (append-only log).
- Due dates, reminders, notifications (unchanged from INTENT-004).

## Fixed constraints

- No new `EventKind`, no `Note` schema change, no new MCP tool.
- Done stays soft and reversible: `archive_note`, visible under Archived.
- The widget writes to the event log only through `NoteService`, under the same `flock`
  every other process uses.
- The eval gate (`unli-001`…`unli-008`) does not block this. It is a new capability, not
  a fix for a predicted failure mode. This is the same reasoning as INTENT-003 and
  INTENT-004.

## Questions discovery could not settle

- **Whether an agent may close a to-do item.** INTENT-004 says only the founder archives.
  "Update the to do list at handoff" reads as including "close what you finished". The
  plan proposes allowing it, narrowly. This is the founder's call.
- **Whether the handoff rule is enforced by the linter** (a new required `memory.md`
  field, studio-wide) or only written into `AGENTS.md`. The plan recommends the linter.
- **Chat-app LLMs** (claude.ai, the ChatGPT app) have no `memory.md` and no hook. For them
  the rule can only be advisory text in the MCP server's instructions.
