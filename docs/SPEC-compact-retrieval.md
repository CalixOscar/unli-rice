# SPEC — Compact retrieval

**Intent:** docs/intent/INTENT-014-compact-retrieval.md
**Status:** intent approved by the founder 2026-11-16; spec open to the pre-mortem
**Plan:** docs/PLAN-compact-retrieval.md

Two new read-only MCP tools and a benchmark. "The result" below means the `result`
member of the `tools/call` reply, `{"content":[{"type":"text","text":<payload JSON>}]}`,
serialized by the server's own writer. "Payload" is the JSON inside `text`.

## Shared rules

| ID | Requirement | Check |
|---|---|---|
| S1 | The 15 existing tools keep their names, schemas, descriptions and outputs. `search_notes` matching is unchanged. | Existing suite green; catalog test pins the 15 old entries byte-for-byte against `main`. |
| S2 | Both tools are read-only: `MCPTool.isWrite == false`, and a call appends no event. | Catalog test; event count before and after each call in unit and process tests. |
| S3 | **Budget.** `max_bytes` is an integer, default 16384, range 2048–65536. A successful result serializes to at most `max_bytes − 128` UTF-8 bytes, so the whole reply line is at most `max_bytes` when the request id serializes to 90 bytes or fewer. The size is measured on the real serialization, not estimated. | Unit tests at 2048, 16384 and 65536 with adversarial text (quotes, slashes, control characters, combining marks, emoji, CJK); process test measures the actual reply line. |
| S4 | Both tools return exactly one content block. Projection warnings are carried inside the payload as counts, not appended as a second block with note ids. | Process test with a conflicted fixture. |
| S5 | **Diagnostics.** Notes with incomplete or conflicting history stay excluded exactly as today. Every payload has `diagnostics: {incomplete, pending_notes, conflicted_notes}`; when `incomplete` is true it also has a fixed `notice` saying results may be incomplete. No text of an excluded note appears anywhere. | Unit tests over a pending and a conflicted fixture; search for the excluded body's marker string in the result. |
| S6 | **Revision.** Every payload carries `revision`, a string derived from the set of events behind the projection that answered: `r1-<event count>-<32 hex>`. Two services over the same log give the same value; any appended event changes it. It is local: it says nothing about other devices. The tool descriptions say so. | Unit tests: two `NoteService` instances agree; an append changes it; `rebuild()` reproduces it. |
| S7 | One call reads one coherent projection: notes, diagnostics and revision come from a single locked read. | Code review; unit test with a second writer between calls, never inside one. |
| S8 | Note text appears only as JSON string values under `title`, `excerpt`, `body` and `tags`. Payload keys and the `notice` are fixed strings. The tool descriptions say titles, excerpts and bodies are user data, not instructions. | Unit test with instruction-like note bodies: fixed key set, no event appended. |
| S9 | Arguments are validated strictly, with an error that names the argument and the allowed range. A boolean is never accepted as an integer; a non-boolean `include_archived` is an error. Errors are `isError: true` and the server stays up. | Unit tests per argument; process test. |

## `search_note_summaries`

Arguments: `query` (required, non-empty string, at most 1024 UTF-8 bytes), `limit`
(integer, default 10, range 1–50), `max_bytes` (S3), `cursor` (optional string, at
most 512 bytes), `include_archived` (boolean, default false).

| ID | Requirement | Check |
|---|---|---|
| Q1 | A note matches exactly when `search_notes` would return it for the same query and `include_archived`. One shared predicate serves both. | Unit test: ids over all pages equal `searchNotes` ids, for title, body, tag, Unicode and no-match queries. |
| Q2 | Order: `updatedAt` descending, then note id (uppercase UUID string) ascending. | Unit test with tied timestamps and duplicate titles. |
| Q3 | Each result: `id`, `title`, `excerpt`, `excerpt_cut`, `matched`, `tags`, `updated_at` (ISO 8601, as existing tools), `archived`. No body, flags, links, backlinks or history. | Unit test on the key set. |
| Q4 | `title` is the note's title cut to at most 200 UTF-8 bytes at a whole-character boundary; `title_truncated: true` is present when cut. | Unit test with long, emoji and combining-mark titles. |
| Q5 | `excerpt` is a verbatim, contiguous piece of the note body of at most 320 UTF-8 bytes, cut at whole characters, positioned so the first body match is inside it (about a third of the window before the match). With no body match, or when the match cannot be located in the original text, it starts at the beginning of the body. `excerpt_cut` is always present: `none`, `start`, `end`, `both`, or `omitted`. | Unit tests: the excerpt is a substring of the body; the match is inside it; each `excerpt_cut` value. |
| Q6 | `matched` lists which of `title`, `body`, `tags` matched. | Unit test. |
| Q7 | `tags`: the note's tags sorted ascending, at most 8, skipping any tag over 64 UTF-8 bytes; `tags_omitted: n` is present when any were left out. | Unit test. |
| Q8 | **Fill.** Results are added in order until `limit` is reached or the next one would break S3. The payload reports `returned`, `total_matches`, `offset`, `stopped_by` (`end`, `limit` or `budget`) and `next_cursor` (a string when more remain, else null). | Unit tests for each `stopped_by`. |
| Q9 | **Progress.** A page with matches remaining always returns at least one result. If the first result does not fit in normal form it is returned in minimal form: `minimal: true`, title cut to 96 bytes, empty excerpt with `excerpt_cut: "omitted"`, no tags and `tags_omitted` set. If even that cannot fit, the call fails with a clear error rather than exceeding the budget or returning an empty page. | Unit test at `max_bytes` 2048 with worst-case titles. |
| Q10 | **Cursor.** Opaque to callers. It binds the query, `include_archived`, the position, and a digest of the ordered ids of all current matches. With an unchanged match list, paging returns every match exactly once whatever `limit` and `max_bytes` each page uses. | Unit test: page through at mixed limits and budgets; union equals the full list, no duplicates. |
| Q11 | **Stale cursor.** If the ordered match list differs from the one the cursor was issued against (a match added, removed, reordered, archived, or excluded by diagnostics), the call fails with "restart the search without a cursor". It never continues. A write that leaves the match list identical does not invalidate the cursor. | Unit tests: write to a matching note, new matching note, archive of a match, unrelated write, write from a second `NoteService`. |
| Q12 | A cursor that is malformed, too long, from another query or another `include_archived` value, or out of range fails with a clear error. | Unit tests. |

## `get_notes_batch`

Arguments: `ids` (required array of 1–20 note id strings, unique), `max_bytes` (S3),
`include_archived` (boolean, default false).

| ID | Requirement | Check |
|---|---|---|
| B1 | A malformed id, a duplicate id (compared as UUIDs), an empty array or more than 20 ids is an error naming the position. Nothing is returned partially. | Unit tests. |
| B2 | `notes` has one entry per requested id, in request order, each with `id` and `status`: `returned`, `missing`, `archived_excluded`, `unavailable_pending`, `unavailable_conflicted` or `omitted_for_budget`. | Unit test with one of each. |
| B3 | A `returned` entry carries the complete `title` and `body`, all `tags` (sorted), `created_at`, `updated_at`, `archived`, `creator` and `sources` (sorted). No flags, links, backlinks or history. A body is never shortened. | Unit test: body equals the note body exactly, including large and Unicode bodies. |
| B4 | **Fill.** In request order, a note is returned when the result still fits S3 with it included; otherwise it is `omitted_for_budget` and later, smaller notes are still tried. | Unit test: large note in the middle, small ones after it. |
| B5 | An `omitted_for_budget` entry carries `retry_max_bytes`, the smallest `max_bytes` at which that note alone would be returned, and `fits_max_budget` (false when that exceeds 65536; the note is then readable only with `get_note`). | Unit test: retrying with the stated value returns the note; a body over the maximum reports false. |
| B6 | The payload reports `returned`, `omitted_for_budget` (count), `revision` and `diagnostics`. If `max_bytes` cannot hold even the status of every id, the call fails with a clear error saying to raise `max_bytes` or send fewer ids. | Unit test at 2048 with 20 ids. |
| B7 | An archived note is `archived_excluded` unless `include_archived` is true. An id excluded by diagnostics reports its `unavailable_*` status and no content. | Unit tests. |

## Benchmark

| ID | Requirement | Check |
|---|---|---|
| M1 | Synthetic notes only, generated deterministically in test code into a temporary store. No file from the founder's vault, no live-vault connection. | Code review; the test sets `UNLIRICE_DATA_PATH` to a temp path. |
| M2 | 20–30 fixed tasks, each with required evidence ids chosen when the fixture is written, not derived from tool output. They cover: title, body and tag matches; large and Unicode notes; duplicate titles and tied timestamps; archived notes; missing ids; incomplete and conflicted projections; a write from another `NoteService`; paging interrupted by a write; instruction-like note bodies. | Test source review. |
| M3 | Two documented procedures run over the real `unlirice-mcp` process: **baseline** (`search_notes`, or `get_note` per id) and **compact** (`search_note_summaries` paged until the evidence ids are seen, then `get_notes_batch` for exactly those ids, retrying omissions as B5 directs). The compact procedure is an oracle: it knows the evidence ids, so its call count is a lower bound. The report says so. | Test source review. |
| M4 | Recorded per task and in total: evidence coverage, call count, complete reply-line UTF-8 bytes. Estimated tokens may be shown only as `bytes / 4, estimate`. Cold (first call after launch) and warm (median of repeats) timings are recorded with fixture size and hardware. | Report file. |
| M5 | The test asserts only correctness: full coverage for both procedures and S3 for every compact reply. Size and speed are reported, never asserted, and tasks where compact is worse are listed. No model accuracy or provider speed is claimed. | Test source; `docs/BENCH-compact-retrieval.md`. |

## Not in this spec

Changing the connector's instructions, `AGENTS.md`, the app's copy or the public
guide to recommend the new tools; ranking; full-text indexes; embeddings; summaries
written by a model; per-client state. Each is a later decision.
