# Draft — reusable specification template

**Status:** working draft for review; not an approved studio convention.

This template helps a person and their AI describe what should be built and how
to tell whether it works. It does not approve an idea, start a build, or prove a
test passed. Keep unanswered questions visible; do not fill them with guesses.
The person reviews the result before treating it as an agreed specification.

**Codex recommendation, pending founder decision and Claude's review:** use a
short separate specification for substantial work. The intent owns the problem,
desired outcome and boundaries; the spec owns numbered observable requirements,
proposed checks and unknowns; the plan owns the file-scoped steps. Link the
artifacts by feature and revision instead of copying their contents between them.
Keep small changes proportionate under an explicitly agreed fast path. Claude's
fetched Studio draft also proposes a separate spec; this does not claim Claude
has reviewed or endorsed this recommendation.

This is a proposed change, not the current studio rule: the vault currently
treats the intent document as the specification. Resolve the difference before
adopting this template or treating either approach as authoritative. Until a
source of truth is chosen, say so. Once chosen, identify copies as snapshots;
they do not update one another automatically.

---

# <Specific feature or problem>

**Status:** draft
**Decision owner:** <person or role, or unknown>
**Planner:** <person or tool responsible for delivery, or not yet assigned>
**Intent:** <authoritative intent path and revision, or not yet decided>
**Source of truth:** <repository and path, other chosen source, or not yet decided>
**Revision:** <unique revision and commit or explicitly uncommitted snapshot, or unknown>
**Based on:** <links or references to the source idea and decisions, or none>

Only the person authorized to decide may approve a draft. For studio intents,
record the founder's approval and date; if an approved intent is wrong, write a
new intent and identify the one it supersedes.

## Context and boundaries

Link the intent for the problem, people, desired outcome, scope and experience;
do not maintain a second copy here. Add a one-sentence orientation if useful.
Record a constraint or dependency here only when it narrows a requirement and
link its source. Mark missing decisions as unknown.

## Acceptance and verification

For each requirement, give an observable scenario and a proposed way to check it.
Include relevant empty, incomplete, failed, interrupted and return states. Actual
results belong in the delivery plan or review record, not retroactive edits to
an approved studio intent.

| ID | Scenario and expected result | Proposed verification |
|---|---|---|
| A1 | <Given … when … then …> | <specific test or observed walkthrough> |

## Open questions and assumptions

- **Open question:** <what is undecided, who can decide it, and when needed>
- **Assumption:** <what is being assumed and what would confirm or change it>
- **Unknown:** <missing fact and, if known, how to establish it>

## Decisions and changes

Record decisions known at approval, with their dates and supporting evidence.
Identify the authoritative version when it has been chosen. When recording a
later revision in an append-only note, give it a distinct identifier and say
which version it supersedes; retain earlier material as history. Updating a note
does not update a repository document automatically.

## Delivery evidence belongs elsewhere

Link to the delivery plan or review record. There, keep built behavior, actual
verification and evidence, unverified checks, and remaining work separate.
Do not rewrite an approved studio intent to match what was implemented.
