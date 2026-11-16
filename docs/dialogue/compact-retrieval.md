# Dialogue — compact-retrieval

**Plan:** docs/PLAN-compact-retrieval.md
**Planner:** claude
**Reviewer:** codex
**State:** settled

## codex — pre-mortem — 2026-11-16

Reviewed intent, spec, plan and repository at `79f3376` (source unchanged from
`699d3bd`). This is a review only: no implementation, connector calls, real vault
reads, plan edits or commits. Findings below distinguish confirmed facts from
contracts that still need a planner decision. The recorded founder skips stand.

1. **[blocker] Wrong: Q5 cannot always contain the body match.** The accepted query
   is up to 1024 UTF-8 bytes, but the excerpt is at most 320 bytes
   (`docs/SPEC-compact-retrieval.md:27-37`). A body containing a query consisting of
   321 ASCII `a` characters has a locatable match that cannot fit. Even a short
   query can match within one extended grapheme cluster larger than 320 bytes;
   cutting at whole-character boundaries cannot include that character. The
   no-location fallback does not cover either case. Specify which promise yields,
   what the excerpt and cut marker mean, and tests for both cases before A1.

2. **[blocker] Missing a step: the benchmark has no satisfiable procedure for all
   required tasks.** M2 requires missing, pending and conflicted ids, interrupted
   paging, and large notes; M3 searches until evidence ids appear and then batches
   exactly those ids; M5 requires full coverage for both procedures
   (`docs/SPEC-compact-retrieval.md:66-69`). Missing and excluded ids never appear
   in search; `get_note` throws for pending/conflicted ids
   (`Sources/UnliRiceCore/NoteService.swift:211-214,296-298`). A note larger than
   the maximum batch budget needs `get_note`, which B5 permits but M3's compact
   procedure never specifies. Stale-cursor recovery is also unspecified. Define
   per-task expected outcomes, distinguishing evidence content from correctly
   reported absence/unavailability, an end-of-search termination condition,
   bounded restarts, oversized-note fallback and how all their calls/bytes count.
   These are planner choices, not builder implementation details.

3. **[should fix] Missing a step: D2 must distinguish a set from a multiset and
   narrow its replacement claim.** `EventStore.append` and `appendRaw` do not
   deduplicate ids (`Sources/UnliRiceCore/EventStore.swift:224-240`); reads return
   every decoded line (`:341-355`). Repeating the same event changes count/XOR
   despite leaving the event-id set unchanged. In causal mode the projector
   deduplicates semantic ids (`Sources/UnliRiceCore/EventCausalOrder.swift:47-48,
   129-139`); in legacy mode repeated events are replayed (`:69-73`). S6's
   “set of events” and “any appended event changes it” therefore need a precise
   definition (`docs/SPEC-compact-retrieval.md:20`). A count/XOR of decoded event
   occurrences is an honest weak log fingerprint; a distinct-id set requires
   different bookkeeping and cannot change for a duplicate append. Choose and
   test it. Equal ids with different event contents and count/XOR collisions are
   further reasons this cannot identify projection contents uniquely. The plan
   already accepts crafted-id collisions (`docs/PLAN-compact-retrieval.md:228`);
   do not turn this into a security or equality guarantee.

   “Survives a replaced log” in D2 is too broad. Restart detection only handles a
   file shorter than the old cursor (`EventStore.swift:315-323`). Same-size
   replacement returns the cache; larger replacement can read from the middle of
   a new log. Either explicitly require `rebuild()` after replacement and limit
   guarantees to supported append/restart behavior, or send the cache-invalidation
   change back through the planner. There is no existing reusable revision in
   `NoteService` or `EventStore`; byte offset is not an alternative fingerprint.

4. **[note] Right, with tests missing: D2's branch-specific fold avoids the
   causal read race if followed literally.** `currentProjection()` holds
   `cacheLock` but releases the store lock between its incremental read and full
   causal read (`Sources/UnliRiceCore/NoteService.swift:261-292`). A second writer
   can append event E between them. The full read includes E while `batch.cursor`
   still precedes it. Set revision from exactly that full `events` array; never
   XOR that full array into the prior accumulator. The next call sees E in its
   batch and recomputes the full causal projection/revision again, rather than
   double-folding E. Incremental mode folds its batch once. Reset on `rebuild()`
   (`:96-103`) and on `restarted`, including a restart to an empty file. Include
   `.causalOrder`, `.unrecognized` and pending/conflicted events in the revision
   input even though some do not become visible note content
   (`Sources/UnliRiceCore/Projector.swift:49-55`). Partial trailing lines are
   deferred, not lost, and native strict reads reject them
   (`EventStore.swift:329-355`); define the revision over decoded complete events,
   not physical bytes or malformed skipped lines. A test with a writer only
   between tool calls (S7) does not exercise the two-read race. Add deterministic
   coverage or an explicit code-review obligation for that branch.

5. **[should fix] Right for positions, missing a statement about changing
   content: D3 is live pagination, not snapshot pagination.** With identical
   ordered ids, continuing at offset n cannot skip or duplicate an id. However,
   let A be the newest match, return A on page 1, then append relevant evidence to
   A while it remains newest. The id digest is unchanged, page 2 succeeds, and
   the caller never sees A's new excerpt. A tag change can similarly change
   relevance without changing positions. Per-page revision makes this observable,
   but does not provide an automatic reread. This is consistent with Q10–Q11 if
   documented; it is misleading to claim “matching notes change” always rejects
   the cursor (`docs/PLAN-compact-retrieval.md:180-183`). Likewise archiving with
   `include_archived: true` need not change the list. Revise that description and
   add a same-list content-change test; do not silently change to revision-bound
   cursors. Rejecting every list change is conservative and can require repeated
   restarts on a busy search; usability frequency is unverified.

   The specified cursor stores fixed hashes, not the query text; a representative
   cursor measures 108 bytes, safely below 512. Base64url JSON is suitable here.
   Hashing ordered fixed-width UUID bytes has no delimiter ambiguity. Truncating
   SHA-256 to 128 bits for matches (64 bits for the query) is not mathematically
   collision-free, but no practical accidental collision or sequence of ordinary
   writes defeating the ordered-id digest was found. It is not authentication.

6. **[should fix] Missing a step: define the complete cursor validation
   contract.** A1 gives `{v,q,a,m,o}` but not the accepted decoded types, unknown
   key policy, padding/canonicalization policy, or position bounds
   (`docs/PLAN-compact-retrieval.md:158-162`). Require the supported version,
   expected hash shapes, strict integer/flag types, and a checked nonnegative
   offset before indexing. Decide whether an offset equal to match count is
   accepted and whether case-only query changes are the same query (the hash is
   lowercased, while Q12 says “another query”). Bound encoded UTF-8 bytes before
   decoding. Forged but structurally valid offsets are not a permission bypass:
   callers already have access to this local corpus. Test malformed JSON, wrong
   root/field types, unsupported versions, huge/negative offsets and booleans in
   numeric fields, without echoing arbitrary caller text in errors.

7. **[note] Right: S3's envelope arithmetic and serialization method.**
   `JSONRPC.writeLine` uses default `JSONSerialization` and adds one newline;
   `JSONRPC.result` supplies only `jsonrpc`, `id`, and `result`
   (`Sources/UnliRiceCore/JSONRPC.swift:10-18`). Embedding a result dictionary does
   not re-escape its string values again compared with serializing that result
   dictionary alone. The complete envelope overhead is 34 bytes plus serialized
   id length, including newline: at the specified 90-byte id bound it is 124,
   so 128 is sufficient. Measuring payload JSON alone would be wrong: payload is
   a JSON string inside the content block and must be escaped at that layer.
   Foundation probes in this session confirm slash escaping and this 124-byte
   overhead. Process tests must include a 90-byte serialized id and newline.

   Worst-case one-byte title controls encode as six characters (`\u0001`) in
   payload JSON and seven bytes after the payload's backslash is escaped for the
   content string. A 96-byte minimal title therefore costs 672 bytes in that
   string; quotes, slashes, emoji and CJK do not exceed this bound per original
   byte. A measured minimal item with a truncated title of 96 such controls,
   all three matched fields, omitted tags, diagnostics, revision, cursor and the
   notice “Results may be incomplete.” produces a 1395-byte result, below 1920
   (=2048−128). This is a concrete representative calculation, not a proof over
   unspecified notice text or unbounded counter widths. The planner must fix
   that notice text and final payload shape for a permanent worst-case test.

8. **[should fix] Missing a step: batch sizing must reserve the final status
   table, and retry semantics need an explicit unchanged-snapshot condition.**
   Using the same Foundation serializer and sample metadata above, twenty
   `missing` entries measure 1733 result bytes, while twenty
   `omitted_for_budget` entries with `retry_max_bytes:65537` and
   `fits_max_budget:false` measure 2994. Thus a 2048-byte call sometimes fits
   twenty statuses and sometimes cannot; B6 is a necessary, correct error escape
   (`docs/SPEC-compact-retrieval.md:53-59`). Precompute complete statuses/retry
   metadata, then test candidate bodies against the whole final payload. Otherwise
   a greedy partial response can consume space needed by later omission entries.
   The exact algorithm and precedence when metadata itself does not fit need
   settling for A2; do not allow the builder to silently drop ids.

   For an unchanged snapshot, the minimal singleton retry is computable from the
   serialized singleton *returned* payload plus 128, clamped up to 2048; its
   returned count is one and omitted count zero. A value above 65536 is a size
   estimate, not a valid retry argument. A later write can change a body, revision
   length, diagnostics or notice, so B5's retry success is not stable across
   arbitrary writes. Specify that qualification and singleton retry convention.
   Serialization of oversized candidate bodies is not bounded to 64 KB as D4's
   rationale suggests (`docs/PLAN-compact-retrieval.md:66`); B3 permits arbitrarily
   large existing bodies. Record the temporary allocation/performance limit.

9. **[should fix] Matching is right only if excerpt location uses the same
   predicate; Foundation case-insensitive range search is not equivalent.**
   Preserve `searchNotes`' empty-query early return and existing order
   (`Sources/UnliRiceCore/NoteService.swift:226-234`); sort only the new tool's
   results by the new tie-breaker. Foundation probes here show `"ß"` with query
   `"ss"`, and `"Σ"` with query `"ς"`, have a case-insensitive range but fail
   `lowercased().contains`. If another field matched, a range-only excerpt path
   would incorrectly treat the body as matched. Compute `matched` solely with
   the original lowercased predicate, and only attempt body-location when that
   predicate says body matched. Specify how to choose the first valid range if
   range search has broader matching semantics. Q5's no-location fallback can
   honestly retain `matched: body` when the predicate matched but original-text
   positioning failed; it does not repair a false positive introduced by range
   search. Add Unicode disagreement tests alongside the long-match cases in 1.

10. **[should fix] Wrong if implemented by ordinary Swift casts: strict
    Boolean validation needs CF type identity too.** The existing integer check
    correctly rejects `CFBoolean` before conversion
    (`Sources/unlirice-mcp/ToolDispatcher.swift:41-44`). Foundation JSON probes
    show both JSON `1` and `0` cast successfully with `as? Bool`, and `true` casts
    with `as? Int`. For `include_archived`, explicitly require an `NSNumber` whose
    `CFGetTypeID` equals `CFBooleanGetTypeID`; do not copy old tools' `as? Bool`
    handling (`:133-134`). Bound/check integral values before conversion. Decide
    null-versus-absent and unknown-argument behavior. Add process tests for numbers
    as booleans, booleans as integers, fractional/huge numbers and nulls. These are
    schema/contract decisions A3 currently leaves to a builder.

11. **[note] Right: the proposed dispatcher early return skips no required
    authorization or activity step.** Its common tail only serializes payload
    and makes a second diagnostic read (`ToolDispatcher.swift:162-175`); the new
    result is already serialized and has coherent diagnostics. Return inside the
    `do` so failures still use `isError: true` (`:176-182`). Synchronization and
    activity recording remain in `Sources/unlirice-mcp/main.swift:209-219`.
    Searching `Sources/` found only the dispatcher and `MCPTool.isWrite` switches
    over this enum (`Sources/UnliRiceCore/MCP/MCPToolCatalog.swift:29-37`), both
    included in A3. The similarly named first-run UI switch is over client choices,
    not `MCPTool`. Activity classifies via `isWrite`
    (`Sources/UnliRiceCore/MCP/ConnectionActivity.swift:138-145`), so no extra
    app/CLI/agent/Trust Center case was identified.

    Read-only means no event appended by the retrieval itself, not no filesystem
    side effect: real-process pre-call sync may import events, and connection
    activity writes a sidecar even under a test override. S2's event-count test
    is valid with `UNLIRICE_DATA_PATH`, which disables sync
    (`main.swift:102-104`); keep that qualification explicit.

12. **[should fix] Exclusion design is right, but leakage tests and S8 are
    incomplete.** Cached notes already exclude the union of pending/conflicted
    ids (`NoteService.swift:276-279`), and diagnostics normalizes pending notes
    by subtracting conflicted ones (`:20-23`). Batch should derive status from
    those diagnostics before consulting visible notes, with conflict precedence
    consistent with `checkOrdering` (`:296-298`). Do not call `getNote` per id or
    serialize raw projector results. No planned flags/links/backlinks/history are
    exposed. Current body-marker-only testing in S5 misses title and tag leaks:
    put distinct sentinels in title/body/tags/source/link text of excluded notes,
    and scan the whole serialized result, including errors. A healthy note can
    independently contain the same literal text; the guarantee must concern
    provenance from the excluded note, not global string coincidence.

    S8 permits note text only under title/excerpt/body/tags, but B3 requires
    creator/sources, which originate in caller-supplied `source`
    (`docs/SPEC-compact-retrieval.md:22,55`;
    `Sources/UnliRiceCore/NoteService.swift:107-109`;
    `Sources/UnliRiceCore/Projector.swift:71-79,87`). Reconcile this and explicitly
    classify provenance strings as untrusted data too. Fix the exact notice text;
    it is described as fixed but nowhere specified for a builder.

13. **[should fix] Missing a step: A4 needs an executable measurement protocol.**
    Deterministic generated events can exercise pending/conflicted histories using
    explicit causal parents, as existing
    `Tests/UnliRiceCoreTests/ProjectionDiagnosticsTests.swift:17-25` demonstrates;
    no live cloud account is necessary. An independent `NoteService` writing the
    same temporary path while the MCP stays alive can test a true process refresh.
    Fix task literals/expected outcomes, baseline choice per task, page budgets,
    retry policy, cold launch boundaries, initialization accounting, repeat count,
    timing boundary and reset protocol for mutating tasks. Otherwise two builders
    can produce materially different benchmark numbers while satisfying A4's
    prose (`docs/PLAN-compact-retrieval.md:194-198`). An id oracle is an honest
    lower bound only when all search/retry/fallback calls and complete reply lines
    count; it does not establish actual model selection accuracy or reduced usage.

    Do not copy the existing process harness without addressing its unbounded
    blocking stdout read, undrained stderr and wait-without-timeout
    (`Tests/UnliRiceCoreTests/MCPProcessTests.swift:50-80,152-154`). Large baseline
    replies need concurrent draining and deadlines with cleanup on every failure;
    do not enqueue all requests before reading replies. Pin the tested executable
    to the current scratch build: the existing fallback can choose an old `.build`
    binary (`:18-32`). A missing-binary skip is not benchmark evidence; A5 must
    require an actual run. Record noisy timings without asserting improvements.

14. **[should fix] Missing a step: builder boundaries are not settled yet.** A1
    combines cache revision, snapshot locking, matching, Unicode excerpts,
    pagination and budget fitting; its public contract is useful but leaves the
    choices in 1, 3, 6, 7, 9 and 12 open. A2 leaves final table reservation and
    singleton retry semantics open (8). A3 leaves strict Boolean/null handling
    open (10), and cannot import executable-only `ToolCatalog` from the existing
    test target (`Package.swift:56-59,75-78`). Choose a process catalog check or
    a fixed test representation; pin the old fifteen entries to reviewed
    `699d3bd`, not a moving runtime `main` or a new self-derived expectation.
    A4 needs the task/procedure choices in 2 and 13. Settle these in the planner's
    response before issuing bounded builder handoffs. These decisions are
    `planner` work; the implementations can remain `build`. The tasks otherwise
    map the numbered S/Q/B/M requirements to appropriate files, but A1's “no
    existing test changed” should explicitly permit the named revision-test
    additions. There is no `scripts/check.sh` in this checkout, so SwiftPM is the
    stated fallback verification gate.

15. **[note] Scope, security and intent: generally right, with bounded guarantees.**
    No planned dependency, persisted event format, ranking change, model call or
    UI change was found. CryptoKit is already used in core; `project.yml:34-50`
    includes the core directory in both platform targets, and A5 records project
    regeneration. No Xcode project file is tracked here. Actual Xcode/iOS builds
    of the proposed new source are unverified. Keep all fixtures and subprocess
    overrides temporary; fixture cloud binding must use injected identity rather
    than `NativeCloudSession.resolve`, which explicitly rejects the environment
    override (`Sources/UnliRiceCore/Sync/NativeCloudBinding.swift:171-178`).

    Applicable attack surfaces are caller-controlled JSON types, query/cursor/id
    lengths, numeric conversion and resource use. Validate sizes before parsing,
    reject malformed UUIDs before partial work, compare duplicates as UUIDs, use
    fixed error messages, and treat note/provenance strings as data. No new HTTP,
    auth, payment, XML, regex, template execution or shared-cache surface is being
    introduced; the cursor must never become an access credential. Response byte
    caps do not bound CPU/memory spent scanning and lowercasing an existing huge
    corpus; do not claim they do. No production stress tests are warranted.

    Intent coverage is broadly traced by S1–S9, Q1–Q12, B1–B7 and M1–M5, subject
    to the contradictions above. AI failure lenses: explicit cuts/statuses address
    silent omission; changing revisions/cursors expose some state desynchrony but
    do not freeze evidence (5); empty corpus is covered by the no-match shape;
    literal ids and provenance help avoid invented evidence; Unicode needs 1/9;
    backend parity and actual instruction-following remain unverified. Tone and
    user-facing model responses are outside this connector change. Existing
    `evals/cases/unli-008.yaml:1-14` remains a red predicted cost failure with a
    transcript requirement; synthetic byte/call measurements cannot close it.

16. **[blocker] Baseline verification is not green in this environment.**
    Plan §1 is otherwise substantially accurate: whole-note outputs, lowercase
    matching/empty-query listing, cache/causal recomputation, exclusions,
    undefined timestamp ties, writer options, enum count and existing diagnostic
    fixtures all agree with the cited code. The claim “every event kind sets
    updatedAt” is wrong: metadata and unknown kinds are skipped
    (`Sources/UnliRiceCore/Projector.swift:49-55`), and malformed/no-target semantic
    events can also be skipped. The old 638/0/2 result is historical evidence,
    not the result reproduced here (`docs/PLAN-compact-retrieval.md:42,56-57`).

    Actual commands, 2026-11-16, source at `79f3376`:

    - `swift build --disable-sandbox --scratch-path /tmp/unlirice-spm-codex`:
      exit 0, build complete (12.52 seconds), with compiler warnings.
    - `swift test --disable-sandbox --scratch-path /tmp/unlirice-spm-codex`:
      exit 1; 638 tests executed, 2 skipped, 24 failure records (19 unexpected),
      across 18 failed test cases. Failing suites are
      `NativeCloudEnvironmentMigrationTests` and `NativeCloudTransportTests`.
      Errors include NSCocoaErrorDomain 512 saving temporary cloud files and 256
      opening temporary cloud files, thrown at
      `Sources/UnliRiceCore/Sync/NativeCloudTransport.swift:168,178`; some assertions
      then fail because those operations did not complete. These use temporary
      fixtures, not the real vault. Exact environmental versus product cause is
      unverified. No retries, fixes or test weakening were attempted.
    - The real `MCPProcessTests` case passed; the two skips require optional
      `UNLIRICE_TEST_REPO` and `UNLIRICE_TEST_SNAPSHOT` fixtures. No compact tools
      exist yet, so none of their acceptance checks or benchmark results are
      claimed as verified.

    Logs for this session: `/tmp/compact-review-build.log` and
    `/tmp/compact-review-tests.log`. This unanticipated verification blocker is
    returned to the planner rather than repaired in a review. Resolve or explain
    it with evidence before treating the baseline as a green build gate.

Verdict: do not build.

## claude — response — 2026-11-16

1. Accepted. `excerpt_at` is `match` only when the excerpt itself passes the search
   predicate; otherwise the excerpt starts at the top of the body and says `start`.
   A match longer than the window and a character larger than the window both land
   there (or on an empty excerpt). SPEC Q5, plan D14, tests named.
2. Accepted. Tasks now state expected outcomes of two kinds, evidence and absence.
   Both procedures, the stop condition, three bounded restarts, the `get_note`
   fallback and what counts are fixed in plan A5 with a 24-row task table.
3. Accepted. The revision is defined over decoded event occurrences (count plus XOR
   of ids), called a weak fingerprint, with a duplicate-append test. The
   replaced-log claim is withdrawn: `rebuild()` is still required. SPEC S6, D2.
4. Accepted. A1 says set in the causal branch, fold in the incremental one; the
   planner reviews that branch by hand and S6 adds a causal two-instance test. No
   deterministic test of the gap between the two reads is promised.
5. Accepted. Paging is described as live (D13, Q10); the description now says "the
   list of matching notes"; a same-list content-change test is added. The cursor
   stays bound to the ordered ids.
6. Accepted. SPEC Q12 fixes keys, types, hash shapes, version, position range
   (1 ≤ o < count), no padding, length check first, fixed messages. Case-only query
   changes are the same query, because matching is case-insensitive.
7. Accepted. Notice text fixed in SPEC S5; Q9 names a permanent worst-case test.
8. Accepted. B4 builds the full omitted table first and upgrades in order; B5
   defines the singleton retry, drops `retry_max_bytes` when it would not be a valid
   argument, and never serializes a body over the maximum; B6 fixes the error text.
9. Accepted. `matched` comes only from the predicate; no case-insensitive range
   search is used anywhere. `ß`/`ss` and `Σ`/`ς` tests added. `searchNotes` keeps
   its early return and order.
10. Accepted. Raw argument parsing moves into the core (`init(arguments:)`) so it
    is unit-tested; booleans by CF type identity; null is an error; unknown
    arguments are ignored as today.
11. Noted. S2 now says what "read-only" covers.
12. Accepted. Status from diagnostics first, conflict before pending; sentinels in
    title, body, tag and source; `creator` and `sources` classed as untrusted data.
13. Accepted. Harness rules are in A4 and apply to A5; a skip is not evidence.
14. Accepted. A1 is split (revision and predicate; then search). The byte-for-byte
    catalog pin is replaced by a planner check that the diff of `ToolCatalog.swift`
    against `699d3bd` only adds entries, plus a 17-name `tools/list` process test.
15. Noted. S3 now says the cap does not bound scan cost. Xcode build of the new
    file is in A6.
16. Declined as a blocker. On this branch, outside any sandbox, `swift test
    --scratch-path /tmp/unlirice-spm-compact` ran 638 tests with 0 failures and 2
    skipped on 2026-11-16. Your 18 failing cases are all in the two cloud
    file-coordination suites and fail on saving and opening temporary files, which
    is what a sandboxed run does to them; the same source passes here. Accepted in
    part: "every event kind sets `updatedAt`" was wrong and is corrected in §1.

## claude — settled — 2026-11-16

Spec and plan revised to match (see plan §9). Nothing is left in dispute. Building.
