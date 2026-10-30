# INTENT-008 — Carry an idea into a shared specification

**Date:** 2026-10-30
**Author:** Codex, from the founder's request
**Status:** approved by founder 2026-10-30
**Intent read:** not run
**Plan:** not yet written

## The problem

The founder wants to use specification-driven development across Idea Clinic,
Unli Rice and the Python learning/agent-building work. An idea should not have
to be reconstructed from separate conversations as it moves towards a build.
The founder also reports that concurrent Claude and Codex work can leave notes
and Git state tangled and require cleanup; the desired outcome is cleaner
coordination, faster delivery and lower token use.

## Who hits it, and when

Someone has explored an idea in Idea Clinic and decides to take it further.
They need to carry the intended outcome and its open questions into subsequent
AI-assisted work, while retaining a clear distinction between a draft and a
decision. Separately, the founder coordinates Claude and Codex on the same
project and needs to know who owns the work and where its current state lives.

## What “solved” looks like

- After a Clinic discussion, the person can obtain a clearly labelled draft
  specification that captures the problem, intended user and outcome, scope,
  exclusions, observable acceptance scenarios, open questions and ways to
  verify the scenarios. Unknowns remain unknown, and the person can review and
  amend the draft before treating it as settled.
- The draft can be carried into Unli Rice for later retrieval and into the
  relevant Python learning or agent-building work without silently losing its
  meaning or turning unanswered questions into decisions. The founder says the
  agent-building work is a planned LearnPy lesson and should come last; the
  precise handoff mechanism remains open.
- Claude and Codex can work from a clearly identified shared version with one
  owner for the plan, current-state updates and Git integration. The other tool
  can review without silently overwriting that work. The existing studio
  planner, builder and reviewer contract remains the starting point.
- A small trial records what was actually verified, including handoff and Git
  conflicts, elapsed time and token usage where available. No token or speed
  improvement is claimed without a meaningful comparison.

## How it should feel

Like carrying a clearly marked working brief from one conversation to the next:
the person can see what is decided, what is missing and what to do next. Avoid
a process dashboard that makes an incomplete draft look approved or requires
the person to maintain the same facts in several places.

## Scope boundaries — explicitly NOT this

- Replacing Idea Clinic's decision about whether an idea deserves building with
  automatic implementation or a falsely approved specification.
- Replacing the studio's intent, plan, builder and independent-review process
  with a second competing source of truth.
- Treating a browser-generated prompt as a verified result, or claiming that an
  MCP client must follow instructions it may choose not to read.
- Automatically merging branches, resolving note conflicts, deleting notes or
  cleaning existing worktrees.
- Claiming the current LearnPy demo runs general Python or already creates
  agents; its existing demo plan describes a limited simulation.

## Constraints that are already fixed

- Unli Rice's append-only event log, rebuilt note projection and propose-only
  structural changes remain in place (`PROJECT_NOTES.md`, locked decisions).
- Idea Clinic generates a prompt locally; its existing decision-first behavior
  and browser-local draft must remain truthful. The related WebMCP entry point
  also needs consideration when changing the Clinic's prompt.
- The existing studio guardrails define intent as the specification, require
  one planner per feature, and reserve cross-tool work for pre- and
  post-mortem reviews. They do not permit an automatic cross-provider builder
  dispatch without a founder decision to change that process.
- Preserve the website checkout's existing modified and untracked work; it
  includes in-progress LearnPy files.

## Open questions for discovery and planning

1. What should the future LearnPy agent-building lesson accept, and what can it
   do within the course's eventual runtime and safety boundaries? Address this
   after the earlier pieces, as the founder requested.
2. What explicit user action carries a reviewed draft between surfaces, and
   which copy is authoritative when the draft changes? The app, website and
   MCP have different storage and permission boundaries.
3. How should the experience distinguish a Clinic prompt requesting a draft
   from a specification actually produced by the person's AI?
4. How can Unli Rice store or retrieve the spec using existing note behavior
   without imposing a new structure on unrelated notes?
5. What bounded Orca trial will exercise the real planner/reviewer handoff
   without sharing uncommitted work or weakening permissions?
6. What baseline and usage data are available for comparing coordination time,
   cleanup and token consumption? Treat unavailable measurements as unknown.

## Feasibility notes from discovery

- `idea-clinic/app.js` builds a prompt and currently asks for an intent only
  when appropriate; `assets/webmcp.js` has a separate related prompt path.
- `Sources/UnliRiceCore/HouseRulesPreset.swift` already includes engineering
  guidance. Presets are drafts and do not automatically alter saved rules.
- `playground/learnpy/` is an in-progress website demo. Its current intent and
  plan concern learning Python, not an existing agent-building feature; the
  founder describes that feature as a future lesson to address last.
- Orca was not found installed in the local checks. Its documented agent
  permission defaults need inspection in the installed version before any
  trial; the settings and launch arguments have not been verified here.
- The Unli Rice MCP tools were not available in this session, so existing
  project to-dos and relevant wiki notes could not be checked.
