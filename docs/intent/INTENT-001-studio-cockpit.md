<!-- INTENT — the WHY, written at stage 1, before any architecture exists.
     Template: ~/Documents/Unli Rice Vault/scripts/templates/INTENT.md
     Never edited to match what got built; superseded by a new INTENT if it turns
     out to be wrong. -->

# INTENT-001 — Studio cockpit

**Date:** 2026-09-02
**Author:** founder, via Claude Code (discovery was a written brief, not a Spark session)
**Status:** draft
**Plan:** `docs/PLAN-studio-cockpit.md`

## The problem

The studio's rules exist and are written down, but nothing makes them arrive. The guardrails
live in `~/Documents/Unli Rice Vault/_AI Context/04_Guardrails.md` and bind only the tools
that happen to read them. Work is lost or stranded without anyone noticing: on 2026-09-02 a
scan found 22 unpushed commits on this repo's own feature branch, one forgotten stash in
Nuptia, and five projects with no upstream at all — none of which was visible anywhere the
founder actually looks. And a note that was supposed to say what is happening right now had
grown to 119,551 characters, so the state an agent needed was there but unfindable.

Every one of those is the same shape: the information exists, and nothing surfaces it at the
moment it matters. Shell scripts now cover the enforcement half (`check-repos.sh`,
`lint-memory.sh`, `check-secrets.sh`, the pre-commit hook). What they cannot do is be
*seen* — a script only reports when it is run, and a pre-commit hook only fires when someone
is already committing.

## Who hits it, and when

The founder, at the start of a work session, deciding which project to open — and after a
session ends abruptly on a usage limit, with no memory of what was left uncommitted. Also
every agent that starts a session in a project folder and has to reconstruct current state
before it can do anything useful.

## What "solved" looks like

Opening Unli Rice answers, without typing a command: which projects have work that exists
only on this machine, which are missing a required artifact, and what each one's current
state is. And an agent connecting over MCP can obtain the studio guardrails and the
project's `memory.md` in one call instead of knowing three absolute paths by heart.

## Scope boundaries — explicitly NOT this

- **Not a git client.** No commit, push, pull, fetch, merge, branch, or stage. Read-only
  reporting on local state. The founder commits in his own terminal.
- **Not a replacement for the shell scripts.** They stay canonical and keep working with the
  app closed and on any machine. The cockpit reads the same state; it does not become the
  only way to check it.
- **Not an editor.** It surfaces `memory.md` and `PROJECT_NOTES.md`; it does not write them.
- **Not a rule engine.** Guardrails stay prose in the vault. The app serves them, and never
  becomes a second place they are written.
- **No new note-mutation surface.** Nothing here touches the event log or adds a way for an
  agent to apply a structural change.

## Constraints that are already fixed

- The four locked decisions in `PROJECT_NOTES.md` — append-only log as source of truth,
  `Note` as a rebuilt projection, no destructive delete, structural changes propose-only.
- Shipped on the Mac App Store since 2026-08-01. **Sandboxed.** Reading arbitrary paths
  under `~/Documents/Projects` requires user-granted security-scoped bookmarks, and
  executing `git` is not a thing a sandboxed App Store app may casually do. This is the
  binding constraint on the whole idea and the plan has to answer it first.
- Vault guardrails: no third-party analytics, no engagement patterns, privacy-first,
  on-device processing. A dashboard that invites you to sit and watch it fails the product
  philosophy — this must be a glance, not a destination.
- The vault is the single source of truth for rules. The app may read it; it may not own it.

## Open questions for stage 2

1. How does a sandboxed app read git state — a user-granted bookmark on
   `~/Documents/Projects` plus its own git plumbing, a non-sandboxed helper, or a scheduled
   write from `check-repos.sh` into a file the app is already permitted to read?
2. **An MCP server cannot prepend anything to a client's system prompt.** It offers tools,
   resources and prompts, all of which the client chooses to invoke. So "inject the
   guardrails at session start" has to become something else — which of tool, resource, or
   the existing `UserPromptSubmit` hook is it? (`Scripts/unlirice-prompt-hook.py` already
   exists for this and is registered in no settings file.)
3. Does "artifact enforcer" block anything, or only report? Locked decision #3 says this
   codebase proposes rather than applies, which argues for reporting only.

## Feasibility notes from discovery

The enforcement layer is already real and tested: `check-repos.sh` produced correct output
against all fourteen project folders on first run, and the pre-commit hook was verified to
block and then pass on a real commit. So the cockpit is a presentation and transport problem
over state that already exists in files — not new analysis. That is the reason to believe
the scope is small. The sandbox question is the one that could make it large.
