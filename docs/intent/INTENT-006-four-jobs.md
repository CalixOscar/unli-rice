# INTENT-006 — Four jobs: context, guardrails, security, projects

**Date:** 2026-10-19
**Author:** founder, via Claude
**Status:** approved 2026-10-19 — founder confirmed the keep/cut list as drafted
**Intent read:** not run
**Plan:** docs/PLAN-four-jobs.md _(not written yet)_

## The problem

The founder's words: "the features on unli rice are too many now. We need to simplify the
app to focus on context, guardrails, security and keeping track of things like gits."

This happened once before. The August "one-button app" pass (`docs/ANTIGRAVITY_SIMPLIFY.md`)
cut the sidebar to a few rows. Since then it has grown back to nine: Home, Garden, Notes,
To do, Repos, Needs you, Your year so far, Map, More. "More" opens nine more pages, and
Setup has five tabs of its own. Two of the sidebar rows, Garden and Repos, now do much the
same job.

## Who hits it, and when

A developer installs Unli Rice so that Claude, Codex and ChatGPT share one memory and follow
the same rules. They open the app to check three things: what their AI knows, whether
the rules are in place, and where each project stands. Instead they get a year-in-review,
a node graph, a profile builder and a "why not a text file?" essay, all at the same level
as the things they came for.

## What "solved" looks like

- The sidebar names four jobs, plus Setup. Everything on screen belongs to one of them:
  - **Context:** what your AI knows (Home), your notes, and the folder your AI can read.
  - **Guardrails:** "What your AI should always do" (House Rules), To do, and Needs you
    (reviews and notices together).
  - **Security:** the Trust Center (checks, recovery points, trash), privacy, and where
    your data lives.
  - **Projects:** one place for git and project status. Garden and Repos become one page.
- A first-time user can say what the app is for after looking at the sidebar alone.
- Nothing that runs by itself is hidden. If a feature keeps working in the background,
  its switch stays visible.
- Existing notes, profiles and settings are untouched. A hidden feature's data is still
  there and still readable by the AI tools.

## How it should feel

A quiet control room with four labelled doors. You check what you came for and close the
app. Calm, concise and discreet, as the studio voice asks.

Avoid the generic version: a settings-style list of every capability, or a dashboard of
counts that asks for attention. If a screen doesn't help one of the four jobs, it doesn't
get a door.

## Keep / cut (founder confirmed 2026-10-19)

| Today | Proposal | Job |
|---|---|---|
| Home ("What your AI knows about you", recent writes) | Keep | Context |
| Notes | Keep | Context |
| The folder your AI can read (mirror export) | Keep, move under Context | Context |
| Setup → AI Tools (connect Claude/Codex/ChatGPT) | Keep as Setup | Setup |
| What your AI should always do (House Rules) | Keep, promote to the sidebar | Guardrails |
| To do | Keep | Guardrails |
| Needs you + Notifications | Keep, merge into one | Guardrails |
| Trust Center | Keep, promote to the sidebar | Security |
| Archived notes | Keep, inside Security (it's the recovery path) | Security |
| Garden + Repos (+ branch graph) | Merge into one Projects page | Projects |
| Your year so far | Hide | — |
| Map (note graph) | Hide | — |
| Separate memories (profiles, profile builder) | Hide (see open question 3) | — |
| Why not just a text file? | Hide | — |
| What runs on its own / Advanced Mode | One visible on/off switch in Setup | Setup |
| Capture promo card in the sidebar | Hide | — |
| Extra exports (PDF, ZIP) | Hide from menus; keep the folder mirror | — |

"Hide" means removed from navigation. The code and data stay and come back with one line.
Deleting the code is a later, separate decision, made once nobody misses it.

## Scope boundaries — explicitly NOT this

- No change to the event log, note format, sync shards or any stored file (locked
  architecture in `PROJECT_NOTES.md`).
- No change to the MCP tools AI agents use (14 tools today). Agents keep every
  capability; this is about what the founder sees.
- No new features. The Projects merge reuses Garden and Repos; it adds nothing new.
- No App Store upload, version bump, screenshots or metadata. New screenshots will be
  needed before the next submission, but that is a separate piece of work.
- The iPhone Capture app is out of scope this round (founder, 2026-10-19).

## Constraints that are already fixed

- The app ships on the Mac App Store, so this branch is a submission candidate. The
  pre-launch gate applies before release, and screenshots must match the build.
- Sandboxed: git is read from files, never by running git. Fixes are copied text, not
  actions.
- No destructive delete. Hiding a feature must never strand data the user can't reach;
  archived notes stay reachable.
- The Garden integration (`codex/project-garden`, Codex's plan) is uncommitted and mid
  review. This work starts after it lands, or the two will collide in `ContentView.swift`
  and `HomeView.swift`.

## Open questions for stage 2

Settled by the founder on 2026-10-19: hide now and delete later; the Mac app only;
background work becomes one visible switch in Setup.

1. **Separate memories:** if a user already has more than one profile, hiding the switcher
   strands them on one. Keep a minimal switcher in Setup when there's more than one
   profile, or hide it completely?
2. Should the four job names appear as sidebar section headings, or only as the page
   names?

## Feasibility notes from discovery

- The navigation lives mainly in `ContentView.swift` (the sidebar), `MoreView.swift` and
  `SetupView.swift`. Most of the cut is a navigation change, not a code removal.
- Garden (new) and Repos (older, with a branch graph) both read the same folder grants.
  Merging them is the largest single piece of work.
- The "which page is showing" state is 18 separate `showing…` flags in `AppStore`. A
  plan should look at replacing them with one "current page" value. That's also the
  suspected cause of the sidebar lag in `memory.md`'s open hypotheses.
