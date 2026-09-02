# Claude Code instructions for this repo

Read in this order. It is deliberate: the list runs from the content that changes
least often to the content that changes most, because prompt caching matches on an
exact prefix — anything that changes invalidates everything after it. `memory.md`
changes several times a session and therefore comes last.

1. `~/Documents/Unli Rice Vault/_AI Context/04_Guardrails.md` — the studio guardrails.
   Authoritative for tool roles and the five-stage pipeline, scope discipline, note
   hygiene, the backend security floor, and the vault/repo boundary. Stable for weeks.
   Where it and anything in this repo disagree, the vault wins.
2. `AGENTS.md` — rules for using the `unlirice` MCP server. Written to apply to any
   agent (Claude Code, Codex, Antigravity), which is why the conventions live there
   rather than being duplicated per tool.
3. `PROJECT_NOTES.md` — the architecture and its locked-in decisions. This is the
   **historical record**: what was decided, when, and why. Large and append-only.
4. `memory.md` — **current working state.** Status, task in flight, files touched,
   next step, gotchas. Capped at 32,000 characters and enforced in pre-commit. Read
   this one in full; it is the file that tells you where things actually stand.

**Never put a timestamp, token count, or session id in this file or in `AGENTS.md`.**
One volatile line at the top of a stable file re-bills everything below it on every
turn.

## Before you commit

`.git/hooks/pre-commit` runs three checks — a secret scan on every commit, plus
structure checks on `memory.md` and `PROJECT_NOTES.md` when they are staged. The
scripts in `Scripts/` are **copies**; the canonical versions live in
`~/Documents/Unli Rice Vault/scripts/`. Fix a rule there and re-run
`install-studio-hooks.sh`, never by editing the copy in this repo.

## What Claude does here

Claude plans; it does not build. A long mechanical pass belongs to the Antigravity
swarm — write the plan into `docs/` instead, as a `PLAN-<slug>.md` traceable to an
intent doc in `docs/intent/`. See the pipeline in the guardrails.
