# REVIEW — pre-mortem of docs/PLAN-compact-retrieval.md

**Requested by:** the founder, 2026-11-16 ("Approve, carry on")
**Planner:** claude. **Reviewer:** codex, on its best model.

**This is a pre-mortem, not a build.** Write exactly one new file,
`docs/dialogue/compact-retrieval.md`, in the format of `docs/dialogue/README.md`
(header with `**State:** open`, then one turn headed
`## codex — pre-mortem — 2026-11-16`). Change nothing else: no code, no tests, no
config, no other docs, no `memory.md`, no commits. Don't edit the plan, the spec, the
intent or this brief. Don't start a nested `codex` run. Don't implement any task in
the plan. Don't call any Unli Rice connector tool, and don't open any real
`events.jsonl`; this review needs only the repository. You may run
`swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-codex` or a filtered
`swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-codex` to check a
claim, but nothing needs it.

## What you are reviewing

Three files, all on this branch (`claude/compact-retrieval`, based on `699d3bd`):

- `docs/intent/INTENT-014-compact-retrieval.md` (approved by the founder 2026-11-16)
- `docs/SPEC-compact-retrieval.md` (numbered requirements with checks)
- `docs/PLAN-compact-retrieval.md` (decisions D1–D12, tasks A0–A5)

Plus `AGENTS.md` § "Builder contract", which the builders will follow.

The work adds two read-only MCP tools, `search_note_summaries` and
`get_notes_batch`, and a benchmark. The Idea Clinic and intent read were skipped by
the founder; the plan header records it. That skip is not yours to re-litigate, but
a wrong intent is still a finding.

## Try to break it

The code wins over the plan. For each point say: right, wrong (with `file:line`),
or missing a step. Number your findings and give each a severity (blocker, should
fix, note). Mark anything you could not check from the repo "unverified".

1. **Plan §1 facts.** Check every claim against the source at the lines cited.
2. **Revision (D2, S6, S7).** Is count + XOR of event ids, folded in
   `NoteService.currentProjection()`, correct in every branch: incremental, causal
   mode (where `store.readAll()` can see more events than `batch`), `restarted`,
   `rebuild()`, and the `causalOrder` and `unrecognized` event kinds? Can the same
   event be folded twice, or an event be in the projection but not the revision?
   Does `EventStore` ever deliver duplicates or drop a partial trailing line in a
   way that breaks "same event set, same revision"? Is there a simpler honest
   revision already in the code that the plan missed?
3. **Cursor (D3, Q10–Q12).** The cursor binds to a digest of the ordered match ids
   instead of the corpus revision. Find a sequence of writes where the ordered id
   list is unchanged but continuing from position n is still wrong or misleading,
   or where the list changes but the digest does not. Is rejecting on any
   difference too strict to be usable? Is base64url JSON a problem anywhere?
4. **Budget (D4, D5, S3, Q8, Q9, B4–B6).** Is measuring
   `JSONSerialization.data(withJSONObject:)` of `{"content":[{"type":"text","text":…}]}`
   the same bytes `JSONRPC.writeLine` emits for the `result` member? Is 128 bytes of
   envelope reserve right? Can the minimal search item in Q9 fail to fit at 2048
   with worst-case title bytes (control characters, quotes, slashes)? Do the
   arithmetic. Can the batch status table for 20 ids fit at 2048, and is the B6
   error the right answer when it cannot? Is `retry_max_bytes` (B5) computable and
   stable?
5. **Matching and excerpts (D9, Q1, Q5).** Does routing `searchNotes` through a
   shared predicate change any existing behaviour, including the empty-query path?
   Where can `lowercased().contains` and a case-insensitive `range(of:)` disagree,
   and does Q5's fallback cover it without lying in `matched`?
6. **Dispatcher (D6, D12, S4, S9, A3).** Does returning early for the two tools
   skip anything the common path does that they need? Does the `MCPTool` change
   break any exhaustive switch elsewhere in `Sources/` (app, CLI, agent, Trust
   Center, connection activity)? Is strict argument typing sound with how
   `JSONSerialization` bridges numbers and booleans?
7. **Diagnostics and leaks (S5, B7).** Is there any path where text from a pending
   or conflicted note reaches a compact reply (a title, an excerpt, a tag, a link,
   an error message)?
8. **Benchmark (D10, M1–M5, A4).** Is the oracle procedure an honest comparison?
   What would make its numbers misleading? Are generated fixtures enough to hit
   pending and conflicted projections and a cross-instance write through the real
   process? Is anything flaky by construction (timings, temp paths, process pipes)?
9. **Step boundaries (§5, Handoff).** Is each of A1–A4 small and unambiguous enough
   for a Sonnet builder that may make no design calls? Name every place a builder
   would have to guess. Is anything labelled `build` that needs the planner?
10. **Scope and safety.** Anything that touches the live vault, persists a new
    format, adds a dependency, changes an existing tool's contract, or breaks
    `xcodegen`/Xcode targets. Anything from the studio security checklist that
    applies to parsing a caller-supplied cursor, query or id list.
11. **What is missing.** A requirement in the founder's intent with no spec id, a
    spec id with no task, or a failure mode nobody listed.

End with a one-line verdict: ship as planned, ship with changes, or do not build.
