# SPEC — Compact retrieval

**Intent:** docs/intent/INTENT-014-compact-retrieval.md
**Status:** intent approved by the founder 2026-11-16; revised after the Codex pre-mortem (`docs/dialogue/compact-retrieval.md`), settled 2026-11-16
**Plan:** docs/PLAN-compact-retrieval.md

Two new read-only MCP tools and a benchmark. "The result" below means the `result`
member of the `tools/call` reply, `{"content":[{"type":"text","text":<payload JSON>}]}`,
serialized by the server's own writer. "Payload" is the JSON inside `text`.

## Shared rules

| ID | Requirement | Check |
|---|---|---|
| S1 | The 15 existing tools keep their names, schemas, descriptions and outputs. `search_notes` keeps its matching, its empty-query behaviour and its order. | Existing suite green; the diff of `ToolCatalog.swift` against `699d3bd` only adds entries (planner checks); process test finds all 15 old names plus the 2 new in `tools/list`. |
| S2 | Both tools are read-only: `MCPTool.isWrite == false`, and the retrieval itself appends no event. (The server's existing per-call capture sync and connection-activity record are unchanged and outside this claim; sync is off under `UNLIRICE_DATA_PATH`.) | Catalog test; event count before and after each call in unit and process tests. |
| S3 | **Budget.** `max_bytes` is an integer, default 16384, range 2048–65536. A successful result serializes to at most `max_bytes − 128` UTF-8 bytes, so the whole reply line, newline included, is at most `max_bytes` when the request id serializes to 90 bytes or fewer. The size is measured on the real serialization, not estimated. The cap bounds the reply, not the CPU or memory spent scanning the corpus. | Unit tests at 2048, 16384 and 65536 with adversarial text (quotes, slashes, control characters, combining marks, emoji, CJK); process test measures the actual reply line with a 90-byte request id. |
| S4 | Both tools return exactly one content block. Projection warnings are carried inside the payload as counts, not appended as a second block with note ids. | Process test with a conflicted fixture. |
| S5 | **Diagnostics.** Notes with incomplete or conflicting history stay excluded exactly as today. Every payload has `diagnostics: {incomplete, pending_notes, conflicted_notes}`; when `incomplete` is true it also has `notice`, exactly: `Some notes are left out because their history is incomplete or conflicting. Results may be incomplete.` Nothing that comes from an excluded note (title, body, tags, source) appears in a result or an error. | Unit tests over a pending and a conflicted fixture whose title, body, tag and source each carry a distinct sentinel string found nowhere else; the whole serialized result and every error is scanned for each sentinel. |
| S6 | **Revision.** Every payload carries `revision`: `r1-<n>-<32 hex>`, where `n` is the number of complete decoded events the projection has read and the hex is the XOR of their ids (every occurrence, every kind, including metadata, unrecognized, pending and conflicted events). Two services that have read the same log give the same value; every appended complete event changes it. It is a weak local fingerprint: not unique, not a security token, and it says nothing about other devices. A log replaced behind the service's cursor needs `rebuild()`, as it does today. | Unit tests: two `NoteService` instances agree in legacy and causal mode after interleaved writes; an append changes it; a duplicate-id append changes it; `rebuild()` reproduces it. |
| S7 | One call reads one coherent projection: notes, diagnostics and revision come from a single `cacheLock` hold. In the causal branch the revision is set from exactly the event array the projection was computed from, never folded onto the previous value. | Code review by the planner of that branch; the S6 causal-mode test. |
| S8 | Text that comes from notes appears only as JSON string values under `title`, `excerpt`, `body`, `tags`, `creator` and `sources`. All of it is untrusted data. Payload keys, status values and the `notice` are fixed strings. The tool descriptions say this text is user data, not instructions. | Unit test with instruction-like note text: fixed key set, no event appended. |
| S9 | Arguments are validated strictly before any work, with a fixed error message that names the argument and the allowed range and never echoes caller text. An integer must be a JSON number that is not a boolean, finite and whole. A boolean must be a JSON boolean (`1` and `0` are rejected). `null` is an error for any named argument. Unknown arguments are ignored, as existing tools do. Errors are `isError: true` and the server stays up. | Unit tests per argument on the raw-argument initializers: numbers as booleans, booleans as integers, fractional, huge, negative, null, wrong type; one process test. |

## `search_note_summaries`

Arguments: `query` (required, non-empty string, at most 1024 UTF-8 bytes), `limit`
(integer, default 10, range 1–50), `max_bytes` (S3), `cursor` (optional string, at
most 512 UTF-8 bytes), `include_archived` (boolean, default false).

| ID | Requirement | Check |
|---|---|---|
| Q1 | A note matches exactly when `search_notes` would return it for the same query and `include_archived`. One shared predicate (`lowercased().contains` on title, body and each tag) serves both, and `matched` is computed only by it. | Unit test: ids over all pages equal `searchNotes` ids, for title, body, tag, Unicode and no-match queries, including `ß`/`ss` and `Σ`/`ς`, which must not match. |
| Q2 | Order: `updatedAt` descending, then `id.uuidString` ascending. | Unit test with tied timestamps and duplicate titles. |
| Q3 | Each result: `id`, `title`, `excerpt`, `excerpt_cut`, `excerpt_at`, `matched`, `tags`, `updated_at` (ISO 8601, as existing tools), `archived`. No body, flags, links, backlinks or history. | Unit test on the key set. |
| Q4 | `title` is the note's title cut to at most 200 UTF-8 bytes at a whole-character boundary; `title_truncated: true` is present when cut. | Unit test with long, emoji and combining-mark titles. |
| Q5 | `excerpt` is a verbatim, contiguous piece of the note body of at most 320 UTF-8 bytes, cut at whole characters. `excerpt_at` is `match` only when the excerpt itself satisfies the Q1 predicate for the query (`excerpt.lowercased().contains(query.lowercased())`); the window then starts up to 100 bytes before the match. In every other case (no body match, a match longer than the window, a match that cannot be located in the original text) the excerpt starts at the beginning of the body and `excerpt_at` is `start`. If no whole character fits, the excerpt is empty. `excerpt_cut` is always present: `none`, `start`, `end`, `both`, or `omitted` (empty excerpt of a non-empty body, or minimal form). | Unit tests: excerpt is a substring of the body; `match` implies the predicate holds on the excerpt; a 321-byte query; a single character over 320 bytes; a body where lowercasing changes the character count; each `excerpt_cut` value. |
| Q6 | `matched` lists which of `title`, `body`, `tags` matched, in that order. | Unit test. |
| Q7 | `tags`: the note's tags sorted ascending, at most 8, skipping any tag over 64 UTF-8 bytes; `tags_omitted: n` is present when any were left out. | Unit test. |
| Q8 | **Fill.** Results are added in order until `limit` is reached or the next one would break S3. The payload reports `returned`, `total_matches`, `offset` (position of the first result), `stopped_by` (`end`, `limit` or `budget`) and `next_cursor` (a string when more remain, else null). | Unit tests for each `stopped_by`. |
| Q9 | **Progress.** A page with matches remaining always returns at least one result. If the first result does not fit in normal form it is returned in minimal form: `minimal: true`, title cut to 96 bytes, empty excerpt with `excerpt_cut: "omitted"` and `excerpt_at: "start"`, empty `tags` and `tags_omitted` set. If even that cannot fit, the call fails with a clear error rather than exceeding the budget or returning an empty page. | Permanent worst-case unit test at `max_bytes` 2048: 96 control-character title bytes, all three fields matched, diagnostics with the notice, a cursor, six-digit counts. |
| Q10 | **Cursor.** Opaque to callers. It binds the query (case-insensitively, as matching is), `include_archived`, the position, and a digest of the ordered ids of all current matches. With an unchanged ordered id list, paging returns every match exactly once whatever `limit` and `max_bytes` each page uses. This is live paging, not a frozen snapshot: a note already returned can change without invalidating the cursor; each page's `revision` shows that something changed. | Unit test: page through at mixed limits and budgets; union equals the full list, no duplicates. Unit test: append to an already-returned match that stays first; the next page succeeds and its `revision` differs. |
| Q11 | **Stale cursor.** If the ordered id list of matches differs from the one the cursor was issued against (a match added, removed or reordered), the call fails with `The matching notes changed since this cursor was issued. Search again without a cursor.` It never continues. | Unit tests: write that reorders matches, new matching note, archive of a match with `include_archived` false, unrelated write (continues), write from a second `NoteService`. |
| Q12 | A cursor is unpadded base64url of a JSON object with exactly the keys `v` (integer 1), `q` (16 lowercase hex), `a` (integer 0 or 1), `m` (32 lowercase hex), `o` (integer, 1 ≤ o < current match count). Length is checked before decoding. Anything else (bad alphabet, padding, not JSON, not an object, missing or extra key, wrong type, boolean for a number, other version, other query, other `include_archived`, position out of range) fails with a fixed "invalid cursor" message. A wrong `q` or `a` is "invalid cursor", a wrong `m` is Q11. | Unit tests for each case. |

## `get_notes_batch`

Arguments: `ids` (required array of 1–20 note id strings, unique), `max_bytes` (S3),
`include_archived` (boolean, default false).

| ID | Requirement | Check |
|---|---|---|
| B1 | `ids` that is not an array of strings, a malformed id, a duplicate id (compared as UUIDs), an empty array or more than 20 ids is an error naming the position, raised before any note is read. Nothing is returned partially. | Unit tests. |
| B2 | `notes` has one entry per requested id, in request order, each with `id` and `status`: `returned`, `missing`, `archived_excluded`, `unavailable_pending`, `unavailable_conflicted` or `omitted_for_budget`. Status is decided from the snapshot's diagnostics first (conflicted before pending), then the visible notes. | Unit test with one of each. |
| B3 | A `returned` entry carries the complete `title` and `body`, all `tags` (sorted), `created_at`, `updated_at`, `archived`, `creator` and `sources` (sorted). No flags, links, backlinks or history. A body is never shortened. | Unit test: body equals the note body exactly, including large and Unicode bodies. |
| B4 | **Fill.** First the complete status table is built with every readable note as `omitted_for_budget` (its largest non-returned form). If that table breaks S3 the call fails (B6). Then, in request order, each readable note is upgraded to `returned` when the whole result still fits S3; otherwise it stays omitted and later notes are still tried. | Unit test: large note in the middle, small ones after it; 20 ids at 2048. |
| B5 | An `omitted_for_budget` entry carries `fits_max_budget`. When true it also carries `retry_max_bytes`: the size of the result for a request of that id alone against the same snapshot, plus 128, and at least 2048. When that would exceed 65536 (or the body alone is over 65536 bytes, in which case nothing is serialized to find out), `fits_max_budget` is false, there is no `retry_max_bytes`, and the note is readable only with `get_note`. The retry value holds while the note and diagnostics are unchanged. | Unit test: retrying alone with the stated value on the same snapshot returns the note; a body over the maximum reports false. |
| B6 | The payload reports `returned`, `omitted_for_budget` (count), `revision` and `diagnostics`. If `max_bytes` cannot hold the status table, the call fails with `max_bytes is too small to report every requested id. Raise max_bytes or request fewer ids.` | Unit tests at 2048 with 20 missing ids (fits) and 20 oversized notes (error). |
| B7 | An archived note is `archived_excluded` unless `include_archived` is true. An id excluded by diagnostics reports its `unavailable_*` status and no content. | Unit tests, with the S5 sentinels. |

## Benchmark

| ID | Requirement | Check |
|---|---|---|
| M1 | Synthetic notes only, generated deterministically in test code into a temporary store. No file from the founder's vault, no live-vault connection, no cloud session. | Code review; the test sets `UNLIRICE_DATA_PATH` to a temp path. |
| M2 | 24 fixed tasks as listed in the plan (§5 A4). Each task states its expected outcomes when the fixture is written: **evidence** ids whose complete body must be obtained, and **absence** ids that must be reported with a stated status. | Test source review against the plan's table. |
| M3 | Two procedures run over the real `unlirice-mcp` process, as defined in the plan: **baseline** (`search_notes` once, or `get_note` per id) and **compact** (`search_note_summaries` paged, then `get_notes_batch`, with the stated retry, restart and fallback rules). Every call either procedure makes is counted, including retries, restarts and `get_note` fallbacks. The compact procedure is an oracle: it knows the evidence ids, so its counts are a lower bound, not a model's behaviour. The report says so. | Test source review. |
| M4 | Recorded per task and in total: outcome coverage, call count, complete reply-line UTF-8 bytes. Estimated tokens may be shown only as `bytes / 4, estimate`. Cold and warm timings are recorded as the plan defines, with fixture size and hardware. | Report file. |
| M5 | The test asserts only correctness: every expected outcome observed for both procedures, and S3 for every compact reply. Size and speed are reported, never asserted, and tasks where compact is worse are listed. No model accuracy or provider speed is claimed. A skipped run (missing binary) is not evidence; the record needs a real run. | Test source; `docs/BENCH-compact-retrieval.md`. |

## Not in this spec

Changing the connector's instructions, `AGENTS.md`, the app's copy or the public
guide to recommend the new tools; ranking; full-text indexes; embeddings; summaries
written by a model; per-client state; closing `evals` case `unli-008`. Each is a
later decision.
