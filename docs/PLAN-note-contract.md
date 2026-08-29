# Plan — Note Contract validation

**Stage:** 2 (plan/architecture). Settled enough for a Codex pre-mortem, then the swarm.
**Not built.** Written by Claude Code 2026-08-29.
**Verified against:** `NoteService.swift`, `unlirice-mcp/ToolDispatcher.swift`,
`ToolCatalog.swift`, `HouseRulesPreset.swift`, `CorpusHealth.swift`,
`Ingest/LocalFileImporter.swift`, and the locked-in decisions in `PROJECT_NOTES.md`.

---

## 1. Problem

`create_note` and `append_to_note` accept any shape. `ToolDispatcher.dispatch` maps them
straight onto `NoteService.createNote` / `appendToNote`, which append an `Event` and
return a projection. Nothing between the agent and the log looks at structure. An agent
can write a note that contradicts itself in adjacent lines and nothing notices.

The author's workaround lives *outside* the app: `scripts/lint-project-notes.sh` on a git
pre-commit hook. It works because it binds every tool equally, including ones that never
read a guardrail. But it only guards markdown inside a git repo someone remembered to wire
up. The note store has no equivalent, and other users get nothing.

Four failures this produced, all verified 2026-08-29 in the author's own projects:

| # | Failure | Scale |
|---|---|---|
| 1 | `## Decisions Log` heading never written, so dated entries nested inside `## Handoff` | 120 entries; Handoff spanned lines 20–1766 of a 199k note |
| 2 | Contradictory adjacent fields — two `Left by:` in one block; another block missing `Files touched:` | UnliDisk, both tracks |
| 3 | Unbounded growth, nothing warns | 199k / 119k / 104k char notes |
| 4 | Same file ingested from two paths → duplicate notes | 29 unresolved duplicate flags |

Failure 4 is a different bug with a different fix. It is **out of scope** here and is
written up separately in §8 so it does not get lost.

---

## 2. Constraints this must not violate

From `PROJECT_NOTES.md` "Locked-in architecture decisions":

1. **Append-only event log is the source of truth; `Note` is a rebuilt projection.**
   So validation cannot inspect "the note" as a stored document — it must validate the
   *projected body that would result* from the candidate event.
2. **No destructive delete anywhere.** Nothing here deletes or rewrites. Not affected.
3. **Structural changes are proposed, never applied by an agent.** So the validator
   **never auto-fixes** — it does not insert the missing heading, reorder fields, or
   rewrite anything. It reports, and it flags.
4. **Every write records its `source`.** Flags raised by validation need their own
   attributable source (§4, D6).

`AGENTS.md` adds: *"there is no tool that lets you apply a structural change, and none
should ever be added that does."* Declining to append is not applying a change, so a
hard reject is compatible — but see D2, which is where the real care is needed.

---

## 3. What a contract is

A **Note Contract** is a named, versioned description of a note's expected structure:

- required `##` sections, in order
- which sections are append-only
- an optional **fielded block** spec: ordered field names, no repeats, all-or-none
- optional soft size ceiling

Contracts are **built-in and referenced by id**, declared in the note body:

```
<!-- unlirice:contract project-notes-v1 -->
```

Rationale: no schema change, no migration, no new `Event` kind, and the contract travels
with the note — a tool that never opens the app's settings still reads the body it is
about to edit. That is the same reasoning behind the author's `<!-- NOTE CONTRACT -->`
block, and it is why this is a marker rather than app-side configuration.

A note with no marker has no contract and is validated as today (i.e. not at all).
**Adoption is opt-in.** This is deliberate: retrofitting structure onto 389 existing
notes would generate flags nobody asked for and train the flag away.

`project-notes-v1` ports the rules already proven in `scripts/lint-project-notes.sh`:
four required sections, six ordered Handoff fields, multi-track handoffs validated
independently, dated `Left by`, dated-heading-inside-Handoff detection, 40k soft ceiling.

---

## 4. Design decisions

**D1 — Validate the projected body, not the argument.**
`appendToNote(text:)` receives a fragment with no structure of its own. The validator
takes `(contractId, bodyBefore, bodyAfter)` where `bodyAfter` is the projection that
*would* result. `NoteService` already rebuilds via `require(noteId)`; the plan computes
the candidate body without appending, validates, and only then appends.

**D2 — Block only what the write introduces. Pre-existing violations warn.**
This is the load-bearing decision. If a hard reject fired on any violation, a note that
is *already* malformed would become permanently unappendable — an agent could not even
add the entry that fixes it, and the only escape would be abandoning the note. So:
compute violations before and after; **reject only violations whose identity is new**.
Everything pre-existing degrades to a warning.

This is not a novel invention — it is exactly why the shell linter has `--staged` mode
("content rules run against ADDED lines only... demanding evidence retroactively would
force exactly the rewriting of old entries the guardrails forbid"). Same reasoning,
same conclusion, and the two implementations must stay behaviourally aligned (§7).

**D3 — Never auto-fix.** Locked-in decision #3. The error names the cause *and* the fix
in prose; the agent applies it. The shell linter's lesson holds: "a field was split
around inserted content" was true but useless, while "the `## Decisions Log` heading is
probably missing" is actionable. Error text is part of the deliverable, not decoration.

**D4 — Two severities only.** `.reject` (new, meaning-destroying: dated entry landing in
a current-state section; a repeated field within one block; a required section removed)
and `.warn` (everything else, including size). No third tier — a severity nobody can
describe is a severity nobody acts on.

**D5 — Violations surface twice.** In the tool result, so the writing agent sees them in
the same turn and can fix it immediately; and as a review flag, so a human sees it later
via `pending_reviews`. The tool result is the one that actually changes behaviour; the
flag is the durable record.

**D6 — Flags from validation need a reserved source.** `AGENTS.md` reserves `janitor` and
`ingest`. Validation is neither. Add `contract` to the reserved set and document it in
`AGENTS.md` alongside the others, or the flag will read as though an agent raised it.

---

## 5. Files to touch

**New**

| File | Contents |
|---|---|
| `Sources/UnliRiceCore/NoteContract.swift` | `NoteContract` (sections, fielded-block spec, size ceiling), `NoteContract.builtIn` with `project-notes-v1`, marker parsing (`contractId(inBody:)`) |
| `Sources/UnliRiceCore/NoteContractValidator.swift` | Pure: `validate(contract:body:) -> [Violation]` and `newViolations(before:after:contract:) -> [Violation]`. No I/O, no dates, no globals — trivially testable |
| `Tests/UnliRiceCoreTests/NoteContractTests.swift` | Fixtures replaying all four real failures (§1) plus the multi-track case |

**Modified**

| File | Change |
|---|---|
| `Sources/UnliRiceCore/NoteService.swift` | `createNote`/`appendToNote` compute the candidate body, validate, throw `NoteServiceError.contractViolation([Violation])` on `.reject`, otherwise append and return warnings. Needs a non-mutating "project as if appended" helper — see §6 |
| `Sources/unlirice-mcp/ToolDispatcher.swift` | Catch `contractViolation` → MCP error whose text names cause and fix. On success with warnings, attach them to the result payload. Add a `contractViolation` case to `ToolDispatchError` or map through it |
| `Sources/unlirice-mcp/ToolCatalog.swift` | Describe the behaviour in the `create_note`/`append_to_note` descriptions. An agent that cannot see the rule in the tool schema will keep hitting it |
| `Sources/UnliRiceCore/HouseRulesPreset.swift` | Pair `project-notes-v1` with a preset whose prose *says* what the validator *checks*. If instruction and check drift, the instruction loses and users learn to ignore both |
| `Sources/UnliRiceCore/ProfileTemplate.swift` | "Install notes guard" — emit `lint-project-notes.sh` + pre-commit hook into a chosen project folder. This is the part that generalizes the author's private fix to every user |
| `Sources/UnliRiceCore/Janitor/JanitorProposal.swift` | Contract violations become an additional proposal source, reusing the existing propose-never-resolve path rather than a parallel system |
| `AGENTS.md` | Document `contract` as a reserved source and the contract marker |
| `Tests/…/NoteServiceTests.swift` | Reject/warn/no-contract paths |

---

## 6. Edge cases

- **The projection helper is the risky part.** `NoteService.appendToNote` currently appends
  *then* projects. Validation needs the body *before* committing. Do not fake this by
  appending and rolling back — the log is append-only and has no rollback. Extract the
  fold so a candidate body can be computed in memory from `bodyBefore + text`, and prove
  it matches what the real projection produces (property test).
- **Concurrent writers.** Two agents can append between validate and commit, so a write
  can be validated against a body that is already stale. Accept this: the next write
  catches it, and the flag is durable. Do not add locking — it would be the first
  blocking primitive in an append-only store.
- **Multi-track handoffs are legitimate.** One codebase can ship two products. Validate
  each `### Track` independently; do not treat multi-track as malformed.
- **A note may adopt a contract it already violates.** Adding the marker must not
  retroactively reject the next write — D2 handles this, but it needs an explicit test.
- **Marker inside a fenced code block** (this plan file contains one) must not be read as
  a declaration. Parse outside fences.
- **`append_to_note` that only adds prose** to a compliant note must stay silent. If
  routine appends produce warnings, the warnings get ignored and the feature is dead.
- **Empty/whitespace fields.** `**Task:**` with nothing after it is present-but-empty.
  The shell linter treats presence as satisfied; match that, or the two disagree.

---

## 7. Verification

- `swift test`. The four §1 failures are fixtures; each must be caught at its intended
  severity, and the multi-track case must pass clean.
- **Cross-check against the shell linter.** Both implementations encode the same rules.
  Add a test running `Scripts/lint-project-notes.sh` over the same fixtures and assert
  the pass/fail verdicts agree. Two enforcement paths that disagree are worse than one.
- **Dogfood last, not first.** Unli Rice's own `PROJECT_NOTES.md` satisfies none of the
  four required sections — it is an architecture document that happens to share the
  filename. Decide whether to restructure it or leave it contract-free *before* adopting
  the marker anywhere, not during.
- A green suite is not evidence on its own. Verify against `git diff`.

---

## 8. Out of scope — the duplicate-ingest bug (tracked, not planned here)

The 29 duplicate flags share **one** cause, not 29. `LocalFileImporter` derives a note
title from parent directory + filename (`Doc: \(parent)/\(name)`), and `RawStore` dedupes
on **path** — its own comment says "path is what makes deduplication actually hold". So
one file reachable from two overlapping scan roots (`~/Documents/raw` and
`~/Documents/Unli Rice Vault/raw`) mints two notes with identical titles.

Fix direction: key ingest identity on **content hash** (`RawStore` already computes SHA256)
with path as a secondary attribute, so the same bytes reached by two paths resolve to one
note. Fixing ingest stops *generating* duplicates; the existing 29 are then a one-off
cleanup through the normal propose/resolve path, not 29 manual merges.

This deserves its own plan. It is unrelated to note structure and should not ride along.

---

## 9. Open questions for the pre-mortem

1. Is `.reject` right at all, or should everything warn? Blocking is what made the git
   hook work, but this store has never refused a write before. D2 narrows the blast
   radius; the pre-mortem should try to break that reasoning.
2. Does the in-body marker (D4/§3) belong in the body, or should contract adoption be a
   new `Event` kind? In-body needs no migration but is agent-editable — an agent can
   silently remove its own supervision.
3. Should `project-notes-v1` ship enabled for notes the Profile Builder generates, or
   stay opt-in everywhere?
