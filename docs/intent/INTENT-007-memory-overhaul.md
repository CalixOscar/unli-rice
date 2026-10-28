# INTENT-007 — Overhaul: what Unli Rice is for, now that every AI remembers

**Date:** 2026-10-29
**Author:** founder, via Claude
**Status:** draft. The founder confirms or edits the keep / cut / build table, then a plan follows.
**Intent read:** not run
**Plan:** docs/PLAN-memory-overhaul.md _(not written yet)_

## The problem

The founder's words: "Based on the latest changes in the AI world with [Claude's] memory added and
especially agents, let's do an overhaul of Unli Rice and figure out what is needed and what is not."

Unli Rice was built as *the* memory layer: one store that Claude, Codex and ChatGPT read and
write over MCP. Since then, each of those tools has shipped memory of its own (sources below,
checked 2026-10-29, mostly unverified against vendor docs):

- **Claude chat and Cowork** share one memory as of August 2026. Chat memory is on all plans.
- **Claude Code** keeps per-project memory as plain Markdown files in
  `~/.claude/projects/<project>/memory/`. This Mac has 15 of them (verified: `ls`, 2026-10-29).
- **Claude Managed Agents** got memory stores in April 2026: plain files, exportable over the API.
  A "dreaming" preview reviews past sessions and merges duplicates.
- **Codex** has `AGENTS.md` plus generated memories in `~/.codex/memories/`. Reports say memory v2
  is on by default for new profiles and can import other agents' memories. This Mac has no
  `~/.codex/memories/` yet (verified: `ls`, 2026-10-29).
- **ChatGPT memory and Codex memory are separate stores**, even inside OpenAI.

The vendors converged on what Unli Rice already does: **memory as plain files.** But each vendor
keeps its own files, on one machine, invisible to the others. Nobody shows you all of them in one
place, keeps their history, or tells you when they disagree.

## What the evidence says about today's app

- **Agents rarely write to Unli Rice directly.** In the only event log this Mac can read
  (`~/Library/Application Support/Unli Rice/events.jsonl`, 724 events, 2026-07-19 → 07-20),
  697 events came from ingest, 22 from Claude, 1 from Antigravity and 2 from the janitor. Most
  were tags (466). The App Store copy's data is sandboxed and couldn't be read. **The founder
  should check the real counts in the app before the plan is written.**
- **The founder's own working memory lives in files, not in Unli Rice:** `memory.md`,
  `PROJECT_NOTES.md`, `CLAUDE.md`/`AGENTS.md` and the Unli Rice Vault. This session's `unlirice`
  MCP reported 0 notes.
- **The eight eval cases (`evals/`, unli-001 → 008) are all unconfirmed:** no recorded transcript
  shows an agent using the MCP tools well or badly. The overhaul shouldn't redesign the MCP
  surface until at least a few are recorded.

## What "solved" looks like

Unli Rice becomes **the one place that shows what every AI on this Mac remembers, keeps its
history, and flags when they drift apart.** It stops trying to be the place they write to.

- Context: one screen lists each tool's memory files (Claude Code, Codex, `AGENTS.md`/`CLAUDE.md`,
  project `memory.md`), read from folders the user already granted. Read-only, like Repos.
- History: every change to those files lands in the append-only log as a snapshot. This is
  the security camera: you can see what an AI "learned" and when.
- Guardrails: House Rules stay. The text is written for the files every tool already reads
  (`AGENTS.md`, `CLAUDE.md`), still copied rather than written by the app.
- Drift: when two tools' memories contradict each other, or a memory contradicts a House Rule,
  it shows up in Needs you. Flag only, never fixed automatically (the janitor's existing rule).
- Projects and Security stay as built in four-jobs.

## Keep / cut / build (draft, for the founder to confirm)

| Today | Proposal | Why |
|---|---|---|
| Event log, archive-not-delete, `note_history`, `transaction_log` | **Keep** | The audit trail is the one thing vendor memory lacks |
| MCP server (14 tools) | **Keep, freeze** | Still the cross-tool bridge. Trim only after eval transcripts show which tools agents use |
| House Rules | **Keep**, aim the output at `AGENTS.md` / `CLAUDE.md` | Every tool reads those natively now |
| Projects (Garden + Repos + branch graph), To do | **Keep** | No vendor memory does this |
| Trust Center, snapshots, archived notes | **Keep** | Security job |
| Folder mirror (plain-file export) | **Keep** | Matches where the vendors went |
| Sync shards (multi-device) | **Keep** | Vendor memories are per machine |
| **Map (note graph)** | **Founder's call:** delete, or keep behind a switch (see open question 1) | Founder wants it gone from view |
| Your year so far (retrospective) | Same switch as the Map, or delete | Hidden since four-jobs |
| Profiles / Profile Builder / multi-vault | **Delete the code** | Hidden since four-jobs; nothing has missed it |
| PDF and ZIP export | **Delete the code** | Hidden since four-jobs |
| Bulk ingest of local files (`LocalFileImporter`) | **Narrow** to memory files and session history | 697 of 724 logged events were ingest noise |
| Janitor similarity / embedding connection (`RemoteSimilarity`) | **Stop investing**; keep flag-only rules | Vendor "dreaming" consolidates inside each tool |
| BYO LLM (`feature/byo-llm`, `docs/BYO_LLM.md`) | **Close** | Contradicts "the reasoning comes from the agent you connect" |
| iOS Capture | **Keep as is**, no new work | Free/MIT since 2026-08-09 |
| **New:** read Claude Code / Codex / `AGENTS.md` memory files into one view | **Build** | The core of the new pitch |
| **New:** snapshot those files into the log on change | **Build** | History no vendor keeps |
| **New:** drift flags (tool vs tool, memory vs House Rule) | **Build, after the two above** | Uses the existing flag-for-review path |

Repo housekeeping, not app scope: archive the five `docs/ANTIGRAVITY_*.md` (Antigravity left
the pipeline on 2026-10-16), decide the ~10 open branches, prune the four stale worktrees under
`.claude/worktrees/`.

## Open questions

1. **Map: delete or switch?** The founder first said "let go of the map", then "or can we make it
   toggleable". Options:
   - **A. One "Show extras" switch** in Setup, off by default, that brings back the Map and Your
     year so far together. Cheap: both screens still exist, so the switch only adds
     two rows to the sidebar. Costs: two views (`MapPaneView.swift`, `NoteGraphView.swift`) keep
     compiling and need a glance at each UI change. *(Claude's recommendation: one switch, not one
     per feature, so Setup doesn't grow a row each time something is retired.)*
   - **B. Delete** both files and the `.map` pane case. `BranchGraphView` (Projects) and
     `LinkIndex` (backlinks) are separate and stay either way.
2. **Positioning:** does the App Store listing change from "a memory layer for your AIs" to "see
   what every AI remembers about you"? That changes screenshots and the public roadmap page
   (calmdownoscar.com/unlirice).
3. **Reading `~/.claude` and `~/.codex` from the sandbox** needs the user to grant those folders
   once, like scan roots. Acceptable onboarding cost?
4. **Writing:** should Unli Rice ever *write* into a tool's memory (e.g. Codex's import of
   external memories), or stay read-only and copy-only, as today?
5. `feature/todo-widget` (the 1.3 release, 25 commits) is still not in `main`. Merge it before
   any overhaul branch starts?

## Scope boundaries: explicitly NOT this

- No change to the event log format, note format or sync shards (locked architecture in
  `PROJECT_NOTES.md`). New snapshots are new events of an existing kind, or a new kind the
  plan must justify.
- No automatic edits to another tool's files. Copy, never write, unless open question 4 says
  otherwise.
- No cloud service, no account, no bundled model.

## Sources

- [Claude Cowork remembers chat (TechCrunch, 2026-08-25)](https://techcrunch.com/2026/08/25/claude-cowork-finally-remembers-what-you-told-the-app-in-chat/)
- [Memory for Claude Managed Agents (Anthropic)](https://claude.com/blog/claude-managed-agents-memory)
- [Claude Platform release notes](https://platform.claude.com/docs/en/release-notes/overview)
- [ChatGPT & Codex changelog](https://learn.chatgpt.com/docs/changelog)
- [Codex memory: AGENTS.md and memories (third party)](https://aiagentmemory.org/articles/codex-memory/)
- [mcp-memory-service: shared memory across tools](https://wavect.io/blog/mcp-memory-service-claude-code-cursor/)
