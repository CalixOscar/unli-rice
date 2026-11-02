# INTENT-013 — Agent workspace

**Status: draft; not founder-approved.** Planning and one discovery review are authorized; building is not.

**Intent read:** not run

## Problem and people
A solo studio owner uses several AI assistants and projects. Captures, project memory, agent conversations, branch state and requests for attention live in different places. The proposed workspace should help the owner see and continue the right conversation with the right context, without concealing Git or claiming that an agent finished when it is waiting for an answer.

## Proposed outcome
A folder-first project view, with Git details wherever available, and a simple recent-session overview for Claude, Codex and Antigravity where official provider interfaces permit it. Shared Unli Rice notes, guardrails and explicit user-selected context support the work. Jev and GitHub MCP are desired integration capabilities, not promised parity. Existing manual handoffs remain usable when an integration is unavailable.

A successful owner can identify the project, conversation, observed branch/worktree, current state and next decision; open or resume a supported session deliberately; and review its result. Unsupported, stale or unknown state is labeled rather than guessed. Editing runs initially serialize per project; independent reviews may continue.

## Boundaries and open choices
This is not approval to clone Orca, hide branches, run unattended agents, override provider safeguards, auto-approve, merge, publish, or build. Folder-only projects remain possible. Chat, task, run, and observed Git association are separate concepts. The default view, execution/distribution boundary, and degree of session control are not yet decided. Local models and Cursor are later possibilities. See the draft spec and plan; founder approval follows discovery review.
