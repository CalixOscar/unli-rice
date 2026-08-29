# Plan — Note Contract validation

**Status:** plan, not built. Written by Claude Code 2026-08-29 for the swarm to implement.
**Why now:** the author's own vault hit every failure this prevents; users get no equivalent.

## The problem, stated precisely

Unli Rice's MCP write path accepts any shape. `create_note` and `append_to_note` in
`Sources/unlirice-mcp/ToolCatalog.swift` declare only `title`/`body`/`id` — there is no
structural validation anywhere in `ToolDispatcher.swift`. An agent can write a note that
contradicts itself in adjacent lines and nothing notices.

The author worked around this *outside* the app, with `scripts/lint-project-notes.sh`
wired to a git pre-commit hook in each repo. That works because it binds every tool
equally, including ones that never read any guardrail. But it only protects markdown
files inside a git repo that someone remembered to install a hook into. It does nothing
for the note store itself, and nothing at all for any other user.

Four failures this produced in practice, all verified on 2026-08-29:

1. **A missing heading swallowed the log.** UnliDisk's `## Decisions Log` heading was
   never written, so 120 dated entries nested inside `## Handoff`, which spanned lines
   20–1766 of a 199k-char note. Every tool that opened it read 1,700 lines of history as
   "current unfinished work".
2. **Adjacent fields contradicted each other.** One Handoff track carried two `Left by:`
   fields (different tools, no dates). Another was missing `Files touched:` entirely.
   A note that contradicts itself reads as current, which is worse than a stale one.
3. **Unbounded growth.** Notes reached 199k, 119k and 104k characters. Nothing warns.
4. **Silent duplication.** 29 unresolved duplicate flags, nearly all from one cause: the
   same file ingested from two paths, producing doubled-hash titles.

## Design

Add a **Note Contract**: an optional, per-note declared structure that the store itself
enforces on write. Three principles, each chosen against a failure above:

- **Warn in the tool result, flag for review, block only on meaning-destroying shapes.**
  A hard block on every violation risks discarding an agent's work mid-turn. But a pure
  flag is too weak — the git hook worked *because* it blocked. So: return the violation
  in the `create_note`/`append_to_note` result so the writing agent sees it immediately
  and can fix it in the same turn, and raise a review flag. Hard-reject only shapes that
  silently change what the note means: a dated entry landing inside a current-state
  section, and a repeated field within one block.
- **Reuse the janitor's existing review machinery.** `JanitorProposal`, `flag_for_review`
  and `pending_reviews` already implement "surface it, never auto-resolve". Contract
  violations become another proposal source, not a parallel system.
- **The contract travels with the note.** Like the `<!-- NOTE CONTRACT -->` block the
  author puts at the top of each `PROJECT_NOTES.md` — a tool that never reads the app's
  settings still reads the file it is about to edit.

## Work

1. **`Sources/UnliRiceCore/NoteContract.swift`** (new) — parse a contract declaration:
   required sections in order, append-only sections, and a fielded block spec (ordered
   field names, no repeats). Port the rules from `Scripts/lint-project-notes.sh`, which is
   the validated reference implementation — including its two hard-won exemptions:
   content rules apply to *added* lines only (the logs are append-only history), and a
   deliberate deferral is waivable in-file rather than bypassed.
2. **`Sources/UnliRiceCore/NoteContractValidator.swift`** (new) — pure function,
   `(contract, oldBody, newBody) -> [Violation]`, each with severity `.reject`/`.warn`.
   Diff-aware so append-only rules can distinguish added from existing lines.
3. **Wire into `ToolDispatcher.swift`** on `create_note` and `append_to_note`. On
   `.reject`, return an error naming the cause *and the fix* — the linter's own lesson was
   that "a field was split around inserted content" was true but useless, while "the
   '## Decisions Log' heading is probably missing" is actionable. On `.warn`, write, then
   append the violations to the tool result and raise a review flag.
4. **Size pressure** — carry `NOTES_SIZE_WARN` (default 40,000 chars) into the warn path
   and surface it in the app's note list, not only on write. There is no compaction tool
   any more; the warning is the only guard.
5. **Ship the contract as a template** — extend `ProfileTemplate.swift` so the Profile
   Builder can emit a project-notes contract alongside the profile documents it already
   generates, and add an "Install notes guard" action that writes
   `scripts/lint-project-notes.sh` plus the pre-commit hook into a chosen project folder.
   This is the part that generalizes the author's private fix to every user.
6. **Dedup on ingest** — the 29 duplicate flags share one cause, not 29. Key ingested
   documents by content hash and source path so the same file reached by two paths
   resolves to one note. Fix the ingest path; the duplicates stop being generated.

## Gotchas

- The hook resolves `scripts/` **or** `Scripts/`. macOS is case-insensitive, so a
  hardcoded lowercase path appears to work locally while resolving to nothing on a
  case-sensitive checkout. Unli Rice and UnliDisk both use capital-S.
- A Handoff may legitimately hold several named tracks (`### Handoff A — …`) for one
  codebase shipping two products. Validate each track independently; do not treat
  multi-track as malformed.
- Do not retrofit rules onto existing note bodies. Demanding evidence or structure
  retroactively forces exactly the rewriting of history the guardrails forbid.
- Unli Rice's own `PROJECT_NOTES.md` currently satisfies none of the four required
  sections — it is an architecture document that happens to share the filename. Decide
  whether to restructure it or exempt it *before* dogfooding this, not during.

## Verification

`swift test`, plus a fixture suite that replays the four real failures above and asserts
each is caught with the intended severity. Verify against `git diff` — a passing run is
not evidence on its own.
