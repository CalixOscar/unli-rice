# INTENT-010 — Capture belongs in the Studio

**Date:** 2026-11-01
**Author:** codex, from the founder's requests in this session
**Status:** approved 2026-11-01 — founder: “Proceed skip pre mortem and implement”
**Spec:** docs/SPEC-capture-studio.md
**Plan:** docs/PLAN-capture-studio.md

## The founder's words

“I have an idea while walking my dog, I tell it to unli rice capture. I forget
about the idea I come back and start working on something else but any llm will
remind me that I have created a voice capture of an idea.”

“It is mainly Codex and CLaude that needs to see the note through unli rice.
Imaging I start working on my wedding app and there is a capture regarding that
app either llm can remind me of. Even better if I could ask for a status opdate
of my repos and unli rice captures are included.”

“An option would then be to act on the note or add to a todo list. I also want
the same repo overview if possible in the ios app availble on the mac app today.”

“Lets get to it and update the app design to match the mac app”

“Does the mac app also show the difference between local git and github gits?
if yes then have the ios app do the same.”

## The problem

Capture can save a transcript and exchange event files with the Mac, but a
searchable note is not a reminder. The Mac Studio now groups projects, branches
and notes into decks; Capture still presents its older recorder and lists.
The phone's existing repository snapshot lacks the richer project status the
Mac assembles from project folders. Codex and Claude receive no automatic
summary of pending project captures from the current MCP initialization text.

## What solved looks like

1. Record or type an idea with minimal interruption. Assign a project explicitly,
   or leave it unassigned. The transcript remains available after the audio expires.
2. When Codex or Claude connects through Unli Rice, it receives a concise pointer
   to pending captures. It checks the current project's captures and mentions
   relevant ideas without starting implementation until the founder chooses.
   A running session can request fresh context; this is not a push-notification promise.
3. A repo status request includes project status, next step, to-dos, pending
   captures and repository evidence. Unassigned captures remain discoverable.
4. A capture can be discussed/acted on with an AI, added to a project's to-dos,
   or explicitly set aside. Reading or copying it does not mark it handled.
   Both assistants and both apps use the same append-only note state.
5. iOS presents a compact Studio in the Mac's visual family: album-style project
   sleeves, solid decks, shared colors, system type and restrained glass controls.
   Recording stays one tap away; an active recording remains visible during navigation.
6. Each project's phone overview shows its last published status and next step,
   repository comparison, pending captures and to-dos. It clearly shows when the
   Mac observed the information and when it was published.
7. Local versus remote comparison has the Mac's exact meaning: local branch tips
   compared with recorded remote refs. GitHub is not checked live. Missing remote
   evidence is unknown, not “all pushed.”

## How it should feel

Say it, put the phone away, and trust that the idea will meet you when you work
on the project. The phone feels like the Mac Studio adapted to touch, with large
project artwork and detail on demand. Avoid a dense git dashboard, an AI chat
screen bolted onto the recorder, or decorative controls that slow capture down.

## Constraints and boundaries

- Preserve the append-only event log, permanent titles, existing sync transport
  and propose-only structural review. No new EventKind is necessary for capture state.
- The Mac publishes the project picture; iOS does not scan or change repositories.
- Project association starts with explicit assignment. Do not silently guess a
  wedding-app reference, rename project tags, or attach ambiguous names.
- “Act with AI” on iOS prepares a share/copy handoff. It does not run a remote
  coding agent. Inside Codex/Claude, acting requires the founder's instruction.
- No hosted service, cloud inference dependency, GitHub authentication, live fetch,
  repository write, version bump, upload or App Store submission in this work.
- Retain typed capture, Action Button, audio playback/retention, app lock, iPad,
  accessibility, settings and private-device mode.
- This is an existing-app feature; no new-app Idea Clinic or demand test is required.

## Approval boundary

Founder approved this scope on 2026-11-01: “Proceed skip pre mortem and implement”.
The pre-mortem is waived for this feature only. Verification and post-mortem remain required.
