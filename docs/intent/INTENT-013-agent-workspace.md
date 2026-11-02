# INTENT-013 — Agent workspace

**Status: draft; not founder-approved.** Planning and one discovery review are authorized; building is not.

**Intent read:** not run

## Problem and people
A solo studio owner uses several AI assistants and projects. Captures, project memory, agent conversations, branch state and requests for attention live in different places. The proposed workspace should help the owner see and continue the right conversation with the right context, without concealing Git or claiming that an agent finished when it is waiting for an answer.

## Proposed outcome
A new open-source desktop app for macOS and Windows, distributed outside the Mac App Store through GitHub. It has a folder-first project view, with Git details wherever available, and a simple recent-session overview for Claude, Codex and Antigravity where official provider interfaces permit it. The founder wants useful Unli Rice features or optional automatic connectors; whether project memory is built in or connected is still being decided. Jev and GitHub MCP are desired integration capabilities, not promised parity. Existing manual handoffs remain usable when an integration is unavailable.

A successful owner can identify the project, conversation, observed branch/worktree, current state and next decision; open or resume a supported session deliberately; and review its result. Unsupported, stale or unknown state is labeled rather than guessed. Editing runs initially serialize per project; independent reviews may continue.

## Founder addition — project session folders and favorites
Gather the related sessions for an Unli Rice project into one project folder in the interface, across supported assistants and branches. The founder can star that project folder as a favorite for quick access. Treat this as logical organization, not moving provider transcript files or creating another checkout. Branch/worktree evidence remains visible on each session. This addition is a requested product outcome, not approval of the full architecture or permission to build.

## Boundaries and open choices
This is not approval to clone Orca, hide branches, run unattended agents, override provider safeguards, auto-approve, merge, publish, or build. Folder-only projects remain possible. Chat, task, run, and observed Git association are separate concepts. The default view, cross-platform runtime, memory boundary and degree of session control are not yet decided. The separate app, macOS/Windows targets, open-source direction and outside-Store distribution are founder choices; this does not authorize implementation. Local models and Cursor are later possibilities. See the draft spec and plan; founder approval follows discovery review.

## Founder direction — 2026-11-03
The earlier conditional GitHub fallback is superseded: plan a **new open-source app for macOS and Windows**, released outside the Mac App Store, with GitHub as the initial distribution channel. GitHub does not restrict repository hosts. Name, new repository location, license, supported OS/provider matrix and update trust remain unsettled. These documents remain in the existing repo as a planning record; no new project, target or migration is created yet.

The founder then asked whether Unli Rice features should instead be included in the new app. **Recommendation, not yet accepted:** include minimal local project notes, guardrails and handoffs so the standalone app works without Unli Rice, plus an optional consented Unli Rice connector for existing memory and captured ideas. Do not clone voice capture, iCloud transport, ingestion and review systems into v1. Each source retains explicit authority; no silent imports, duplicate writable note copies or credential sharing. Current Unli Rice apps and data remain intact. This is not full intent/spec approval or permission to build.
