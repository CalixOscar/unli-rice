# BENCH — compact retrieval against the existing tools

**Plan:** docs/PLAN-compact-retrieval.md (A5, A6). **Spec:** M1–M5.
**Run:** 2026-11-16, branch `claude/compact-retrieval`, by the planner (not a builder's report).
**Command:** `UNLIRICE_BENCH_OUT=/tmp/unlirice-bench.json swift test --scratch-path /tmp/unlirice-spm-compact`
(682 tests, 0 failed, 2 skipped; the benchmark test ran, it was not skipped).
**Machine:** Apple M5 Pro, 15 cores, 24 GB, macOS 27.2.1, debug build.
**Fixture:** 600 made-up notes, 1,507,669 bytes of events, generated in test code.
A second 7-note fixture holds the pending and conflicted notes. No real note was used.

## What was compared

- **Baseline:** one `search_notes` call, or one `get_note` per id.
- **Compact:** `search_note_summaries`, paged until the needed notes appear, then
  `get_notes_batch` for exactly those notes, retrying anything left out for size.

The compact procedure knows in advance which notes are the evidence. A real
assistant has to choose from the summaries, so its numbers will be the same or
worse. These figures are bytes and calls, not tokens, not model accuracy and not
provider speed. Bytes are whole reply lines.

## Totals over 24 tasks

| | Calls | Bytes | Expected outcomes observed |
|---|---|---|---|
| Baseline | 31 | 386,744 | 42 of 43 (one cannot be observed, see task 20) |
| Compact | 55 | 295,163 | 43 of 43 |

Compact returned 24% fewer bytes overall and made 77% more calls. All 54 compact
replies were within the `max_bytes` they were called with.

## Per task

| # | Task | Baseline calls / bytes | Compact calls / bytes |
|---|---|---|---|
| 1 | title-only token | 1 / 728 | 2 / 1,737 |
| 2 | title-only token | 1 / 3,311 | 2 / 4,327 |
| 3 | title-only token | 1 / 2,093 | 2 / 3,109 |
| 4 | body-only token | 1 / 2,267 | 2 / 3,270 |
| 5 | body-only token | 1 / 1,049 | 2 / 2,053 |
| 6 | body-only token | 1 / 1,362 | 2 / 2,367 |
| 7 | tag-only token | 1 / 3,815 | 2 / 4,827 |
| 8 | tag-only token | 1 / 2,597 | 2 / 3,609 |
| 9 | Unicode body | 1 / 1,607 | 2 / 2,619 |
| 10 | Unicode body | 1 / 4,191 | 2 / 5,202 |
| 11 | two 30 KB notes | 1 / 60,754 | 4 / 63,064 |
| 12 | one 80 KB note | 1 / 80,415 | 3 / 81,669 |
| 13 | same title, two notes | 1 / 4,231 | 2 / 5,771 |
| 14 | three notes, one timestamp | 1 / 6,480 | 2 / 8,504 |
| 15 | archived excluded, nothing matches | 1 / 77 | 1 / 322 |
| 16 | archived included | 1 / 4,263 | 2 / 5,274 |
| 17 | 5 needed out of 40 matches | 1 / 93,852 | 5 / 36,437 |
| 18 | instruction-like body | 1 / 473 | 2 / 1,226 |
| 19 | 3 existing + 2 missing ids | 5 / 9,273 | 1 / 9,097 |
| 20 | archived id, archived not wanted | 1 / 3,948 | 1 / 350 |
| 21 | pending id + 1 healthy | 2 / 3,376 | 1 / 3,299 |
| 22 | conflicted id + 1 healthy | 2 / 2,136 | 1 / 2,084 |
| 23 | note created by another writer | 2 / 547 | 3 / 1,550 |
| 24 | paging while another writer appends | 1 / 93,899 | 7 / 43,396 |

## Where compact is worse

- **Narrow searches (tasks 1–10, 13–16, 18, 23).** When a search matches one to
  three notes and all of them are wanted, the old tool already returns little.
  Compact costs one extra call and about 1,000 more bytes (the summary page).
- **Notes larger than the default reply size (tasks 11, 12).** Each 30 KB note
  needs its own retry at a larger size; the 80 KB note falls back to `get_note`.
  More calls, slightly more bytes.
- **Paging deep into a wide result (tasks 17, 24).** Fewer bytes, but 5 and 7
  calls. Task 24 includes one restart after the other writer changed the results.

## Where compact is better

- **Wide searches where few notes are wanted (17, 24):** 61% and 54% fewer bytes.
  This is the case the intent describes, and its saving grows with the number of
  matches, while the old tool's cost grows with it.
- **Reading several notes by id (19, 21, 22):** one call instead of two to five.
- **Archived notes (20):** the old `get_note` returns an archived note in full with
  no way to say "not wanted"; compact reports `archived_excluded` in 350 bytes.
- **A stated ceiling.** The largest compact reply is bounded by `max_bytes`. The
  largest baseline reply here was 93,899 bytes and has no ceiling.

## Timing (one body-only search, task 4; noisy, not asserted)

| | Cold, median of 3 launches | Warm, median of 10 |
|---|---|---|
| `search_notes` | 69.5 ms | 19.0 ms |
| `search_note_summaries` | 66.6 ms | 17.4 ms |
| summaries then batch | 67.5 ms | 18.1 ms |

Cold is process launch to first reply. No meaningful speed difference: both scan
and lowercase every note, as planned.

## Limits of this benchmark

- 18 of the 24 tasks search for a token that only one to three notes contain. Real
  queries ("auth", "release") match many notes, which is where compact saves the
  most. The totals above therefore understate the saving on wide queries and say
  nothing reliable about the mix a real assistant produces.
- The oracle never reads a note it does not need. A model will.
- Byte counts are not token counts.
- One machine, one run for timings, debug build.
- No assistant was told to prefer the new tools; nothing here measures adoption.
