# INTENT-007 — Overhaul: guardrails, grounding and evals

**Date:** 2026-10-29
**Author:** founder, via Claude
**Status:** approved 2026-10-29 — founder confirmed the tables and the drafted defaults for open questions 2–7
**Intent read:** not run
**Plan:** docs/PLAN-memory-overhaul.md (stage 2 draft, 2026-10-29)

## The problem

The founder's words: "Based on the latest changes in the AI world with [Claude's] memory added and
especially agents, let's do an overhaul of Unli Rice and figure out what is needed and what is not."
Then: "Make more switches for the nice to have but not needed. Let's stick to the core of having
guardrails, grounding and evals sort of in the app."

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

Remembering is solved inside each tool. What isn't solved: knowing what each one remembers,
whether it follows your rules, and whether it got better or worse. Those are the three jobs.

## What the evidence says about today's app

- **Agents rarely write to Unli Rice directly.** In the only event log this Mac can read
  (`~/Library/Application Support/Unli Rice/events.jsonl`, 724 events, 2026-07-19 → 07-20),
  697 events came from ingest, 22 from Claude, 1 from Antigravity and 2 from the janitor. Most
  were tags (466). The App Store copy's data is sandboxed and couldn't be read. **The founder
  should check the real counts in the app before the plan is written.**
- **The founder's own working memory lives in files, not in Unli Rice:** `memory.md`,
  `PROJECT_NOTES.md`, `CLAUDE.md`/`AGENTS.md` and the Unli Rice Vault.
- **Evals already exist as dev tooling** in `evals/`: a Python harness (`run.py`), 9 cases,
  deterministic assertions plus an optional judge model on localhost, and a voice rubric. None
  of it ships in the app. Cases 001–008 have no recorded transcript yet.
- **The app already reads Claude Code session transcripts** (`ClaudeSessionImporter`). The raw
  material for in-app evals is on disk.

## What "solved" looks like

The sidebar names three jobs, plus Setup. Everything else is an extra with its own switch.

### Grounding: what your AI knows

- Your notes, as today.
- **New:** one read-only view of each tool's own memory files (Claude Code, Codex,
  `AGENTS.md`/`CLAUDE.md`, project `memory.md`), from folders the user grants once.
- **New:** every change to those files is snapshotted into the append-only log, so you can see
  what an AI "learned" and when.
- The folder mirror and the MCP server stay: they are how a tool reads the grounding.

### Guardrails: what your AI must and must not do

- House Rules, with the text aimed at the files every tool already reads (`AGENTS.md`,
  `CLAUDE.md`). Still copied, never written by the app.
- Needs you: reviews and notices, plus **new** drift flags (two tools' memories disagree, or a
  memory contradicts a House Rule). Flag only, never fixed automatically.
- The safety net: Trust Center, recovery points, archived notes. "Nothing an AI does here can
  destroy anything" is itself a guardrail, so the Security job folds into this one.

### Evals: did your AI actually follow the rules and use what it knows?

- **New:** the app runs checks over session transcripts already on disk. Each House Rule can
  carry a check, e.g. "ran the tests before committing", "read the rules before editing",
  "didn't touch files outside the task", "wrote no secrets". Results are pass / fail / unknown
  per session, with the transcript line that decided it.
- Deterministic checks run in the app. Judged checks (voice, judgement calls) run only against
  a model on localhost, the same restriction as today's embedding connection, or are handed to
  the user as a copyable prompt. No bundled model, no cloud.
- A trend: is each tool following the rules more or less often than last month?
- The `evals/` cases are the seed set. The dev harness stays as dev tooling.

## Jobs table (draft, for the founder to confirm)

| Today | Proposal | Job |
|---|---|---|
| Home ("What your AI knows"), Notes | Keep | Grounding |
| Folder mirror (plain-file export) | Keep | Grounding |
| MCP server (14 tools) | Keep, freeze; trim only after eval transcripts show which tools agents use | Grounding |
| Event log, archive-not-delete, `note_history`, `transaction_log` | Keep | Grounding (history) |
| Sync shards (multi-device) | Keep | Grounding |
| **New:** each tool's memory files in one view, snapshotted on change | Build | Grounding |
| House Rules | Keep, aim output at `AGENTS.md` / `CLAUDE.md` | Guardrails |
| Needs you + notices | Keep | Guardrails |
| Trust Center, recovery points, archived notes | Keep, move under Guardrails | Guardrails |
| **New:** drift flags | Build, after the memory view | Guardrails |
| **New:** checks over session transcripts, per House Rule | Build | Evals |
| **New:** trend per tool | Build, after the checks | Evals |
| Setup (AI Tools, Folders, background switch) | Keep | Setup |

## Extras: each gets its own switch (decided 2026-10-29)

Setup gets an **Extras** tab. Each row is one switch, off by default for new installs. Turning
one on brings its screen (or behaviour) back; nothing is deleted. This replaces the earlier
"one Show extras switch" decision from the same day.

| Extra | Default | Note |
|---|---|---|
| Projects (Garden + Repos + branch graph) | Off for new installs; **on** for existing installs that have used it (open question 6) | Was a core job in four-jobs, 10 days ago |
| To do | Same as Projects | Derived mostly from repos and `memory.md` |
| Map (note graph) | Off | Founder: "let go of the map" |
| Your year so far | Off | Hidden since four-jobs |
| Separate memories (profiles, Profile Builder) | Off | Hidden since four-jobs |
| PDF and ZIP export | Off | Hidden since four-jobs; the folder mirror stays core |
| Bulk import of local files (`LocalFileImporter`) | Off | 697 of 724 logged events were ingest; session history and memory files stay on |
| Duplicate-note detection (janitor similarity, embedding connection) | Off | Vendor "dreaming" consolidates inside each tool |
| iPhone Capture promo | Off | Capture itself is unchanged |

A switch that controls something running in the background says so on its row (four-jobs rule:
nothing that runs by itself is hidden).

**Delete outright:** only `feature/byo-llm` and `docs/BYO_LLM.md` (never shipped; contradicts
"the reasoning comes from the agent you connect").

Repo housekeeping, not app scope: archive the five `docs/ANTIGRAVITY_*.md` (Antigravity left
the pipeline on 2026-10-16), decide the ~10 open branches, prune the four stale worktrees under
`.claude/worktrees/`.

## Open questions

1. ~~**Map: delete or switch?**~~ **Decided 2026-10-29:** a switch, now one of several in Extras.
2. **Positioning:** does the App Store listing become "guardrails, grounding and evals for your AI
   tools"? That changes screenshots and the public roadmap page (calmdownoscar.com/unlirice).
3. **Reading `~/.claude` and `~/.codex` from the sandbox** needs the user to grant those folders
   once, like scan roots. Acceptable onboarding cost?
4. **Writing:** should Unli Rice ever *write* into a tool's memory (e.g. Codex's import of
   external memories), or stay read-only and copy-only, as today?
5. `feature/todo-widget` (the 1.3 release, 25 commits) is still not in `main`. Merge it before
   any overhaul branch starts? It adds a To do widget, and To do is now an extra.
6. **Projects and To do for existing users:** keep them on for anyone who has used them, so the
   update doesn't take away a screen someone relies on?
7. **Which transcripts do evals read?** Claude Code's are on disk and already parsed. Codex keeps
   session logs too (unverified). ChatGPT and Claude chat don't leave transcripts on the Mac, so
   evals would cover coding agents only at first. Acceptable?

## Scope boundaries: explicitly NOT this

- No change to the event log format, note format or sync shards (locked architecture in
  `PROJECT_NOTES.md`). Snapshots and eval results are new events of an existing kind, or a new
  kind the plan must justify.
- No automatic edits to another tool's files. Copy, never write, unless open question 4 says
  otherwise.
- No cloud service, no account, no bundled model. Judged evals use localhost only.
- No deleting code for anything in Extras. Deleting is a later, separate decision.

## Sources

- [Claude Cowork remembers chat (TechCrunch, 2026-08-25)](https://techcrunch.com/2026/08/25/claude-cowork-finally-remembers-what-you-told-the-app-in-chat/)
- [Memory for Claude Managed Agents (Anthropic)](https://claude.com/blog/claude-managed-agents-memory)
- [Claude Platform release notes](https://platform.claude.com/docs/en/release-notes/overview)
- [ChatGPT & Codex changelog](https://learn.chatgpt.com/docs/changelog)
- [Codex memory: AGENTS.md and memories (third party)](https://aiagentmemory.org/articles/codex-memory/)
- [mcp-memory-service: shared memory across tools](https://wavect.io/blog/mcp-memory-service-claude-code-cursor/)
